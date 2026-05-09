// SpreadDeviation alert 测试（v15.57 · ⌘⌥W 一键加预警）
//
// 覆盖：
// - AlertCondition.spreadDeviation Codable round-trip（兼容 9 现有 case 一起）
// - AlertEvaluator onTick 看到 spreadDeviation 不触发（v1 placeholder）
// - AlertEvaluator onBar 看到 spreadDeviation 不触发
// - AlertHistoryFilter ConditionKind.of 映射 .spread

import Testing
import Foundation
import Shared
@testable import AlertCore

private func makeTick(_ instrumentID: String, price: Decimal, openInterest: Decimal = 0) -> Tick {
    Tick(
        instrumentID: instrumentID,
        lastPrice: price, volume: 100, openInterest: openInterest, turnover: 0,
        bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
        highestPrice: 0, lowestPrice: 0, openPrice: 0,
        preClosePrice: 0, preSettlementPrice: 0,
        upperLimitPrice: 0, lowerLimitPrice: 0,
        updateTime: "00:00:00", updateMillisec: 0,
        tradingDay: "20260508", actionDay: "20260508"
    )
}

@Suite("SpreadDeviation alert · v15.57 placeholder + 数据契约")
struct SpreadDeviationAlertTests {

    // MARK: - Codable

    @Test("AlertCondition.spreadDeviation Codable round-trip")
    func codableRoundTrip() throws {
        let cond = AlertCondition.spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.5)
        let data = try JSONEncoder().encode(cond)
        let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
        #expect(decoded == cond)
    }

    @Test("AlertCondition.spreadDeviation 跨期变体 round-trip")
    func calendarRoundTrip() throws {
        let cond = AlertCondition.spreadDeviation(spreadID: "rb-05-10", isCalendar: true, zThreshold: 3.0)
        let data = try JSONEncoder().encode(cond)
        let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
        #expect(decoded == cond)
    }

    @Test("Alert struct 包含 spreadDeviation condition · 完整 Codable round-trip")
    func alertWithSpreadConditionRoundTrip() throws {
        let alert = Alert(
            name: "[价差] 螺纹热卷 上轨突破",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0),
            cooldownSeconds: 600
        )
        let data = try JSONEncoder().encode(alert)
        let decoded = try JSONDecoder().decode(Alert.self, from: data)
        #expect(decoded.condition == alert.condition)
        #expect(decoded.name == alert.name)
        #expect(decoded.instrumentID == "RB0")
    }

    // MARK: - Evaluator placeholder（v1 不触发）

    @Test("AlertEvaluator.onTick 收到 spreadDeviation alert · 不触发（lastTriggeredAt 保持 nil）")
    func evaluatorOnTickDoesNotTrigger() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)

        // 模拟 RB0 多个 tick · spread alert 不应触发（lastTriggeredAt 保持 nil）
        for i in 0..<5 {
            let tick = makeTick("RB0", price: Decimal(3245 + i * 10), openInterest: 1200)
            await evaluator.onTick(tick)
        }

        let after = await evaluator.allAlerts()
        #expect(after.count == 1)
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("AlertEvaluator.onBar 收到 spreadDeviation alert · 不触发")
    func evaluatorOnBarDoesNotTrigger() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-05-10",
            instrumentID: "RB2505",
            condition: .spreadDeviation(spreadID: "rb-05-10", isCalendar: true, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)

        for i in 0..<3 {
            let bar = KLine(
                instrumentID: "RB2505", period: .daily,
                openTime: Date().addingTimeInterval(TimeInterval(i) * 86400),
                open: 3245, high: 3260, low: 3230, close: 3250,
                volume: 1000, openInterest: 0, turnover: 0
            )
            await evaluator.onBar(bar, instrumentID: "RB2505", period: .daily)
        }

        let after = await evaluator.allAlerts()
        #expect(after.count == 1)
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("alert 被加入 evaluator 后 allAlerts 可查到（持久化语义）")
    func alertPersistedInEvaluator() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] au-80ag",
            instrumentID: "AU0",
            condition: .spreadDeviation(spreadID: "au-80ag", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        let all = await evaluator.allAlerts()
        #expect(all.count == 1)
        #expect(all.first?.condition == alert.condition)
        #expect(all.first?.id == alert.id)
    }

    // MARK: - AlertHistoryFilter 映射

    @Test("AlertHistoryStatistics.ConditionKind.of(.spreadDeviation) → .spread")
    func historyFilterMapping() {
        let cond = AlertCondition.spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        #expect(AlertHistoryStatistics.ConditionKind.of(cond) == .spread)
    }

    // MARK: - v15.60 · onSpreadValue 真触发

    private struct StubSV: SpreadValueLike {
        let value: Decimal
        init(_ v: Decimal) { self.value = v }
    }

    /// 30 个均值 100 + 1 个 200 偏离点 · 强烈偏离触发上轨
    private func makeStrongUpper() -> [SpreadValueLike] {
        var arr: [SpreadValueLike] = (0..<30).map { _ in StubSV(100) }
        arr.append(StubSV(200))
        return arr
    }

    @Test("onSpreadValue · 强偏离 + 匹配 spreadID/isCalendar → 触发")
    func onSpreadValue_triggersOnMatchingAlert() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        await evaluator.onSpreadValue(values: makeStrongUpper(), spreadID: "rb-hc", isCalendar: false)

        let after = await evaluator.allAlerts()
        #expect(after.first?.lastTriggeredAt != nil)
    }

    @Test("onSpreadValue · spreadID 不匹配 → 不触发")
    func onSpreadValue_skipsWrongSpreadID() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        // 强偏离但 spreadID 是别的
        await evaluator.onSpreadValue(values: makeStrongUpper(), spreadID: "au-80ag", isCalendar: false)

        let after = await evaluator.allAlerts()
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("onSpreadValue · isCalendar 不匹配（同 ID 但跨期/跨品种 mismatch）→ 不触发")
    func onSpreadValue_skipsWrongCalendarFlag() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] x",
            instrumentID: "X",
            condition: .spreadDeviation(spreadID: "x", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        await evaluator.onSpreadValue(values: makeStrongUpper(), spreadID: "x", isCalendar: true)

        let after = await evaluator.allAlerts()
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("onSpreadValue · 弱偏离（|z| < threshold）→ 不触发")
    func onSpreadValue_skipsWeakDeviation() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        // 30 点小幅波动 0..29 · stdDev 大 · current 在尾部 z 接近 1.71 < 2
        let values: [SpreadValueLike] = (0..<30).map { StubSV(Decimal($0)) }
        await evaluator.onSpreadValue(values: values, spreadID: "rb-hc", isCalendar: false)

        let after = await evaluator.allAlerts()
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("onSpreadValue · 样本不足 30 → 不评估")
    func onSpreadValue_skipsBelowMinSamples() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0)
        )
        await evaluator.addAlert(alert)
        // 仅 5 点 · 不足 30
        let values: [SpreadValueLike] = (0..<5).map { _ in StubSV(100) } + [StubSV(500)]
        await evaluator.onSpreadValue(values: values, spreadID: "rb-hc", isCalendar: false)

        let after = await evaluator.allAlerts()
        #expect(after.first?.lastTriggeredAt == nil)
    }

    @Test("onSpreadValue · cooldown 期间不重复触发")
    func onSpreadValue_respectsCooldown() async {
        let evaluator = AlertEvaluator()
        let alert = Alert(
            name: "[价差] rb-hc",
            instrumentID: "RB0",
            condition: .spreadDeviation(spreadID: "rb-hc", isCalendar: false, zThreshold: 2.0),
            cooldownSeconds: 600  // 10 分钟
        )
        await evaluator.addAlert(alert)

        let now1 = Date()
        await evaluator.onSpreadValue(values: makeStrongUpper(), spreadID: "rb-hc", isCalendar: false, now: now1)
        let firstTrigger = await evaluator.allAlerts().first?.lastTriggeredAt
        #expect(firstTrigger == now1)

        // 30s 后重扫 · 强偏离仍在 · 但 cooldown 未过 → lastTriggeredAt 不变
        let now2 = now1.addingTimeInterval(30)
        await evaluator.onSpreadValue(values: makeStrongUpper(), spreadID: "rb-hc", isCalendar: false, now: now2)
        let secondTrigger = await evaluator.allAlerts().first?.lastTriggeredAt
        #expect(secondTrigger == now1)  // 未刷新
    }
}
