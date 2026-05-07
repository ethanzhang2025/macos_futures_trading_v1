// WP-54 v15.23 batch8 · SimulatedTradingEngine 集成 DisciplineEvaluator 测试
// onTick 后自动评估 trades 类规则 · push .disciplineViolation event · dedup by ruleID:ruleKind

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("Engine + Discipline · WP-54 v15.23 batch8 集成 · 自动违规推送")
struct EngineDisciplineIntegrationTests {

    private func makeContract() -> Contract {
        Contract(instrumentID: "rb2501", instrumentName: "螺纹钢2501",
                 exchange: .SHFE, productID: "rb",
                 volumeMultiple: 10, priceTick: 1, deliveryMonth: 202501, expireDate: "20250115",
                 longMarginRatio: Decimal(string: "0.10")!, shortMarginRatio: Decimal(string: "0.10")!,
                 isTrading: true, productName: "螺纹钢", pinyinInitials: "LWG")
    }

    private func makeTick(_ price: Decimal) -> Tick {
        Tick(instrumentID: "rb2501", lastPrice: price, volume: 1,
             openInterest: 0, turnover: 0,
             bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
             highestPrice: 0, lowestPrice: 0, openPrice: 0,
             preClosePrice: 0, preSettlementPrice: 0,
             upperLimitPrice: 0, lowerLimitPrice: 0,
             updateTime: "10:00", updateMillisec: 0, tradingDay: "20250101", actionDay: "20250101")
    }

    private func openOrder(_ dir: Direction = .buy) -> OrderRequest {
        OrderRequest(instrumentID: "rb2501", direction: dir, offsetFlag: .open,
                     priceType: .limitPrice, price: 3500, volume: 1)
    }

    /// 收集 N 个 event（每次 onTick 后从 stream 拉）
    private func collectEvents(_ stream: AsyncStream<SimulatedTradingEvent>, count: Int) async -> [SimulatedTradingEvent] {
        var result: [SimulatedTradingEvent] = []
        for await event in stream {
            result.append(event)
            if result.count >= count { break }
        }
        return result
    }

    @Test("setDisciplineRules · 注入 + 查询")
    func setRules() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        let rules = [DisciplineRule(kind: .maxDailyTrades, threshold: 5)]
        await engine.setDisciplineRules(rules)
        let current = await engine.currentDisciplineRules()
        #expect(current.count == 1)
        #expect(current[0].kind == .maxDailyTrades)
    }

    @Test("maxDailyTrades · 第 6 笔 onTick 触发 · push .disciplineViolation event")
    func maxDailyTradesAutoPush() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        await engine.setDisciplineRules([DisciplineRule(kind: .maxDailyTrades, threshold: 5)])

        let collector = ViolationCollector()
        let observeTask = Task { [collector] in
            for await event in await engine.observe() {
                if case .disciplineViolation(let v) = event {
                    await collector.add(v)
                    if await collector.count() >= 1 { break }
                }
            }
        }

        let now = Date(timeIntervalSince1970: 1746360000)
        for i in 0..<6 {
            _ = await engine.submitOrder(openOrder(), now: now.addingTimeInterval(Double(i)))
            await engine.onTick(makeTick(3500), now: now.addingTimeInterval(Double(i)))
        }
        _ = await observeTask.value
        let snap = await collector.snapshot()
        #expect(snap.count == 1)
        #expect(snap[0].ruleKind == .maxDailyTrades)
        #expect(snap[0].message.contains("6"))
    }

    @Test("dedup · 同 rule 多 tick 仅 push 1 次（已 active 不重复）")
    func dedupSameRuleMultipleTicks() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        await engine.setDisciplineRules([DisciplineRule(kind: .maxDailyTrades, threshold: 3)])

        let collector = ViolationCollector()
        let observeTask = Task { [collector] in
            for await event in await engine.observe() {
                if case .disciplineViolation(let v) = event { await collector.add(v) }
            }
        }

        let now = Date(timeIntervalSince1970: 1746360000)
        for i in 0..<4 {
            _ = await engine.submitOrder(openOrder(), now: now.addingTimeInterval(Double(i)))
            await engine.onTick(makeTick(3500), now: now.addingTimeInterval(Double(i)))
        }
        for i in 4..<7 {
            await engine.onTick(makeTick(3500), now: now.addingTimeInterval(Double(i)))
        }
        // v15.23 batch208 · 修 flaky · 用 polling 等够 1 个 violation（替代固定 50ms sleep · 解决 CI 慢节点 timing）
        _ = await waitForCount(collector, target: 1)
        // 再额外 buffer · 确保第二个 violation 不会出现（dedup 验证负面用例）
        try? await Task.sleep(nanoseconds: 50_000_000)
        observeTask.cancel()
        let snap = await collector.snapshot()
        #expect(snap.count == 1, "同 rule 多 tick 应只 push 1 次 · 实际 \(snap.count)")
    }

    @Test("无 rules · onTick 不 push 任何 violation event")
    func noRulesNoEvents() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())

        let collector = ViolationCollector()
        let observeTask = Task { [collector] in
            for await event in await engine.observe() {
                if case .disciplineViolation(let v) = event { await collector.add(v) }
            }
        }
        let now = Date(timeIntervalSince1970: 1746360000)
        for i in 0..<10 {
            _ = await engine.submitOrder(openOrder(), now: now.addingTimeInterval(Double(i)))
            await engine.onTick(makeTick(3500), now: now.addingTimeInterval(Double(i)))
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        observeTask.cancel()
        #expect(await collector.count() == 0)
    }

    @Test("setDisciplineRules · 切换规则后清 lastViolationKeys（同 rule 可重新触发）")
    func switchRulesResetsCache() async {
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        await engine.registerContract(makeContract())
        let rule = DisciplineRule(kind: .maxDailyTrades, threshold: 1)
        await engine.setDisciplineRules([rule])

        let collector = ViolationCollector()
        let task = Task { [collector] in
            for await event in await engine.observe() {
                if case .disciplineViolation(let v) = event { await collector.add(v) }
            }
        }

        let now = Date(timeIntervalSince1970: 1746360000)
        for i in 0..<2 {
            _ = await engine.submitOrder(openOrder(), now: now.addingTimeInterval(Double(i)))
            await engine.onTick(makeTick(3500), now: now.addingTimeInterval(Double(i)))
        }
        // v15.23 batch208 · 修 flaky · polling 等到 count == 1（替代 30ms sleep · CI 慢节点不 flaky）
        let count1 = await waitForCount(collector, target: 1)
        #expect(count1 == 1, "首次违规未推送 · 实际 \(count1)")

        await engine.setDisciplineRules([rule])
        await engine.onTick(makeTick(3500), now: now.addingTimeInterval(10))
        let count2 = await waitForCount(collector, target: 2)
        task.cancel()
        #expect(count2 == 2, "切规则后清 cache · 同条件应再 push · 实际 \(count2)")
    }
}

/// 测试用 actor · 收集 violation events（避免 Swift 6 sendable 警告）
private actor ViolationCollector {
    private var events: [DisciplineViolation] = []
    func add(_ v: DisciplineViolation) { events.append(v) }
    func count() -> Int { events.count }
    func snapshot() -> [DisciplineViolation] { events }
}

/// v15.23 batch208 · 修 flaky · polling 等待 collector 达到目标 count（解决 observe stream 异步消费 timing）
/// - timeout: 最长等待秒数（默认 0.5s · 比固定 sleep 更稳健）
/// - 返回值：达到 target 时的 count；超时时返回最后一次读到的 count（断言负责报错）
@discardableResult
private func waitForCount(_ collector: ViolationCollector,
                          target: Int,
                          timeout: Double = 0.5) async -> Int {
    let deadline = Date().addingTimeInterval(timeout)
    var current = await collector.count()
    while current < target && Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms poll
        current = await collector.count()
    }
    return current
}
