// OptionStrategy + Payoff + Builder 单测（v15.31 · 期权 Phase 4）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("OptionStrategy · 策略组合 + Payoff + Builder")
struct OptionStrategyTests {

    // MARK: - 测试辅助

    private func makeOption(
        type: OptionType, strike: Decimal, daysFromNow: Int = 30
    ) -> OptionContract {
        let exp = Date().addingTimeInterval(TimeInterval(daysFromNow * 86400))
        return OptionContract(
            id: "TEST-\(type.rawValue)-\(strike)-\(daysFromNow)",
            underlyingID: "TEST", underlyingName: "测试",
            type: type, strikePrice: strike, expirationDate: exp,
            exerciseStyle: .european, contractMultiplier: 100,
            category: .stockIndex, exchange: .CFFEX
        )
    }

    private func makeContext(spotPrice: Double = 100, σ: Double = 0.25) -> OptionStrategyBuilder.Context {
        // 构造 5 strike × 1 到期 的 mini 链
        var contracts: [OptionContract] = []
        for s: Decimal in [90, 95, 100, 105, 110] {
            contracts.append(makeOption(type: .call, strike: s))
            contracts.append(makeOption(type: .put,  strike: s))
        }
        let chain = OptionChainBuilder.build(contracts: contracts)!
        return OptionStrategyBuilder.Context(chain: chain, spotPrice: spotPrice,
                                              riskFreeRate: 0.05, volatility: σ)
    }

    private func firstExpiration(_ ctx: OptionStrategyBuilder.Context) -> Date {
        ctx.chain.slices.first!.expirationDate
    }

    // MARK: - Leg payoff 数学

    @Test("Long Call leg · S>K · payoff = (S-K) - premium")
    func longCallPayoffITM() {
        let leg = OptionStrategyLeg(
            contract: makeOption(type: .call, strike: 100),
            direction: .long, quantity: 1, entryPremium: 5
        )
        // S=110 → max(110-100,0) - 5 = 5
        #expect(leg.payoffAtExpiration(spotPrice: 110) == 5)
    }

    @Test("Long Call leg · S<K · payoff = -premium")
    func longCallPayoffOTM() {
        let leg = OptionStrategyLeg(
            contract: makeOption(type: .call, strike: 100),
            direction: .long, quantity: 1, entryPremium: 5
        )
        #expect(leg.payoffAtExpiration(spotPrice: 90) == -5)
    }

    @Test("Short Put leg · S>K · payoff = +premium")
    func shortPutPayoffOTM() {
        let leg = OptionStrategyLeg(
            contract: makeOption(type: .put, strike: 100),
            direction: .short, quantity: 1, entryPremium: 5
        )
        #expect(leg.payoffAtExpiration(spotPrice: 110) == 5)
    }

    @Test("数量倍乘 · 2 张 long call · payoff × 2")
    func quantityMultiplier() {
        let leg = OptionStrategyLeg(
            contract: makeOption(type: .call, strike: 100),
            direction: .long, quantity: 2, entryPremium: 5
        )
        #expect(leg.payoffAtExpiration(spotPrice: 110) == 10)   // (10-5)*2
    }

    // MARK: - Strategy 净权利金

    @Test("netPremium · 牛市价差应为净付出（正值）")
    func netPremiumBullSpread() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        // long call(95) 比 short call(105) 贵 → 净付出
        #expect(s.netPremium > 0)
    }

    // MARK: - 牛市价差

    @Test("牛市价差 · 远端 PnL 有限利润")
    func bullCallSpreadShape() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        // S=80（远低）→ 净付出权利金（亏损）
        let pnlLow = s.payoffAtExpiration(spotPrice: 80)
        #expect(pnlLow < 0)
        // S=120（远高）→ (105-95) - 净付出 = 最大利润
        let pnlHigh = s.payoffAtExpiration(spotPrice: 120)
        #expect(pnlHigh > 0)
        // 顶部 = (highStrike - lowStrike) - netPremium
        let theoretical = (105 - 95) - s.netPremium
        #expect(abs(pnlHigh - theoretical) < 0.01)
    }

    @Test("牛市价差 · 利润不无限")
    func bullCallSpreadLimitedProfit() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(!analysis.isMaxProfitUnlimited)
        #expect(!analysis.isMaxLossUnlimited)
    }

    // MARK: - 熊市价差

    @Test("熊市价差 · S<lowStrike → 最大利润")
    func bearPutSpreadShape() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bearPutSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        let pnlLow = s.payoffAtExpiration(spotPrice: 80)
        let pnlHigh = s.payoffAtExpiration(spotPrice: 120)
        #expect(pnlLow > pnlHigh)   // 熊市 · 跌得越多越赚
    }

    // MARK: - 长跨式

    @Test("长跨式 · ATM 时最大亏损 = 净权利金")
    func longStraddleATMLoss() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100, expiration: firstExpiration(ctx)
        )!
        // S=K=100 → 全部 OTM/ITM 内在值=0 → 损 = -netPremium
        let pnlAtStrike = s.payoffAtExpiration(spotPrice: 100)
        #expect(abs(pnlAtStrike + s.netPremium) < 0.01)
    }

    @Test("长跨式 · 远端利润无限")
    func longStraddleUnlimitedProfit() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100, expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        // 标的远涨远跌都赚 · 利润无限
        #expect(analysis.isMaxProfitUnlimited)
        #expect(!analysis.isMaxLossUnlimited)   // 亏损 = 净权利金（有限）
    }

    // MARK: - 长宽跨式

    @Test("长宽跨式 · 中段亏损 · 两端盈利")
    func longStrangleShape() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStrangle(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        // S=100 中段 · 两腿都 OTM · 最大亏损 = -netPremium
        let pnlMid = s.payoffAtExpiration(spotPrice: 100)
        let pnlVeryHigh = s.payoffAtExpiration(spotPrice: 200)
        #expect(pnlVeryHigh > pnlMid)
    }

    // MARK: - 蝶式

    @Test("蝶式 · S=midStrike 时最大利润")
    func butterflyPeakAtMid() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longButterfly(
            context: ctx, lowStrike: 95, midStrike: 100, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        // S=100 mid · 利润最大
        let pnlMid = s.payoffAtExpiration(spotPrice: 100)
        let pnlLow = s.payoffAtExpiration(spotPrice: 90)
        let pnlHigh = s.payoffAtExpiration(spotPrice: 110)
        #expect(pnlMid > pnlLow)
        #expect(pnlMid > pnlHigh)
    }

    @Test("蝶式 · 利润亏损都有限")
    func butterflyLimitedBoth() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longButterfly(
            context: ctx, lowStrike: 95, midStrike: 100, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(!analysis.isMaxProfitUnlimited)
        #expect(!analysis.isMaxLossUnlimited)
    }

    // MARK: - PnL 分析器

    @Test("PnL 曲线长度 = sampleCount")
    func curveLength() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        let a = OptionPayoffAnalyzer.analyze(strategy: s, sampleCount: 100)
        #expect(a.curve.count == 100)
    }

    @Test("Breakevens · 牛市价差应有 1 个零点（lowStrike + netPremium）")
    func breakevensBullSpread() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 95, highStrike: 105,
            expiration: firstExpiration(ctx)
        )!
        let a = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(a.breakevens.count == 1)
        // 理论 breakeven = lowStrike + netPremium ≈ 95 + small
        let theoretical = 95 + s.netPremium
        if let be = a.breakevens.first {
            #expect(abs(be - theoretical) < 0.5)
        }
    }

    @Test("Breakevens · 长跨式 2 个零点（strike ± netPremium）")
    func breakevensStraddle() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.longStraddle(
            context: ctx, strike: 100, expiration: firstExpiration(ctx)
        )!
        let a = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(a.breakevens.count == 2)
    }

    // MARK: - Builder 异常

    @Test("Builder · strike 顺序错误返 nil（lowStrike >= highStrike）")
    func builderRejectsBadStrikes() {
        let ctx = makeContext()
        #expect(OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 105, highStrike: 95,
            expiration: firstExpiration(ctx)
        ) == nil)
    }

    @Test("Builder · 找不到合约返 nil")
    func builderRejectsMissingContract() {
        let ctx = makeContext()
        // 999 不在链中
        #expect(OptionStrategyBuilder.bullCallSpread(
            context: ctx, lowStrike: 999, highStrike: 1099,
            expiration: firstExpiration(ctx)
        ) == nil)
    }
}
