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
    /// 资金曲线时序（v15.5 · accountChanged 时追加 · 限 maxEquityPoints 防内存膨胀）
    private var equityCurve: [EquityCurvePoint] = []
    /// 资金曲线最大点数（5000 点足够覆盖一日盘中分钟级采样）
    private let maxEquityPoints: Int = 5000
    /// v15.16 hotfix #11：每合约最近 lastPrice 缓存 · 多合约浮盈正确计算
    /// 之前 recomputePositionPnL 用 openAvgPrice 当其他 instrument mark · 浮盈丢失
    private var instrumentLastPrice: [String: Decimal] = [:]

    // MARK: - 初始化

    public init(initialBalance: Decimal, contracts: [String: Contract] = [:], now: Date = Date()) {
        self.account = Self.freshAccount(initialBalance: initialBalance)
        self.contracts = contracts
        // v15.5 起始 baseline：曲线起点 = 初始权益 · 后续 accountChanged 追加
        self.equityCurve.append(
            EquityCurvePoint(timestamp: now, balance: initialBalance, positionPnL: 0)
        )
    }

    /// 全零字段 + 给定 preBalance 的初始账户（init / reset 共用）
    private static func freshAccount(initialBalance: Decimal) -> Account {
        Account(
            preBalance: initialBalance,
            deposit: 0, withdraw: 0,
            closePnL: 0, positionPnL: 0,
            commission: 0, margin: 0
        )
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

    /// v15.5 资金曲线快照（已按时间序 · 起始 baseline 永远是 index 0）
    public func equityCurveSnapshot() -> [EquityCurvePoint] { equityCurve }

    // MARK: - 持久化（v15.6 · 完整状态快照导出 / 导入）

    /// 导出当前完整状态用于持久化
    /// orders / positions 排序固定（按 orderRef / positionKey）· 跨进程 snapshot 可 diff
    public func snapshot() -> SimulatedTradingSnapshot {
        SimulatedTradingSnapshot(
            account: account,
            orders: orders.values.sorted { $0.orderRef < $1.orderRef },
            trades: trades,
            positions: positions.values.sorted {
                Self.positionKey(instrumentID: $0.instrumentID, direction: $0.direction)
                    < Self.positionKey(instrumentID: $1.instrumentID, direction: $1.direction)
            },
            equityCurve: equityCurve,
            orderRefCounter: orderRefCounter,
            tradeIDCounter: tradeIDCounter,
            instrumentLastPrice: instrumentLastPrice  // v15.17 · 多合约浮盈缓存持久化
        )
    }

    /// 从快照恢复 · 完整覆盖当前状态（warning：丢失订阅者 · UI 应在 restore 后重新 observe）
    /// 不广播任何事件 · caller 自己刷新 UI（避免恢复期间 UI 收 N 条历史 events）
    public func restore(_ snap: SimulatedTradingSnapshot) {
        account = snap.account
        orders = Dictionary(uniqueKeysWithValues: snap.orders.map { ($0.orderRef, $0) })
        trades = snap.trades
        positions = Dictionary(uniqueKeysWithValues: snap.positions.map {
            (Self.positionKey(instrumentID: $0.instrumentID, direction: $0.direction), $0)
        })
        equityCurve = snap.equityCurve
        orderRefCounter = snap.orderRefCounter
        tradeIDCounter = snap.tradeIDCounter
        instrumentLastPrice = snap.instrumentLastPrice  // v15.17 · 重启后多合约浮盈立即正确 · 不等下一次 onTick
    }

    /// 重置为初始状态（保留已注册合约 · 重新建 baseline）
    public func reset(initialBalance: Decimal, now: Date = Date()) {
        account = Self.freshAccount(initialBalance: initialBalance)
        orders.removeAll()
        trades.removeAll()
        positions.removeAll()
        equityCurve = [EquityCurvePoint(timestamp: now, balance: initialBalance, positionPnL: 0)]
        orderRefCounter = 0
        tradeIDCounter = 0
        instrumentLastPrice.removeAll()  // v15.17 · reset 一并清 markPrice 缓存（防错误浮盈）
    }

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
            broadcast(.accountChanged(account), now: now)
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
        broadcast(.orderSubmitted(record), now: now)
        return (ref, nil)
    }

    /// 撤单 · 仅 active 委托可撤 · 释放预占保证金（开仓单）
    @discardableResult
    public func cancelOrder(orderRef: String, now: Date = Date()) -> Bool {
        guard var record = orders[orderRef], record.status.isActive else { return false }

        // 释放预占保证金（开仓单）
        if record.offsetFlag == .open, let contract = contracts[record.instrumentID] {
            let margin = openMargin(contract: contract, price: record.price, volume: record.remainingVolume, direction: record.direction)
            account.margin -= margin
            broadcast(.accountChanged(account), now: now)
        }

        record.status = .cancelled
        record.statusMessage = "用户撤单"
        orders[orderRef] = record
        broadcast(.orderCancelled(record), now: now)
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
        // 撮合后更新持仓盈亏 → 账户 positionPnL（共用同一 now · 曲线时间戳与 tick 同源）
        recomputePositionPnL(lastPrice: lastPrice, instrumentID: tick.instrumentID, now: now)
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
            applyOpen(record: record, contract: contract, fillPrice: matchPrice, fillVolume: fillVolume, now: now)
        } else {
            applyClose(record: record, fillPrice: matchPrice, fillVolume: fillVolume, now: now)
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
        broadcast(.orderFilled(record, trade), now: now)
        broadcast(.accountChanged(account), now: now)
    }

    /// 开仓：建仓 / 加仓 · 锁定保证金（已在 submit 时预占 · 此处转 position.margin）
    private func applyOpen(record: OrderRecord, contract: Contract, fillPrice: Decimal, fillVolume: Int, now: Date) {
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
            broadcast(.positionChanged(existing), now: now)
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
            broadcast(.positionChanged(pos), now: now)
        }
    }

    /// 平仓：减仓 · 释放保证金 · 计算 closePnL
    private func applyClose(record: OrderRecord, fillPrice: Decimal, fillVolume: Int, now: Date) {
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
        // TODO v15.16 hotfix #13：v2 接 contract.feeStructure 后区分平今 / 平昨 · 上期所平今平昨手续费倒挂
        // 当前 v1 hardcoded 5 元/手 · 不区分对账户无影响 · 但 OffsetFlag.close（平昨语义）应优先扣 yesterdayVolume
        // 修法：if request.offsetFlag == .closeToday { todayVolume -= } else { yesterdayVolume -= todayVolume 留 }
        pos.volume -= fillVolume
        pos.todayVolume = max(0, pos.todayVolume - fillVolume)
        positions[key] = (pos.volume == 0) ? nil : pos
        broadcast(.positionChanged(pos), now: now)
    }

    /// 重新计算所有持仓的浮盈 → 汇总到 account.positionPnL
    /// v15.16 hotfix #11：用 instrumentLastPrice 缓存按合约取 mark · 修多合约浮盈丢失
    /// 之前用 openAvgPrice 让其他 instrument 浮盈强制为 0 · 同时持仓 ag 多头浮盈 +500 + rb tick 来时 ag 浮盈被覆盖
    private func recomputePositionPnL(lastPrice: Decimal, instrumentID: String, now: Date = Date()) {
        // 更新当前 instrument 缓存
        instrumentLastPrice[instrumentID] = lastPrice
        var totalPnL: Decimal = 0
        for pos in positions.values where pos.volume > 0 {
            // 优先取该合约缓存价 · fallback 开仓价（首次该合约 tick 未到达时浮盈 = 0 合理）
            let mark: Decimal = instrumentLastPrice[pos.instrumentID] ?? pos.openAvgPrice
            totalPnL += pos.floatingPnL(currentPrice: mark)
        }
        if account.positionPnL != totalPnL {
            account.positionPnL = totalPnL
            broadcast(.accountChanged(account), now: now)
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

    private func broadcast(_ event: SimulatedTradingEvent, now: Date = Date()) {
        // v15.5 资金曲线：accountChanged 时追加点（去重相邻同 balance · 防 onTick 高频空 yield 撑爆）
        if case .accountChanged(let acc) = event {
            let last = equityCurve.last
            if last?.balance != acc.balance || last?.positionPnL != acc.positionPnL {
                equityCurve.append(EquityCurvePoint(timestamp: now, balance: acc.balance, positionPnL: acc.positionPnL))
                if equityCurve.count > maxEquityPoints {
                    equityCurve.removeFirst(equityCurve.count - maxEquityPoints)
                }
            }
        }
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
        broadcast(.orderRejected(orderRef: ref, reason: reason), now: now)
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
