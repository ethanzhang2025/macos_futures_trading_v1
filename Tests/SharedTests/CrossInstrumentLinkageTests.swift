// v17.172 · CrossInstrumentLinkage 单测
//
// 覆盖：
// - 4 trigger kinds × evaluate（rise/fall/limitUp/limitDown 触发 + 未触发）
// - 4 expectation kinds × verdict matched / mismatched（跟涨 + 跟跌 + 背离 + 滞后）
// - changePct 计算（zero base 边界）
// - enabled = false 跳过
// - evaluateAll 多规则批量 + 缺 snapshot 跳过

import Testing
import Foundation
@testable import Shared

@Suite("v17.172 · CrossInstrumentLinkage 跨合约联动")
struct CrossInstrumentLinkageTests {

    // MARK: - trigger 4 kinds

    @Test("trigger riseAtLeast · pct ≥ 阈值 · 触发并评估 watch")
    func triggerRiseFires() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4120, basePrice: 4000)  // +3%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4060, basePrice: 4000) // +1.5%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
        #expect(obs.triggerChangePct == 3.0)
        #expect(obs.watchChangePct == 1.5)
    }

    @Test("trigger riseAtLeast · pct < 阈值 · 不触发")
    func triggerRiseNotFires() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4100, basePrice: 4000)  // +2.5% 不到 3%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4060, basePrice: 4000)
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .notTriggered)
    }

    @Test("trigger fallAtLeast · 下跌 ≥ 阈值 · 触发")
    func triggerFallFires() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .fallAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followDown, watchThresholdPct: 1
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 3880, basePrice: 4000)  // -3%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 3940, basePrice: 4000) // -1.5%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
    }

    @Test("trigger limitUp · 涨停板 7% · 触发")
    func triggerLimitUpFires() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .limitUp, triggerThresholdPct: 7,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 3
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4280, basePrice: 4000)  // +7%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4200, basePrice: 4000) // +5%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
    }

    @Test("trigger limitDown · 跌停板 7% · 触发")
    func triggerLimitDownFires() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .limitDown, triggerThresholdPct: 7,
            watchInstrument: "HC", expectation: .followDown, watchThresholdPct: 3
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 3720, basePrice: 4000)  // -7%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 3800, basePrice: 4000) // -5%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
    }

    // MARK: - expectation 4 kinds × matched / mismatched

    @Test("expectation followUp · watch 涨幅不够 · mismatched（套利机会）")
    func expectationFollowUpMismatched() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 2
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4200, basePrice: 4000)  // +5%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4020, basePrice: 4000) // +0.5% 不到 2%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .mismatched)
        #expect(obs.message.contains("套利机会"))
    }

    @Test("expectation divergeOpposite · 触发涨 · watch 跌 ≥ 阈值 · matched")
    func expectationDivergeMatched() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .divergeOpposite, watchThresholdPct: 1
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4150, basePrice: 4000)  // +3.75%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 3940, basePrice: 4000) // -1.5%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
    }

    @Test("expectation lagBehind · watch 几乎没动 · matched（trader 进套利信号）")
    func expectationLagMatched() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .lagBehind, watchThresholdPct: 0.5
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4200, basePrice: 4000)  // +5%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4010, basePrice: 4000) // +0.25%
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .matched)
    }

    @Test("expectation lagBehind · watch 动得太多 · mismatched")
    func expectationLagMismatched() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .lagBehind, watchThresholdPct: 0.5
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4200, basePrice: 4000)  // +5%
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4080, basePrice: 4000) // +2% 超出 lag 阈值
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .mismatched)
    }

    // MARK: - changePct + 边界

    @Test("changePct · basePrice == 0 · 返回 0 · 不崩")
    func changePctZeroBase() {
        let snap = CrossLinkageSnapshot(instrument: "X", lastPrice: 100, basePrice: 0)
        #expect(snap.changePct == 0)
    }

    @Test("rule disabled · 直接返回 notTriggered")
    func ruleDisabled() {
        let rule = CrossInstrumentLinkageRule(
            ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1,
            enabled: false
        )
        let trig = CrossLinkageSnapshot(instrument: "RB", lastPrice: 4200, basePrice: 4000)
        let watch = CrossLinkageSnapshot(instrument: "HC", lastPrice: 4060, basePrice: 4000)
        let obs = CrossInstrumentLinkage.evaluate(rule: rule, trigger: trig, watch: watch)
        #expect(obs.verdict == .notTriggered)
        #expect(obs.message.contains("未启用"))
    }

    // MARK: - evaluateAll 批量

    @Test("evaluateAll · 2 规则 + 完整 snapshot map · 返回 2 obs")
    func evaluateAllAllPresent() {
        let r1 = CrossInstrumentLinkageRule(ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1)
        let r2 = CrossInstrumentLinkageRule(ruleID: "R2",
            triggerInstrument: "I", triggerKind: .fallAtLeast, triggerThresholdPct: 2,
            watchInstrument: "J", expectation: .followDown, watchThresholdPct: 1)
        let snaps: [String: CrossLinkageSnapshot] = [
            "RB": CrossLinkageSnapshot(instrument: "RB", lastPrice: 4150, basePrice: 4000),  // +3.75%
            "HC": CrossLinkageSnapshot(instrument: "HC", lastPrice: 4060, basePrice: 4000),  // +1.5%
            "I":  CrossLinkageSnapshot(instrument: "I",  lastPrice: 780,  basePrice: 800),   // -2.5%
            "J":  CrossLinkageSnapshot(instrument: "J",  lastPrice: 1980, basePrice: 2000)   // -1%
        ]
        let obs = CrossInstrumentLinkage.evaluateAll(rules: [r1, r2], snapshots: snaps)
        #expect(obs.count == 2)
        #expect(obs.allSatisfy { $0.verdict == .matched })
    }

    @Test("evaluateAll · 缺 watch snapshot 的规则被跳过")
    func evaluateAllSkipsMissing() {
        let r1 = CrossInstrumentLinkageRule(ruleID: "R1",
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1)
        let snaps: [String: CrossLinkageSnapshot] = [
            "RB": CrossLinkageSnapshot(instrument: "RB", lastPrice: 4150, basePrice: 4000)
            // 缺 HC
        ]
        let obs = CrossInstrumentLinkage.evaluateAll(rules: [r1], snapshots: snaps)
        #expect(obs.isEmpty)
    }
}
