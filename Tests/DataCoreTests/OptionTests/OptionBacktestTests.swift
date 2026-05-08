// OptionBacktest 单测（v15.33 · 期权 Phase 6.3）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("OptionBacktest · 期权回测引擎")
struct OptionBacktestTests {

    // MARK: - 测试辅助

    private func makeOption(
        type: OptionType, strike: Decimal, daysFromNow: Int = 30
    ) -> OptionContract {
        let exp = Date().addingTimeInterval(TimeInterval(daysFromNow * 86400))
        return OptionContract(
            id: "BT-\(type.rawValue)-\(strike)-\(daysFromNow)",
            underlyingID: "TEST", underlyingName: "测试",
            type: type, strikePrice: strike, expirationDate: exp,
            exerciseStyle: .european, contractMultiplier: 100,
            category: .stockIndex, exchange: .CFFEX
        )
    }

    private func makeContext(spotPrice: Double = 100, σ: Double = 0.20) -> OptionStrategyBuilder.Context {
        var contracts: [OptionContract] = []
        for s: Decimal in [90, 95, 100, 105, 110] {
            contracts.append(makeOption(type: .call, strike: s))
            contracts.append(makeOption(type: .put,  strike: s))
        }
        let chain = OptionChainBuilder.build(contracts: contracts)!
        return OptionStrategyBuilder.Context(chain: chain, spotPrice: spotPrice,
                                              riskFreeRate: 0.03, volatility: σ)
    }

    /// 生成 N 天的样本时序 · spot 按指定 closure 生成 · IV 恒定
    private func samples(
        days: Int, σ: Double = 0.20,
        spotAt: (Int) -> Double
    ) -> [OptionBacktestSample] {
        let start = Date()
        return (0..<days).map { i in
            OptionBacktestSample(
                date: start.addingTimeInterval(TimeInterval(i * 86400)),
                spotPrice: spotAt(i),
                impliedVolatility: σ
            )
        }
    }

    // MARK: - 基础正确性

    @Test("空样本 · 返回 0 指标 · 不 crash")
    func emptySamples() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(strategy: s, samples: [])
        #expect(r.curve.isEmpty)
        #expect(r.endingPnL == 0)
        #expect(r.maxDrawdown == 0)
        #expect(r.sharpeRatio == 0)
    }

    @Test("曲线长度 = 样本数 · 每点都有 optionMTM + underlyingMTM")
    func curveLength() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 10) { _ in 100 }
        )
        #expect(r.curve.count == 10)
        #expect(r.curve.allSatisfy { $0.totalPnL == $0.optionMTM + $0.underlyingMTM })
    }

    // MARK: - 长跨式回测语义

    @Test("长跨式 · 标的不动 · totalPnL 接近 0（理论价 ≈ entryPremium）")
    func longStraddleStaticSpot() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 5, σ: 0.20) { _ in 100 }
        )
        // 标的不动 · IV 不动 · 仅时间衰减导致小幅亏损（Theta）· 不会大涨大跌
        // 第一天 PnL 应该接近 0（同 IV、同 spot · 仅 1 天衰减）
        let firstDay = r.curve.first!.totalPnL
        #expect(abs(firstDay) < 1)
    }

    @Test("长跨式 · 标的暴涨 · optionMTM 显著为正")
    func longStraddleSpotJump() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        // 第 0 天：100 · 第 1 天：暴涨到 120
        let r = OptionBacktester.run(
            strategy: s,
            samples: [
                OptionBacktestSample(date: Date(), spotPrice: 100, impliedVolatility: 0.20),
                OptionBacktestSample(date: Date().addingTimeInterval(86400),
                                     spotPrice: 120, impliedVolatility: 0.20),
            ]
        )
        // Day 1 PnL 应远大于 Day 0
        #expect(r.curve[1].totalPnL > r.curve[0].totalPnL + 5)
        #expect(r.curve[1].totalPnL > 5)
    }

    // MARK: - 备兑回测

    @Test("备兑 · 标的小涨不破 strike · 收权利金 · totalPnL > 0")
    func coveredCallSlightUp() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.coveredCall(
            context: ctx, callStrike: 105,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        // 持有到接近到期 · 标的从 100 → 103（不破 105）
        let r = OptionBacktester.run(
            strategy: s,
            samples: [
                OptionBacktestSample(date: Date(), spotPrice: 100, impliedVolatility: 0.20),
                OptionBacktestSample(date: Date().addingTimeInterval(28 * 86400),
                                     spotPrice: 103, impliedVolatility: 0.20),
            ]
        )
        // Day-28：标的 +3 · short call OTM 时间价值衰减 · totalPnL 应 > 0
        #expect(r.curve.last!.totalPnL > 0)
    }

    // MARK: - 统计指标

    @Test("totalPnL · 与曲线末日吻合")
    func endingPnLMatchesLast() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 5) { 100.0 + Double($0) }
        )
        #expect(r.endingPnL == r.curve.last!.totalPnL)
    }

    @Test("maxDrawdown · 单调上升序列回撤为 0")
    func zeroDrawdownOnMonotonic() {
        // 构造一个 PnL 严格单调上升的场景：长跨式 + 标的持续上涨
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        // spot 从 100 单调涨到 130 · long call payoff 单调上升 · 整体 PnL 单调上升
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 7) { 100.0 + Double($0) * 5 }
        )
        // 严格单调时 maxDD 应该很小（接近 0 · 因 put 价值在跌但 call 涨更多）
        #expect(r.maxDrawdown < 1.0)
    }

    @Test("maxDrawdown · 正确捕捉 peak→trough")
    func maxDrawdownCapture() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        // 标的轨迹：100 → 130（赚）→ 100（回撤）
        let r = OptionBacktester.run(
            strategy: s,
            samples: [
                OptionBacktestSample(date: Date(), spotPrice: 100, impliedVolatility: 0.20),
                OptionBacktestSample(date: Date().addingTimeInterval(86400),
                                     spotPrice: 130, impliedVolatility: 0.20),
                OptionBacktestSample(date: Date().addingTimeInterval(2 * 86400),
                                     spotPrice: 100, impliedVolatility: 0.20),
            ]
        )
        // peak 在 Day 1 · trough 回到 Day 2 · 回撤显著 > 0
        #expect(r.maxDrawdown > 5)
    }

    @Test("winRate · 全程 totalPnL > 0 时为 1.0")
    func winRateAllPositive() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        // 标的持续暴涨 · 长跨式上方利润无限 · 全部样本 PnL > 0
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 5) { 100.0 + Double($0 + 1) * 10 }
        )
        #expect(r.winRate == 1.0)
    }

    @Test("bestDay/worstDay · 与曲线 max/min 一致")
    func bestWorstConsistency() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(
            strategy: s,
            samples: samples(days: 10) { 100.0 + sin(Double($0)) * 20 }
        )
        let maxPnL = r.curve.map { $0.totalPnL }.max()!
        let minPnL = r.curve.map { $0.totalPnL }.min()!
        #expect(r.bestDay?.totalPnL == maxPnL)
        #expect(r.worstDay?.totalPnL == minPnL)
        #expect(r.peakPnL == maxPnL)
        #expect(r.troughPnL == minPnL)
    }

    // MARK: - 边界

    @Test("单样本 · sharpe = 0（不足以算差分）")
    func singleSampleSharpe() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100,
            expiration: ctx.chain.slices.first!.expirationDate
        )!
        let r = OptionBacktester.run(
            strategy: s,
            samples: [OptionBacktestSample(date: Date(), spotPrice: 100, impliedVolatility: 0.20)]
        )
        #expect(r.sharpeRatio == 0)
        #expect(r.curve.count == 1)
    }

    @Test("到期日后样本 · BS 退化为内在价值（与 leg.payoffAtExpiration 对齐）")
    func samplesAtExpiration() {
        let ctx = makeContext(spotPrice: 100, σ: 0.20)
        let exp = ctx.chain.slices.first!.expirationDate
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100, expiration: exp
        )!
        // 样本时间正好在到期日（T → 0）· spot=120
        let atExpSample = OptionBacktestSample(date: exp, spotPrice: 120, impliedVolatility: 0.20)
        let r = OptionBacktester.run(strategy: s, samples: [atExpSample])
        // 长跨式 strike=100 · spot=120 · call 内在值=20 · put=0 → option PnL ≈ 20 - netPremium
        let theoretical = s.payoffAtExpiration(spotPrice: 120)
        let diff = abs(r.curve.first!.totalPnL - theoretical)
        // 容差大些 · 因为 BS 在 T→1e-6 时仍有微量时间价值
        #expect(diff < 0.5)
    }
}
