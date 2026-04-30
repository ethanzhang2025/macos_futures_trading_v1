// WP-54 v15.3 · 模拟撮合引擎（M5 · SimNow 模拟训练核心）
//
// 职责：
// - submitOrder：本地校验 + 检查保证金/持仓 + 入 active orders
// - onTick：所有 active orders 按 lastPrice 撮合 · 命中即全部成交（v1 不分笔）
// - cancelOrder：取消 active 订单（已成交不可撤）
// - 撮合后：更新持仓 / 账户 / 推送事件
//
// 设计要点（Karpathy "避免过度复杂"）：
// - actor 隔离并发安全 · 所有状态改动单线程化
// - v1 仅支持限价单：买 lastPrice ≤ price 成交 / 卖 lastPrice ≥ price 成交（撮合价 = lastPrice · 模拟"对手价比限价更优"理想情况）
// - 市价单：v1 不支持（OrderRecord 未持有 priceType · submitOrder 校验时仍按限价校验 price>0）· v2 加 priceType 后再实现
// - 持仓：每合约最多 2 个 Position（long + short · 锁仓单独立记账）· 平仓减 volume + 释放保证金
// - 手续费：v1 hardcoded 5 元/手 · v2 接 contract.feeStructure
// - 平今/平昨：上期所/能源中心区分 · v1 直接按 OffsetFlag 处理 · 不区分手续费

import Foundation
import Shared

/// 模拟撮合引擎
public actor SimulatedTradingEngine {

    // MARK: - 配置

    /// v1 固定手续费：5 元/手（开 + 平各收一次 · v2 接 contract.feeStructure 区分）
    public static let fixedCommissionPerLot: Decimal = 5

    // MARK: - 状态

    private var account: Account
    private var contracts: [String: Contract]
    /// 所有委托记录（含 active / filled / cancelled / rejected · key = orderRef）
    private var orders: [String: OrderRecord] = [:]
    /// 所有成交记录（v1 一笔一个 · 委托完整成交则只有 1 笔）
    private var trades: [TradeRecord] = []
    /// 持仓快照（key = instrumentID + direction · 多/空分开记账）
    private var positions: [String: Position] = [:]
    /// 事件订阅 continuations
    private var continuations: [UUID: AsyncStream<SimulatedTradingEvent>.Continuation] = [:]
    /// 委托序号自增（订单 ref 用）· UUID 太长 · 用 8 位字符串
    private var orderRefCounter: Int = 0
    /// 成交序号自增（trade ID 用 · "T" 前缀 + 8 位）
    private var tradeIDCounter: Int = 0

    // MARK: - 初始化

    public init(initialBalance: Decimal, contracts: [String: Contract] = [:]) {
        self.account = Account(
            preBalance: initialBalance,
            deposit: 0, withdraw: 0,
            closePnL: 0, positionPnL: 0,
            commission: 0, margin: 0
        )
        self.contracts = contracts
    }

    // MARK: - 配置 API（运行时新增 / 替换合约）

    public func registerContract(_ contract: Contract) {
        contracts[contract.instrumentID] = contract
    }

    public func registerContracts(_ list: [Contract]) {
        for c in list { contracts[c.instrumentID] = c }
    }

    // MARK: - 查询 API

    public func currentAccount() -> Account { account }

    public func allPositions() -> [Position] { Array(positions.values).filter { $0.volume > 0 } }

    public func position(instrumentID: String, direction: PositionDirection) -> Position? {
        positions[Self.positionKey(instrumentID: instrumentID, direction: direction)]
    }

    public func allOrders() -> [OrderRecord] { Array(orders.values).sorted { $0.orderRef < $1.orderRef } }

    public func activeOrders() -> [OrderRecord] {
        allOrders().filter { $0.status.isActive }
    }

    public func allTrades() -> [TradeRecord] { trades }

    public func contract(_ instrumentID: String) -> Contract? { contracts[instrumentID] }

    public func allContracts() -> [Contract] { Array(contracts.values) }

    // MARK: - 事件订阅

    public func observe() -> AsyncStream<SimulatedTradingEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - 下单

    /// 下单 · 返回 (orderRef, 拒绝原因) · 拒绝原因 nil 表示成功提交（已入 active orders 等待撮合）
    @discardableResult
    public func submitOrder(_ request: OrderRequest, now: Date = Date()) -> (orderRef: String, rejection: OrderRejectReason?) {
        let ref = nextOrderRef()
        func reject(_ reason: OrderRejectReason) -> (orderRef: String, rejection: OrderRejectReason?) {
            recordRejection(ref: ref, request: request, now: now, reason: reason)
            return (ref, reason)
        }

        // 基础参数校验
        guard request.volume > 0 else { return reject(.invalidVolume(request.volume)) }
        if request.priceType == .limitPrice && request.price <= 0 {
            return reject(.invalidPrice(request.price))
        }
        guard let contract = contracts[request.instrumentID] else {
            return reject(.unknownInstrument(request.instrumentID))
        }

        // 开仓：检查可用资金 · 锁定保证金
        if request.offsetFlag == .open {
            let marginNeeded = openMargin(contract: contract, price: request.price, volume: request.volume, direction: request.direction)
            if account.available < marginNeeded {
                return reject(.insufficientFunds(required: marginNeeded, available: account.available))
            }
            // 锁定保证金（资金可用减 · 撮合时再正式扣到 position.margin）
            account.margin += marginNeeded
            broadcast(.accountChanged(account))
        } else {
            // 平仓：检查持仓
            let posDirection: PositionDirection = (request.direction == .sell) ? .long : .short
            let availableVolume = position(instrumentID: request.instrumentID, direction: posDirection)?.volume ?? 0
            if availableVolume < request.volume {
                return reject(.insufficientPosition(direction: posDirection, required: request.volume, available: availableVolume))
            }
        }

        // 入 active orders
        let record = OrderRecord(
            orderRef: ref,
            instrumentID: request.instrumentID,
            direction: request.direction,
            offsetFlag: request.offsetFlag,
            price: request.price,
            totalVolume: request.volume,
            filledVolume: 0,
            status: .submitted,
            insertTime: Self.timeFormatter.string(from: now),
            statusMessage: ""
        )
        orders[ref] = record
        broadcast(.orderSubmitted(record))
        return (ref, nil)
    }

    /// 撤单 · 仅 active 委托可撤 · 释放预占保证金（开仓单）
    @discardableResult
    public func cancelOrder(orderRef: String) -> Bool {
        guard var record = orders[orderRef], record.status.isActive else { return false }

        // 释放预占保证金（开仓单）
        if record.offsetFlag == .open, let contract = contracts[record.instrumentID] {
            let margin = openMargin(contract: contract, price: record.price, volume: record.remainingVolume, direction: record.direction)
            account.margin -= margin
            broadcast(.accountChanged(account))
        }

        record.status = .cancelled
        record.statusMessage = "用户撤单"
        orders[orderRef] = record
        broadcast(.orderCancelled(record))
        return true
    }

    // MARK: - 撮合驱动（onTick）

    /// 按 Tick 撮合所有 active 委托 · 命中即全部成交（v1 不分笔）
    public func onTick(_ tick: Tick, now: Date = Date()) {
        let lastPrice = tick.lastPrice
        // 按 orderRef 排序确保撮合顺序确定（测试可重现）
        let activeRefs = orders.values
            .filter { $0.status.isActive && $0.instrumentID == tick.instrumentID }
            .map(\.orderRef)
            .sorted()
        for ref in activeRefs {
            guard var record = orders[ref], record.status.isActive else { continue }
            guard let matchPrice = matchPrice(record: record, lastPrice: lastPrice) else { continue }
            fillOrder(&record, matchPrice: matchPrice, now: now)
            // 字典 subscript 不支持 inout · fillOrder 修改的是本地副本 · 这里写回最终态
            orders[ref] = record
        }
        // 撮合后更新持仓盈亏 → 账户 positionPnL
        recomputePositionPnL(lastPrice: lastPrice, instrumentID: tick.instrumentID)
    }

    // MARK: - 私有：撮合

    /// 匹配价 · nil 表示未触达（v1 限价单语义 · 撮合价 = lastPrice）
    private func matchPrice(record: OrderRecord, lastPrice: Decimal) -> Decimal? {
        switch record.direction {
        case .buy:
            // 买单 · lastPrice ≤ limit 成交（市场价比我开价更便宜 · 优先成交）
            return lastPrice <= record.price ? lastPrice : nil
        case .sell:
            return lastPrice >= record.price ? lastPrice : nil
        }
    }

    /// 完整成交（v1 一次性全成）· 更新 record / trades / positions / account
    private func fillOrder(_ record: inout OrderRecord, matchPrice: Decimal, now: Date) {
        let fillVolume = record.remainingVolume
        record.filledVolume = record.totalVolume
        record.status = .filled
        guard let contract = contracts[record.instrumentID] else { return }

        let commission = Self.fixedCommissionPerLot * Decimal(fillVolume)
        account.commission += commission

        if record.offsetFlag == .open {
            applyOpen(record: record, contract: contract, fillPrice: matchPrice, fillVolume: fillVolume)
        } else {
            applyClose(record: record, fillPrice: matchPrice, fillVolume: fillVolume)
        }

        let trade = TradeRecord(
            tradeID: nextTradeID(),
            orderRef: record.orderRef,
            instrumentID: record.instrumentID,
            direction: record.direction,
            offsetFlag: record.offsetFlag,
            price: matchPrice,
            volume: fillVolume,
            tradeTime: Self.timeFormatter.string(from: now),
            commission: commission
        )
        trades.append(trade)
        broadcast(.orderFilled(record, trade))
        broadcast(.accountChanged(account))
    }

    /// 开仓：建仓 / 加仓 · 锁定保证金（已在 submit 时预占 · 此处转 position.margin）
    private func applyOpen(record: OrderRecord, contract: Contract, fillPrice: Decimal, fillVolume: Int) {
        let posDirection: PositionDirection = (record.direction == .buy) ? .long : .short
        let key = Self.positionKey(instrumentID: record.instrumentID, direction: posDirection)
        let margin = openMargin(contract: contract, price: fillPrice, volume: fillVolume, direction: record.direction)

        if var existing = positions[key] {
            // 加仓：均价加权
            let oldNotional = existing.openAvgPrice * Decimal(existing.volume)
            let addNotional = fillPrice * Decimal(fillVolume)
            let newVolume = existing.volume + fillVolume
            existing.volume = newVolume
            existing.todayVolume += fillVolume
            existing.openAvgPrice = (oldNotional + addNotional) / Decimal(newVolume)
            existing.avgPrice = existing.openAvgPrice
            existing.margin += margin
            positions[key] = existing
            broadcast(.positionChanged(existing))
        } else {
            let pos = Position(
                instrumentID: record.instrumentID,
                direction: posDirection,
                volume: fillVolume,
                todayVolume: fillVolume,
                avgPrice: fillPrice,
                openAvgPrice: fillPrice,
                preSettlementPrice: fillPrice,   // v1 简化：用开仓价代替昨结算（盯市浮盈基于此）
                margin: margin,
                volumeMultiple: contract.volumeMultiple
            )
            positions[key] = pos
            broadcast(.positionChanged(pos))
        }
    }

    /// 平仓：减仓 · 释放保证金 · 计算 closePnL
    private func applyClose(record: OrderRecord, fillPrice: Decimal, fillVolume: Int) {
        let posDirection: PositionDirection = (record.direction == .sell) ? .long : .short
        let key = Self.positionKey(instrumentID: record.instrumentID, direction: posDirection)
        guard var pos = positions[key] else { return }

        // 释放保证金：按比例（fillVolume / pos.volume）
        let releasedMargin = pos.margin * Decimal(fillVolume) / Decimal(pos.volume)
        pos.margin -= releasedMargin
        account.margin -= releasedMargin

        // 平仓盈亏
        let priceDiff: Decimal = (posDirection == .long)
            ? (fillPrice - pos.openAvgPrice)
            : (pos.openAvgPrice - fillPrice)
        let pnl = priceDiff * Decimal(fillVolume) * Decimal(pos.volumeMultiple)
        account.closePnL += pnl

        // 减持仓（todayVolume 优先扣 · 清仓后从 dict 删除 · 推 volume=0 快照让 UI 感知清仓）
        pos.volume -= fillVolume
        pos.todayVolume = max(0, pos.todayVolume - fillVolume)
        positions[key] = (pos.volume == 0) ? nil : pos
        broadcast(.positionChanged(pos))
    }

    /// 重新计算所有持仓的浮盈 → 汇总到 account.positionPnL
    private func recomputePositionPnL(lastPrice: Decimal, instrumentID: String) {
        var totalPnL: Decimal = 0
        for pos in positions.values where pos.volume > 0 {
            // 仅当前 instrument 用 tick lastPrice · 其他持仓保持已有 markPrice（v1 简化为开仓价 → 浮盈 0）
            let mark: Decimal = (pos.instrumentID == instrumentID) ? lastPrice : pos.openAvgPrice
            totalPnL += pos.floatingPnL(currentPrice: mark)
        }
        if account.positionPnL != totalPnL {
            account.positionPnL = totalPnL
            broadcast(.accountChanged(account))
        }
    }

    // MARK: - 私有：保证金计算

    private func openMargin(contract: Contract, price: Decimal, volume: Int, direction: Direction) -> Decimal {
        let notional = price * Decimal(volume) * Decimal(contract.volumeMultiple)
        let ratio: Decimal = (direction == .buy) ? contract.longMarginRatio : contract.shortMarginRatio
        return notional * ratio
    }

    // MARK: - 私有：序号生成

    private func nextOrderRef() -> String {
        orderRefCounter += 1
        return String(format: "%08d", orderRefCounter)
    }

    private func nextTradeID() -> String {
        tradeIDCounter += 1
        return "T\(String(format: "%08d", tradeIDCounter))"
    }

    // MARK: - 私有：事件广播

    private func broadcast(_ event: SimulatedTradingEvent) {
        for cont in continuations.values { cont.yield(event) }
    }

    /// 拒绝路径统一收口：写 record(rejected) + 推送事件
    private func recordRejection(ref: String, request: OrderRequest, now: Date, reason: OrderRejectReason) {
        let record = OrderRecord(
            orderRef: ref,
            instrumentID: request.instrumentID,
            direction: request.direction,
            offsetFlag: request.offsetFlag,
            price: request.price,
            totalVolume: request.volume,
            filledVolume: 0,
            status: .rejected,
            insertTime: Self.timeFormatter.string(from: now),
            statusMessage: reason.displayMessage
        )
        orders[ref] = record
        broadcast(.orderRejected(orderRef: ref, reason: reason))
    }

    // MARK: - 私有：辅助

    private static func positionKey(instrumentID: String, direction: PositionDirection) -> String {
        "\(instrumentID).\(direction == .long ? "L" : "S")"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
