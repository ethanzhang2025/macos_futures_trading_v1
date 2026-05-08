// ImpliedVolatility 单测（v15.30 · 期权 Phase 3）

import Foundation
import Testing
@testable import DataCore

@Suite("ImpliedVolatility · Newton + bisection 反推")
struct ImpliedVolatilityTests {

    private let tolerance = 1e-3   // IV 精度 0.1%

    // MARK: - 圆环测试（BS → price → IV ≈ σ_orig）

    @Test("圆环 · CALL ATM σ=25% → 反推 ≈ 25%")
    func roundTripCallATM() {
        let σOrig = 0.25
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(iv != nil)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · PUT ATM σ=30% → 反推 ≈ 30%")
    func roundTripPutATM() {
        let σOrig = 0.30
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .put, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .put, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · CALL ITM σ=20% · S=120 K=100")
    func roundTripCallITM() {
        let σOrig = 0.20
        let inputs = BlackScholes.Inputs(spotPrice: 120, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · CALL OTM σ=40% · S=80 K=100")
    func roundTripCallOTM() {
        let σOrig = 0.40
        let inputs = BlackScholes.Inputs(spotPrice: 80, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · 极端 σ=80% · 反推仍准")
    func roundTripExtremeVol() {
        let σOrig = 0.80
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · 短 T=10 天 · σ=40%")
    func roundTripShortMaturity() {
        let σOrig = 0.40
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 10.0 / 365.0,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    @Test("圆环 · 长 T=2 年 · σ=15%")
    func roundTripLongMaturity() {
        let σOrig = 0.15
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 2.0,
                                          riskFreeRate: 0.05, volatility: σOrig)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(abs((iv ?? 0) - σOrig) < tolerance)
    }

    // MARK: - 边界（不合法市价 → nil）

    @Test("市价 < 内在价值 → nil（套利违例）")
    func priceBelowIntrinsicReturnsNil() {
        let inputs = BlackScholes.Inputs(spotPrice: 120, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: 0.30)
        // 内在价值 ≈ 120 - 100·e^(-0.025) ≈ 22.47 · 给市价 5（明显违例）
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: 5, inputs: inputs)
        #expect(iv == nil)
    }

    @Test("T=0 + 市价 ≠ 内在价值 → nil")
    func zeroTimeWithBadPriceNil() {
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0,
                                          riskFreeRate: 0.05, volatility: 0.30)
        // T=0 内在价值 = 0 · 给市价 5（应返 nil 或 0）
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: 5, inputs: inputs)
        #expect(iv == nil)
    }

    @Test("T=0 + 市价 = 内在价值 → 0")
    func zeroTimeWithIntrinsicReturnsZero() {
        let inputs = BlackScholes.Inputs(spotPrice: 110, strikePrice: 100,
                                          timeToExpirationYears: 0,
                                          riskFreeRate: 0.05, volatility: 0.30)
        // T=0 内在价值 = max(110-100, 0) = 10
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: 10, inputs: inputs)
        #expect(iv == 0)
    }

    // MARK: - 收敛性

    @Test("收敛快 · ATM 通常 < 5 次 Newton 迭代")
    func atmConvergesQuickly() {
        // 此测试验证不超过默认 maxIterations · 实际收敛速度由内部 Newton 决定
        // 我们间接验证：默认参数下成功
        let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0.5,
                                          riskFreeRate: 0.05, volatility: 0.25)
        let price = BlackScholes.price(type: .call, inputs: inputs)
        let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs)
        #expect(iv != nil)
    }

    // MARK: - 多 case 批量验证（不同行权价）

    @Test("批量 · 9 strike × σ=25% 圆环全部成功")
    func batchRoundTrip9Strikes() {
        let σOrig = 0.25
        let strikes: [Double] = [80, 85, 90, 95, 100, 105, 110, 115, 120]
        var passCount = 0
        for K in strikes {
            let inputs = BlackScholes.Inputs(spotPrice: 100, strikePrice: K,
                                              timeToExpirationYears: 0.5,
                                              riskFreeRate: 0.05, volatility: σOrig)
            let price = BlackScholes.price(type: .call, inputs: inputs)
            if let iv = ImpliedVolatility.compute(type: .call, marketPrice: price, inputs: inputs),
               abs(iv - σOrig) < tolerance {
                passCount += 1
            }
        }
        #expect(passCount == strikes.count)
    }
}
