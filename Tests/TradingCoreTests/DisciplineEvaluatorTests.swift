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

    // MARK: - batch3 trades 类规则

    private func makeTrade(_ ref: String, _ inst: String = "rb2410",
                           dir: Direction = .buy, offset: OffsetFlag = .open) -> TradeRecord {
        TradeRecord(tradeID: "T-\(ref)", orderRef: ref, instrumentID: inst,
                    direction: dir, offsetFlag: offset, price: 3000, volume: 1,
                    tradeTime: "2026-05-05 10:00:00", commission: 5)
    }

    @Test("maxDailyTrades · 11 笔超过 10 笔阈值 → warning · message 含 11/10")
    func maxDailyTradesTriggered() {
        let rule = DisciplineRule(kind: .maxDailyTrades, threshold: 10)
        let trades = (1...11).map { makeTrade("O-\($0)") }
        let v = DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: trades, dailyRealizedPnL: 0, now: now)
        #expect(v.count == 1)
        #expect(v[0].severity == .warning)
        #expect(v[0].message.contains("11"))
        #expect(v[0].message.contains("10"))
        #expect(v[0].relatedOrderRefs.count == 11)
    }

    @Test("maxDailyTrades · 10 笔正好等于 10 不触发（> 阈值才触发）")
    func maxDailyTradesAtThreshold() {
        let rule = DisciplineRule(kind: .maxDailyTrades, threshold: 10)
        let trades = (1...10).map { makeTrade("O-\($0)") }
        #expect(DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: trades, dailyRealizedPnL: 0, now: now).isEmpty)
    }

    @Test("dailyMaxLoss · 亏损 8000 元超过 5000 阈值 → error · message 含金额")
    func dailyMaxLossTriggered() {
        let rule = DisciplineRule(kind: .dailyMaxLoss, threshold: 5000)
        let v = DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: [], dailyRealizedPnL: -8000, now: now)
        #expect(v.count == 1)
        #expect(v[0].severity == .error)
        #expect(v[0].message.contains("8000"))
        #expect(v[0].message.contains("5000"))
    }

    @Test("dailyMaxLoss · 盈利 +1000 元 → 不触发")
    func dailyMaxLossProfit() {
        let rule = DisciplineRule(kind: .dailyMaxLoss, threshold: 5000)
        #expect(DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: [], dailyRealizedPnL: 1000, now: now).isEmpty)
    }

    @Test("dailyMaxLoss · 亏损刚好达 5000 → 触发（>= 阈值）")
    func dailyMaxLossAtThreshold() {
        let rule = DisciplineRule(kind: .dailyMaxLoss, threshold: 5000)
        let v = DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: [], dailyRealizedPnL: -5000, now: now)
        #expect(v.count == 1)
    }

    @Test("maxAddPositions · 同合约同方向 4 次开仓超过 3 次阈值 → warning")
    func maxAddPositionsTriggered() {
        let rule = DisciplineRule(kind: .maxAddPositions, threshold: 3)
        let trades = (1...4).map { makeTrade("O-\($0)", dir: .buy, offset: .open) }
        let v = DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: trades, dailyRealizedPnL: 0, now: now)
        #expect(v.count == 1)
        #expect(v[0].severity == .warning)
        #expect(v[0].message.contains("rb2410"))
        #expect(v[0].message.contains("买"))
        #expect(v[0].message.contains("4"))
    }

    @Test("maxAddPositions · 平仓清零后再开 3 次不算超阈值")
    func maxAddPositionsClosesReset() {
        let rule = DisciplineRule(kind: .maxAddPositions, threshold: 3)
        let trades: [TradeRecord] = [
            makeTrade("O-1", dir: .buy, offset: .open),
            makeTrade("O-2", dir: .buy, offset: .open),
            makeTrade("O-3", dir: .buy, offset: .close),     // 平仓清零
            makeTrade("O-4", dir: .buy, offset: .open),       // 重新开始
            makeTrade("O-5", dir: .buy, offset: .open),
            makeTrade("O-6", dir: .buy, offset: .open),       // 累计 3 次 · 不超
        ]
        #expect(DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: trades, dailyRealizedPnL: 0, now: now).isEmpty)
    }

    @Test("maxAddPositions · 多空双方向独立计数")
    func maxAddPositionsBidirectional() {
        let rule = DisciplineRule(kind: .maxAddPositions, threshold: 3)
        let trades: [TradeRecord] = [
            makeTrade("O-1", dir: .buy, offset: .open),
            makeTrade("O-2", dir: .buy, offset: .open),
            makeTrade("O-3", dir: .sell, offset: .open),
            makeTrade("O-4", dir: .sell, offset: .open),
        ]
        // 买方 2 次 · 卖方 2 次 · 都不超阈值
        #expect(DisciplineEvaluator.evaluateTrades(rules: [rule], todayTrades: trades, dailyRealizedPnL: 0, now: now).isEmpty)
    }

    @Test("evaluateTrades · 持仓类规则（stopLossPercent）跳过 不报错")
    func tradesEvalSkipsPositionRules() {
        let rules = [
            DisciplineRule(kind: .stopLossPercent, threshold: 2.0),
            DisciplineRule(kind: .maxHoldingMinutes, threshold: 30),
        ]
        let trades = [makeTrade("O-1")]
        #expect(DisciplineEvaluator.evaluateTrades(rules: rules, todayTrades: trades, dailyRealizedPnL: -10000, now: now).isEmpty)
    }
}
