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

    // MARK: - 铁鹰

    @Test("铁鹰 · 4 leg 构造正确（PutK1 long / PutK2 short / CallK3 short / CallK4 long）")
    func ironCondorLegStructure() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 95,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        )!
        #expect(s.legs.count == 4)
        // leg[0] = Long Put@90
        #expect(s.legs[0].direction == .long)
        #expect(s.legs[0].contract.type == .put)
        #expect(s.legs[0].contract.strikePrice == 90)
        // leg[1] = Short Put@95
        #expect(s.legs[1].direction == .short)
        #expect(s.legs[1].contract.type == .put)
        #expect(s.legs[1].contract.strikePrice == 95)
        // leg[2] = Short Call@105
        #expect(s.legs[2].direction == .short)
        #expect(s.legs[2].contract.type == .call)
        #expect(s.legs[2].contract.strikePrice == 105)
        // leg[3] = Long Call@110
        #expect(s.legs[3].direction == .long)
        #expect(s.legs[3].contract.type == .call)
        #expect(s.legs[3].contract.strikePrice == 110)
    }

    @Test("铁鹰 · 净权利金为负（净收入 · 卖方策略）")
    func ironCondorNetCredit() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 95,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        )!
        // 卖近虚值（K2 Put · K3 Call）+ 买远虚值（K1 Put · K4 Call）→ 收净权利金 → netPremium < 0
        #expect(s.netPremium < 0)
    }

    @Test("铁鹰 · S 在 [PutK2, CallK3] 中段 · 接近最大利润（净收入）")
    func ironCondorMaxProfitInMiddle() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 95,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        )!
        // S=100 落在 [95, 105] 区间 · 4 腿全 OTM → PnL = -netPremium = +netCredit
        let pnlMid = s.payoffAtExpiration(spotPrice: 100)
        #expect(abs(pnlMid + s.netPremium) < 0.01)
    }

    @Test("铁鹰 · 远端利润亏损都有限（4 腿对冲）")
    func ironCondorLimitedBoth() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 95,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(!analysis.isMaxProfitUnlimited)
        #expect(!analysis.isMaxLossUnlimited)
    }

    @Test("铁鹰 · 损益平衡 2 个零点（K2 上方 + K3 下方各 1）")
    func ironCondorBreakevens() {
        let ctx = makeContext()
        let s = OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 95,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(analysis.breakevens.count == 2)
        // 下侧 breakeven 应在 (90, 95) 区间内（PutK2 - netCredit）
        // 上侧 breakeven 应在 (105, 110) 区间内（CallK3 + netCredit）
        if analysis.breakevens.count == 2 {
            let lo = analysis.breakevens[0]
            let hi = analysis.breakevens[1]
            #expect(lo > 90 && lo < 95)
            #expect(hi > 105 && hi < 110)
        }
    }

    // MARK: - 备兑开仓

    @Test("备兑开仓 · 单 leg = Short Call · positionSize=quantity")
    func coveredCallStructure() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.coveredCall(
            context: ctx, callStrike: 105, expiration: firstExpiration(ctx), quantity: 1
        )!
        #expect(s.legs.count == 1)
        #expect(s.legs[0].direction == .short)
        #expect(s.legs[0].contract.type == .call)
        #expect(s.legs[0].contract.strikePrice == 105)
        #expect(s.underlyingPositionSize == 1)
        #expect(s.underlyingEntryPrice == 100)
    }

    @Test("备兑开仓 · S=entryPrice · PnL = +callPremium（卖方收权利金 · 标的不动）")
    func coveredCallAtEntryPrice() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.coveredCall(
            context: ctx, callStrike: 105, expiration: firstExpiration(ctx)
        )!
        // S=100=entryPrice · 标的 PnL=0 · short call OTM → +premium
        let pnl = s.payoffAtExpiration(spotPrice: 100)
        let callPremium = s.legs[0].entryPremium
        #expect(abs(pnl - callPremium) < 0.01)
    }

    @Test("备兑开仓 · S 远超 callStrike · 利润有限被锁顶（K - S0 + premium）")
    func coveredCallCappedUpside() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.coveredCall(
            context: ctx, callStrike: 105, expiration: firstExpiration(ctx)
        )!
        // S=200 远超 105 · 被行权
        // 标的 PnL = 200 - 100 = 100
        // short call PnL = -(200-105) + premium = -95 + premium
        // total = 100 - 95 + premium = 5 + premium = (K - entry) + premium
        let pnl = s.payoffAtExpiration(spotPrice: 200)
        let theoretical = (105 - 100) + s.legs[0].entryPremium
        #expect(abs(pnl - theoretical) < 0.01)
    }

    @Test("备兑开仓 · 利润有限 · 亏损虽大但有限（标的不会跌成负数）")
    func coveredCallLimitedProfit() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.coveredCall(
            context: ctx, callStrike: 105, expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(!analysis.isMaxProfitUnlimited)
    }

    // MARK: - 保护性看跌

    @Test("保护性看跌 · S 远低 putStrike · 亏损被锁底（K - S0 - premium）")
    func protectivePutDownsideFloor() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.protectivePut(
            context: ctx, putStrike: 95, expiration: firstExpiration(ctx)
        )!
        // S=50 远低
        // 标的 PnL = 50 - 100 = -50
        // long put PnL = (95-50) - premium = 45 - premium
        // total = -50 + 45 - premium = -5 - premium = -(S0-K) - premium
        let pnl = s.payoffAtExpiration(spotPrice: 50)
        let theoretical = -(100.0 - 95) - s.legs[0].entryPremium
        #expect(abs(pnl - theoretical) < 0.01)
    }

    @Test("保护性看跌 · 上方利润无限（标的可一直涨 · 仅扣 put premium）")
    func protectivePutUnlimitedUpside() {
        let ctx = makeContext(spotPrice: 100)
        let s = OptionStrategyBuilder.protectivePut(
            context: ctx, putStrike: 95, expiration: firstExpiration(ctx)
        )!
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s)
        #expect(analysis.isMaxProfitUnlimited)
        #expect(!analysis.isMaxLossUnlimited)
    }

    @Test("备兑/保护性 · positionSize=0 时 · 退化成纯期权策略")
    func coveredCallZeroPosition() {
        let ctx = makeContext(spotPrice: 100)
        // 手动构造无标的的 short call · 验 OptionStrategy 默认 positionSize=0
        let bareShortCall = OptionStrategy(
            id: "bare-short-call",
            name: "裸卖 Call",
            strategyType: .custom,
            legs: [OptionStrategyLeg(
                contract: makeOption(type: .call, strike: 105),
                direction: .short, quantity: 1, entryPremium: 3
            )],
            underlyingID: "TEST", underlyingName: "测试"
        )
        // S=200 · 裸卖 call 亏损巨大 · 不会被标的对冲
        let pnl = bareShortCall.payoffAtExpiration(spotPrice: 200)
        #expect(pnl < -50)  // 实际 = -(200-105) + 3 = -92
    }

    @Test("铁鹰 · strike 顺序违例返 nil（要求 K1<K2<K3<K4）")
    func ironCondorRejectsBadOrder() {
        let ctx = makeContext()
        // K2 >= K3 违例
        #expect(OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 90, putHighStrike: 105,
            callLowStrike: 100, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        ) == nil)
        // K1 >= K2 违例
        #expect(OptionStrategyBuilder.ironCondor(
            context: ctx,
            putLowStrike: 95, putHighStrike: 90,
            callLowStrike: 105, callHighStrike: 110,
            expiration: firstExpiration(ctx)
        ) == nil)
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
