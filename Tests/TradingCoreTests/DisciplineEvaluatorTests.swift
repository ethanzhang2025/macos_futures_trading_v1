// WP-54 v15.23 batch2 · 纪律规则评估器测试（stopLossPercent + maxHoldingMinutes）

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("DisciplineEvaluator · WP-54 v15.23 batch2 持仓规则")
struct DisciplineEvaluatorTests {

    // MARK: - helpers

    private func makeLong(_ avgPrice: Decimal, volume: Int = 1, mul: Int = 10) -> Position {
        Position(instrumentID: "rb2410", direction: .long, volume: volume, todayVolume: volume,
                 avgPrice: avgPrice, openAvgPrice: avgPrice, preSettlementPrice: avgPrice,
                 margin: 1000, volumeMultiple: mul)
    }

    private func makeShort(_ avgPrice: Decimal, volume: Int = 1, mul: Int = 10) -> Position {
        Position(instrumentID: "rb2410", direction: .short, volume: volume, todayVolume: volume,
                 avgPrice: avgPrice, openAvgPrice: avgPrice, preSettlementPrice: avgPrice,
                 margin: 1000, volumeMultiple: mul)
    }

    private let now = Date(timeIntervalSince1970: 1746360000)
    private var openedTenMinAgo: Date { now.addingTimeInterval(-600) }    // 10 min ago
    private var openedFortyMinAgo: Date { now.addingTimeInterval(-2400) } // 40 min ago

    // MARK: - stopLossPercent

    @Test("stopLossPercent · 多单浮亏 -3% 超过 2% 阈值 → 1 个 error 违规")
    func stopLossLongTriggered() {
        // openAvgPrice 3000 · 当前 2910（-3%）· principal = 3000×1×10 = 30000 · pnl = -900 · loss = 3%
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 2910)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.count == 1)
        #expect(v[0].ruleKind == .stopLossPercent)
        #expect(v[0].severity == .error)
        #expect(v[0].message.contains("rb2410"))
        #expect(v[0].message.contains("3.00"))
    }

    @Test("stopLossPercent · 浮亏 -1% 不到 2% 阈值 → 不触发")
    func stopLossNotTriggered() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 2970)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.isEmpty)
    }

    @Test("stopLossPercent · 浮盈状态（loss 为负）→ 不触发")
    func stopLossProfit() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 3050)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.isEmpty)
    }

    @Test("stopLossPercent · 空单浮亏 -2.5% → 触发（方向对称）")
    func stopLossShortTriggered() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        // 空单：currentPrice 涨 = 亏 · 3000 → 3075 = +2.5% 涨幅 · 空单亏 -2.5%
        let ctx = PositionContext(position: makeShort(3000), openedAt: now, currentPrice: 3075)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.count == 1)
        #expect(v[0].message.contains("空单"))
    }

    @Test("stopLossPercent · 规则 disabled → 不触发")
    func stopLossDisabled() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0, enabled: false)
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 2900)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.isEmpty)
    }

    // MARK: - maxHoldingMinutes

    @Test("maxHoldingMinutes · 持仓 40 分钟超过 30 分钟阈值 → 1 个 warning")
    func holdingTimeTriggered() {
        let rule = DisciplineRule(kind: .maxHoldingMinutes, threshold: 30)
        let ctx = PositionContext(position: makeLong(3000), openedAt: openedFortyMinAgo, currentPrice: 3000)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.count == 1)
        #expect(v[0].ruleKind == .maxHoldingMinutes)
        #expect(v[0].severity == .warning)
        #expect(v[0].message.contains("40"))
        #expect(v[0].message.contains("30"))
    }

    @Test("maxHoldingMinutes · 持仓 10 分钟未到 30 分钟阈值 → 不触发")
    func holdingTimeNotTriggered() {
        let rule = DisciplineRule(kind: .maxHoldingMinutes, threshold: 30)
        let ctx = PositionContext(position: makeLong(3000), openedAt: openedTenMinAgo, currentPrice: 3000)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [ctx], now: now)
        #expect(v.isEmpty)
    }

    // MARK: - 多规则 / 多持仓 / 不相关规则跳过

    @Test("多持仓 · 仅亏损者触发止损 · 各持仓独立计算")
    func multiplePositionsIndependentEval() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        let losingCtx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 2900)
        let winningCtx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 3100)
        let v = DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [losingCtx, winningCtx], now: now)
        #expect(v.count == 1)
    }

    @Test("trades 相关规则（dailyMaxLoss 等）传入 evaluatePositions → 跳过不报错")
    func nonPositionRulesIgnored() {
        let rules = [
            DisciplineRule(kind: .dailyMaxLoss, threshold: 5000),
            DisciplineRule(kind: .maxDailyTrades, threshold: 10),
            DisciplineRule(kind: .maxAddPositions, threshold: 3),
        ]
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 2900)
        let v = DisciplineEvaluator.evaluatePositions(rules: rules, positions: [ctx], now: now)
        #expect(v.isEmpty)
    }

    @Test("空 rules / 空 positions → 返回空")
    func emptyInputs() {
        #expect(DisciplineEvaluator.evaluatePositions(rules: [], positions: [], now: now).isEmpty)
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        #expect(DisciplineEvaluator.evaluatePositions(rules: [rule], positions: [], now: now).isEmpty)
        let ctx = PositionContext(position: makeLong(3000), openedAt: now, currentPrice: 3000)
        #expect(DisciplineEvaluator.evaluatePositions(rules: [], positions: [ctx], now: now).isEmpty)
    }
}
