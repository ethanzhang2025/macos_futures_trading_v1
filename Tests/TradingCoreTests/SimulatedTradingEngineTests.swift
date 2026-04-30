// WP-54 v15.3 · 模拟撮合引擎测试
// 覆盖：下单校验 / 撮合触发 / 撤单 / 持仓更新 / 平仓盈亏 / 资金校验 / 事件流

import Testing
import Foundation
import Shared
@testable import TradingCore

// MARK: - 辅助：合约 / Tick / 委托工厂

private func makeContract(
    instrumentID: String = "rb2501",
    volumeMultiple: Int = 10,
    longMargin: Decimal = Decimal(string: "0.10")!,
    shortMargin: Decimal = Decimal(string: "0.10")!
) -> Contract {
    Contract(
        instrumentID: instrumentID,
        instrumentName: "螺纹钢2501",
        exchange: .SHFE,
        productID: "rb",
        volumeMultiple: volumeMultiple,
        priceTick: 1,
        deliveryMonth: 202501,
        expireDate: "20250115",
        longMarginRatio: longMargin,
        shortMarginRatio: shortMargin,
        isTrading: true,
        productName: "螺纹钢",
        pinyinInitials: "LWG"
    )
}

private func makeTick(_ price: Decimal, instrumentID: String = "rb2501", volume: Int = 1) -> Tick {
    Tick(
        instrumentID: instrumentID, lastPrice: price, volume: volume,
        openInterest: 0, turnover: 0,
        bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
        highestPrice: 0, lowestPrice: 0, openPrice: 0,
        preClosePrice: 0, preSettlementPrice: 0,
        upperLimitPrice: 0, lowerLimitPrice: 0,
        updateTime: "10:00:00", updateMillisec: 0,
        tradingDay: "20250101", actionDay: "20250101"
    )
}

private func makeOpenOrder(
    direction: Direction = .buy,
    price: Decimal = 3500,
    volume: Int = 1,
    instrumentID: String = "rb2501"
) -> OrderRequest {
    OrderRequest(
        instrumentID: instrumentID, direction: direction, offsetFlag: .open,
        priceType: .limitPrice, price: price, volume: volume
    )
}

private func makeCloseOrder(
    direction: Direction,
    price: Decimal = 3600,
    volume: Int = 1,
    instrumentID: String = "rb2501"
) -> OrderRequest {
    OrderRequest(
        instrumentID: instrumentID, direction: direction, offsetFlag: .close,
        priceType: .limitPrice, price: price, volume: volume
    )
}

// MARK: - 1. 下单校验

/// 仅比较 OrderRejectReason 的 case · 不比较关联值（关联值在专门的断言中校验）
private func expectRejection(
    _ rejection: OrderRejectReason?,
    matches expected: OrderRejectReason,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let rejection else {
        Issue.record("expected \(expected), got nil", sourceLocation: sourceLocation)
        return
    }
    let same: Bool
    switch (rejection, expected) {
    case (.unknownInstrument, .unknownInstrument),
         (.insufficientFunds, .insufficientFunds),
         (.insufficientPosition, .insufficientPosition),
         (.invalidPrice, .invalidPrice),
         (.invalidVolume, .invalidVolume):
        same = true
    default:
        same = false
    }
    if !same {
        Issue.record("expected \(expected), got \(rejection)", sourceLocation: sourceLocation)
    }
}

@Suite("SimulatedTradingEngine · 下单校验")
struct SubmitValidationTests {

    @Test("未注册合约 → 拒绝 unknownInstrument")
    func unknownInstrument() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        let (_, rejection) = await engine.submitOrder(makeOpenOrder())
        expectRejection(rejection, matches: .unknownInstrument("rb2501"))
        if case .unknownInstrument(let id) = rejection {
            #expect(id == "rb2501")
        }
    }

    @Test("数量 ≤ 0 → 拒绝 invalidVolume")
    func invalidVolume() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (_, rejection) = await engine.submitOrder(makeOpenOrder(volume: 0))
        expectRejection(rejection, matches: .invalidVolume(0))
    }

    @Test("限价 price ≤ 0 → 拒绝 invalidPrice")
    func invalidPrice() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (_, rejection) = await engine.submitOrder(makeOpenOrder(price: 0))
        expectRejection(rejection, matches: .invalidPrice(0))
    }

    @Test("资金不足 → 拒绝 insufficientFunds")
    func insufficientFunds() async {
        // 1 手 rb2501 · price=3500 · volumeMultiple=10 · longMargin=0.10 → 保证金 3500
        // 给 1000 余额 · 必拒
        let engine = SimulatedTradingEngine(initialBalance: 1_000)
        await engine.registerContract(makeContract())
        let (_, rejection) = await engine.submitOrder(makeOpenOrder())
        expectRejection(rejection, matches: .insufficientFunds(required: 0, available: 0))
    }

    @Test("平仓但无持仓 → 拒绝 insufficientPosition")
    func insufficientPosition() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (_, rejection) = await engine.submitOrder(makeCloseOrder(direction: .sell))
        expectRejection(rejection, matches: .insufficientPosition(direction: .long, required: 0, available: 0))
    }

    @Test("正常下单 · rejection=nil + record.status=submitted")
    func normalSubmit() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (ref, rejection) = await engine.submitOrder(makeOpenOrder())
        #expect(rejection == nil)
        let active = await engine.activeOrders()
        #expect(active.count == 1)
        #expect(active.first?.orderRef == ref)
        #expect(active.first?.status == .submitted)
    }
}

// MARK: - 2. 撮合 onTick

@Suite("SimulatedTradingEngine · onTick 撮合")
struct OnTickMatchTests {

    @Test("买单限价 · lastPrice ≤ price 触发成交")
    func buyLimitFill() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (ref, _) = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 2))

        // 价格 3499 ≤ 3500 → 成交
        await engine.onTick(makeTick(3499))
        let order = await engine.allOrders().first { $0.orderRef == ref }
        #expect(order?.status == .filled)
        #expect(order?.filledVolume == 2)

        // 持仓多头 2 手 · 开仓均价 = 3499（撮合价）
        let pos = await engine.position(instrumentID: "rb2501", direction: .long)
        #expect(pos?.volume == 2)
        #expect(pos?.openAvgPrice == 3499)
    }

    @Test("买单 · lastPrice > price 不成交")
    func buyLimitNotFill() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (_, _) = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500))

        await engine.onTick(makeTick(3501))
        let active = await engine.activeOrders()
        #expect(active.count == 1)
    }

    @Test("卖单 · lastPrice ≥ price 触发成交")
    func sellLimitFill() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (ref, _) = await engine.submitOrder(makeOpenOrder(direction: .sell, price: 3500))

        await engine.onTick(makeTick(3501))
        let order = await engine.allOrders().first { $0.orderRef == ref }
        #expect(order?.status == .filled)

        // 卖开 → 空头持仓
        let pos = await engine.position(instrumentID: "rb2501", direction: .short)
        #expect(pos?.volume == 1)
    }

    @Test("加仓 · 均价加权")
    func addPositionAvgPrice() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        // 第 1 笔：1 手 @ 3500
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))
        // 第 2 笔：1 手 @ 3600
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3600, volume: 1))
        await engine.onTick(makeTick(3600))

        let pos = await engine.position(instrumentID: "rb2501", direction: .long)
        #expect(pos?.volume == 2)
        // (3500*1 + 3600*1) / 2 = 3550
        #expect(pos?.openAvgPrice == 3550)
    }
}

// MARK: - 3. 平仓 + 盈亏

@Suite("SimulatedTradingEngine · 平仓 + 盈亏")
struct CloseAndPnLTests {

    @Test("多头平仓 · 盈利 closePnL 正确")
    func longCloseProfit() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        // 买开 1 手 @ 3500
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))
        // 卖平 1 手 @ 3600
        _ = await engine.submitOrder(makeCloseOrder(direction: .sell, price: 3600, volume: 1))
        await engine.onTick(makeTick(3600))

        let account = await engine.currentAccount()
        // 盈亏 = (3600 - 3500) × 1 × 10 = 1000
        #expect(account.closePnL == 1000)
        // 持仓清零
        let positions = await engine.allPositions()
        #expect(positions.isEmpty)
    }

    @Test("空头平仓 · 盈利 closePnL 正确")
    func shortCloseProfit() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .sell, price: 3600, volume: 1))
        await engine.onTick(makeTick(3600))
        _ = await engine.submitOrder(makeCloseOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))

        let account = await engine.currentAccount()
        // 空头盈亏 = (3600 - 3500) × 1 × 10 = 1000
        #expect(account.closePnL == 1000)
    }

    @Test("部分平仓 · volume 减 + 保证金按比例释放")
    func partialClose() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        // 买开 2 手 @ 3500 · 保证金 3500*2*10*0.10 = 7000
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 2))
        await engine.onTick(makeTick(3500))
        // 平 1 手 @ 3600
        _ = await engine.submitOrder(makeCloseOrder(direction: .sell, price: 3600, volume: 1))
        await engine.onTick(makeTick(3600))

        let pos = await engine.position(instrumentID: "rb2501", direction: .long)
        #expect(pos?.volume == 1)
        // 保证金应剩 3500（一半）
        #expect(pos?.margin == 3500)
    }

    @Test("手续费累计 · 5 元/手 × 开 + 平 × 数量")
    func commissionAccumulates() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 2))
        await engine.onTick(makeTick(3500))
        _ = await engine.submitOrder(makeCloseOrder(direction: .sell, price: 3600, volume: 2))
        await engine.onTick(makeTick(3600))

        let account = await engine.currentAccount()
        // 开 5*2=10 + 平 5*2=10 = 20
        #expect(account.commission == 20)
    }
}

// MARK: - 4. 撤单

@Suite("SimulatedTradingEngine · 撤单")
struct CancelOrderTests {

    @Test("active 委托可撤 · status=cancelled + 释放保证金")
    func cancelActive() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (ref, _) = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        let beforeMargin = await engine.currentAccount().margin
        #expect(beforeMargin > 0)

        let ok = await engine.cancelOrder(orderRef: ref)
        #expect(ok)
        let order = await engine.allOrders().first { $0.orderRef == ref }
        #expect(order?.status == .cancelled)
        let afterMargin = await engine.currentAccount().margin
        #expect(afterMargin == 0)
    }

    @Test("已成交不可撤")
    func cannotCancelFilled() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let (ref, _) = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))   // 已成交
        let ok = await engine.cancelOrder(orderRef: ref)
        #expect(!ok)
    }

    @Test("不存在的 orderRef 撤单 → false")
    func cancelNonExistent() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        let ok = await engine.cancelOrder(orderRef: "99999999")
        #expect(!ok)
    }
}

// MARK: - 5. 浮动盈亏

@Suite("SimulatedTradingEngine · 持仓浮盈")
struct FloatingPnLTests {

    @Test("多头浮盈随价格变化")
    func longFloatingPnL() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))

        // 价格上涨到 3600 · 浮盈 = (3600-3500) × 1 × 10 = 1000
        await engine.onTick(makeTick(3600))
        let account = await engine.currentAccount()
        #expect(account.positionPnL == 1000)
    }

    @Test("空头浮盈随价格变化")
    func shortFloatingPnL() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .sell, price: 3600, volume: 1))
        await engine.onTick(makeTick(3600))

        // 价格跌到 3500 · 空头浮盈 = (3600-3500) × 1 × 10 = 1000
        await engine.onTick(makeTick(3500))
        let account = await engine.currentAccount()
        #expect(account.positionPnL == 1000)
    }
}

// MARK: - 6. 事件流订阅

@Suite("SimulatedTradingEngine · 事件流")
struct EventStreamTests {

    private actor EventCapture {
        private(set) var events: [SimulatedTradingEvent] = []
        func add(_ e: SimulatedTradingEvent) { events.append(e) }
        func snapshot() -> [SimulatedTradingEvent] { events }
    }

    @Test("submitted + filled + accountChanged + positionChanged 全部推送")
    func fullLifecycleEvents() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let capture = EventCapture()
        let task = Task {
            for await e in await engine.observe() {
                await capture.add(e)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await capture.snapshot()
        let hasSubmitted = events.contains { if case .orderSubmitted = $0 { return true }; return false }
        let hasFilled = events.contains { if case .orderFilled = $0 { return true }; return false }
        let hasPosition = events.contains { if case .positionChanged = $0 { return true }; return false }
        #expect(hasSubmitted)
        #expect(hasFilled)
        #expect(hasPosition)
    }

    @Test("rejected 推送拒绝事件")
    func rejectedEvent() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000)
        await engine.registerContract(makeContract())
        let capture = EventCapture()
        let task = Task {
            for await e in await engine.observe() {
                await capture.add(e)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        _ = await engine.submitOrder(makeOpenOrder())   // 资金不足必拒

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await capture.snapshot()
        let hasRejected = events.contains { if case .orderRejected = $0 { return true }; return false }
        #expect(hasRejected)
    }
}

// MARK: - 7. 资金曲线 equityCurve

@Suite("SimulatedTradingEngine · 资金曲线")
struct EquityCurveTests {

    @Test("起始 baseline · index 0 = 初始余额")
    func initialBaseline() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        let curve = await engine.equityCurveSnapshot()
        #expect(curve.count == 1)
        #expect(curve.first?.balance == 1_000_000)
        #expect(curve.first?.positionPnL == 0)
    }

    @Test("EquityCurvePoint Codable 往返")
    func codableRoundTrip() throws {
        let pt = EquityCurvePoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            balance: 1_005_000,
            positionPnL: 5_000
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(EquityCurvePoint.self, from: data)
        #expect(decoded == pt)
    }

    @Test("成交后曲线追加新点 · balance 反映新值")
    func appendAfterFill() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        // 买开 1 手 @ 3500 · 锁保证金 3500 → balance 不变（仅 margin 变）但仍触发 accountChanged
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        // 成交价 3500 → 没浮盈 · 但手续费改变 balance
        await engine.onTick(makeTick(3500))

        let curve = await engine.equityCurveSnapshot()
        #expect(curve.count >= 2)
        // 末点 balance = 1_000_000 - fixedCommissionPerLot
        let expected = Decimal(1_000_000) - SimulatedTradingEngine.fixedCommissionPerLot
        #expect(curve.last?.balance == expected)
    }

    @Test("浮盈变化 → 曲线追加 · 反映 mark-to-market")
    func appendOnPositionPnLChange() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))   // 开仓
        let countAfterOpen = await engine.equityCurveSnapshot().count

        // 价格涨到 3600 → 浮盈 +1000
        await engine.onTick(makeTick(3600))
        let curve = await engine.equityCurveSnapshot()
        #expect(curve.count > countAfterOpen)
        #expect(curve.last?.positionPnL == 1_000)
        // balance = 1_000_000 - 手续费 + 1000（浮盈）
        let expected = Decimal(1_000_000) - SimulatedTradingEngine.fixedCommissionPerLot + 1_000
        #expect(curve.last?.balance == expected)
    }

    @Test("相邻同 balance 不重复追加（去重防 onTick 高频空 yield 撑爆）")
    func dedupeIdenticalPoints() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))   // 一根 tick 触发开仓 + 浮盈计算

        let count1 = await engine.equityCurveSnapshot().count
        // 同样的 3500 价格再次 tick · positionPnL 不变 · balance 不变 → 不追加
        await engine.onTick(makeTick(3500))
        let count2 = await engine.equityCurveSnapshot().count
        #expect(count2 == count1)
    }
}

// MARK: - 8. 持久化快照 snapshot/restore（v15.6）

@Suite("SimulatedTradingEngine · 持久化快照")
struct SnapshotTests {

    @Test("snapshot · 含 account/orders/trades/positions/equityCurve + counters")
    func snapshotContents() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))
        await engine.onTick(makeTick(3600))   // 浮盈 +1000

        let snap = await engine.snapshot()
        #expect(snap.account.balance > 0)
        #expect(snap.orders.count == 1)
        #expect(snap.trades.count == 1)
        #expect(snap.positions.count == 1)
        #expect(snap.equityCurve.count >= 2)
        #expect(snap.orderRefCounter == 1)
        #expect(snap.tradeIDCounter == 1)
    }

    @Test("snapshot Codable JSON 往返")
    func snapshotCodable() async throws {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 2))
        await engine.onTick(makeTick(3500))

        let snap = await engine.snapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SimulatedTradingSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    @Test("restore · 完整恢复 + 后续 onTick 仍正常撮合")
    func restoreAndContinue() async {
        let engine1 = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine1.registerContract(makeContract())
        _ = await engine1.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine1.onTick(makeTick(3500))
        let snap = await engine1.snapshot()

        // 模拟 App 重启 · 新 engine restore
        let engine2 = SimulatedTradingEngine(initialBalance: 0)
        await engine2.registerContract(makeContract())   // 合约重新注册
        await engine2.restore(snap)

        // 持仓 / 账户 / 委托 / 资金曲线全部恢复
        let pos = await engine2.position(instrumentID: "rb2501", direction: .long)
        #expect(pos?.volume == 1)
        let acc = await engine2.currentAccount()
        #expect(acc.balance == snap.account.balance)
        let orders = await engine2.allOrders()
        #expect(orders.count == 1)

        // 后续操作仍正常：平 1 手 @ 3600
        let (_, rejection) = await engine2.submitOrder(makeCloseOrder(direction: .sell, price: 3600, volume: 1))
        #expect(rejection == nil)
        await engine2.onTick(makeTick(3600))
        let posAfter = await engine2.position(instrumentID: "rb2501", direction: .long)
        // 平仓后清仓
        #expect(posAfter == nil)
    }

    @Test("reset · 清空所有 + 资金恢复 + counter 归零")
    func resetClears() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))

        await engine.reset(initialBalance: 1_000_000)
        let acc = await engine.currentAccount()
        #expect(acc.balance == 1_000_000)
        #expect(acc.commission == 0)
        let orders = await engine.allOrders()
        #expect(orders.isEmpty)
        let trades = await engine.allTrades()
        #expect(trades.isEmpty)
        let positions = await engine.allPositions()
        #expect(positions.isEmpty)
        let curve = await engine.equityCurveSnapshot()
        #expect(curve.count == 1)   // 仅 baseline
        #expect(curve.first?.balance == 1_000_000)

        // 重置后 ref counter 归零（下一笔 ref = 00000001）
        let (ref, _) = await engine.submitOrder(makeOpenOrder())
        #expect(ref == "00000001")
    }
}

// MARK: - 9. SimulatedTradingStore UserDefaults 持久化

@Suite("SimulatedTradingStore · UserDefaults 持久化")
struct SimulatedTradingStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SimulatedTradingTest-\(UUID().uuidString)")!
    }

    @Test("save then load · 反序列化等价")
    func saveLoadRoundTrip() async {
        let defaults = makeDefaults()
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        _ = await engine.submitOrder(makeOpenOrder(direction: .buy, price: 3500, volume: 1))
        await engine.onTick(makeTick(3500))
        let snap = await engine.snapshot()

        SimulatedTradingStore.save(snap, defaults: defaults)
        let loaded = SimulatedTradingStore.load(defaults: defaults)
        #expect(loaded == snap)
    }

    @Test("load 空时返回 nil")
    func loadEmptyReturnsNil() {
        let defaults = makeDefaults()
        #expect(SimulatedTradingStore.load(defaults: defaults) == nil)
    }

    @Test("clear · 后续 load 返回 nil")
    func clearRemovesData() async {
        let defaults = makeDefaults()
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        let snap = await engine.snapshot()
        SimulatedTradingStore.save(snap, defaults: defaults)
        SimulatedTradingStore.clear(defaults: defaults)
        #expect(SimulatedTradingStore.load(defaults: defaults) == nil)
    }
}
