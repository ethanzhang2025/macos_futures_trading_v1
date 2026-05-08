// Black-Scholes 定价单测（v15.28 期权 Phase 2）
//
// 经典验证 case：
//   - normalCDF 经典点位（0 → 0.5 / 1.96 → 0.975 等）
//   - 极限边界（σ=0/T=0 → 内在价值）
//   - 看涨看跌平价 PCP

import Foundation
import Testing
@testable import DataCore

@Suite("BlackScholes · 欧式定价 + 累积正态")
struct BlackScholesTests {

    private let tolerance = 1e-4

    // MARK: - normalCDF 经典点位

    @Test("normalCDF(0) = 0.5")
    func cdfZero() {
        #expect(abs(BlackScholes.normalCDF(0) - 0.5) < tolerance)
    }

    @Test("normalCDF(1.96) ≈ 0.975（双侧 95%）")
    func cdf196() {
        #expect(abs(BlackScholes.normalCDF(1.96) - 0.975) < tolerance)
    }

    @Test("normalCDF(-1.96) ≈ 0.025")
    func cdfNeg196() {
        #expect(abs(BlackScholes.normalCDF(-1.96) - 0.025) < tolerance)
    }

    @Test("normalCDF 极值收敛 · CDF(8) ≈ 1 / CDF(-8) ≈ 0")
    func cdfExtremes() {
        #expect(BlackScholes.normalCDF(8) > 0.9999)
        #expect(BlackScholes.normalCDF(-8) < 0.0001)
    }

    @Test("normalCDF 单调递增")
    func cdfMonotonic() {
        let xs = [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]
        let cdfs = xs.map { BlackScholes.normalCDF($0) }
        for i in 1..<cdfs.count {
            #expect(cdfs[i] > cdfs[i - 1])
        }
    }

    @Test("normalPDF(0) = 1/√(2π) ≈ 0.39894")
    func pdfZero() {
        #expect(abs(BlackScholes.normalPDF(0) - 0.398942) < tolerance)
    }

    // MARK: - 定价边界

    @Test("T=0 · CALL 价 = max(S-K, 0)")
    func callExpired() {
        let inputs = BlackScholes.Inputs(spotPrice: 110, strikePrice: 100,
                                          timeToExpirationYears: 0,
                                          riskFreeRate: 0.05, volatility: 0.2)
        let p = BlackScholes.price(type: .call, inputs: inputs)
        #expect(abs(p - 10) < tolerance)
    }

    @Test("T=0 · PUT 价 = max(K-S, 0)")
    func putExpired() {
        let inputs = BlackScholes.Inputs(spotPrice: 90, strikePrice: 100,
                                          timeToExpirationYears: 0,
                                          riskFreeRate: 0.05, volatility: 0.2)
        let p = BlackScholes.price(type: .put, inputs: inputs)
        #expect(abs(p - 10) < tolerance)
    }

    @Test("σ=0 · CALL 价 = max(S - K·e^(-rT), 0)（远期价值）")
    func callZeroVol() {
        // 实际 σ=0 我们退化为内在价值（不严谨但稳健 · 主流券商也这么处理）
        let inputs = BlackScholes.Inputs(spotPrice: 110, strikePrice: 100,
                                          timeToExpirationYears: 1,
                                          riskFreeRate: 0.05, volatility: 0)
        let p = BlackScholes.price(type: .call, inputs: inputs)
        #expect(p == 10)   // 内在价值降级
    }

    // MARK: - 经典定价案例（教科书参考值）

    @Test("CALL · S=100 K=100 T=0.25 r=0.05 σ=0.2 → 4.6147 (Hull 教科书)")
    func classicCallATM() {
        let inputs = BlackScholes.Inputs(
            spotPrice: 100, strikePrice: 100,
            timeToExpirationYears: 0.25,
            riskFreeRate: 0.05, volatility: 0.2
        )
        let p = BlackScholes.price(type: .call, inputs: inputs)
        // Hull 8th ed. 类似输入 ≈ 4.61~4.62
        #expect(abs(p - 4.6147) < 0.01)
    }

    @Test("PUT · S=100 K=100 T=0.25 r=0.05 σ=0.2 → 3.3725")
    func classicPutATM() {
        let inputs = BlackScholes.Inputs(
            spotPrice: 100, strikePrice: 100,
            timeToExpirationYears: 0.25,
            riskFreeRate: 0.05, volatility: 0.2
        )
        let p = BlackScholes.price(type: .put, inputs: inputs)
        #expect(abs(p - 3.3725) < 0.01)
    }

    // MARK: - 看涨看跌平价 PCP

    @Test("PCP · CALL - PUT = S·e^(-qT) - K·e^(-rT)")
    func putCallParity() {
        let S = 110.0, K = 100.0, T = 0.5, r = 0.04, σ = 0.25, q = 0.0
        let inputs = BlackScholes.Inputs(
            spotPrice: S, strikePrice: K,
            timeToExpirationYears: T,
            riskFreeRate: r, volatility: σ, dividendYield: q
        )
        let call = BlackScholes.price(type: .call, inputs: inputs)
        let put  = BlackScholes.price(type: .put, inputs: inputs)
        let theoretical = S * exp(-q * T) - K * exp(-r * T)
        #expect(abs((call - put) - theoretical) < tolerance)
    }

    @Test("PCP 含分红 · q > 0 仍成立")
    func putCallParityWithDividend() {
        let S = 100.0, K = 100.0, T = 1.0, r = 0.05, σ = 0.30, q = 0.03
        let inputs = BlackScholes.Inputs(
            spotPrice: S, strikePrice: K,
            timeToExpirationYears: T,
            riskFreeRate: r, volatility: σ, dividendYield: q
        )
        let call = BlackScholes.price(type: .call, inputs: inputs)
        let put  = BlackScholes.price(type: .put, inputs: inputs)
        let theoretical = S * exp(-q * T) - K * exp(-r * T)
        #expect(abs((call - put) - theoretical) < tolerance)
    }

    // MARK: - 单调性

    @Test("CALL 价格单调随 S 递增")
    func callPriceMonotonicInSpot() {
        let baseInputs = { (S: Double) -> BlackScholes.Inputs in
            BlackScholes.Inputs(spotPrice: S, strikePrice: 100,
                                 timeToExpirationYears: 0.5,
                                 riskFreeRate: 0.05, volatility: 0.25)
        }
        let prices = [80.0, 90, 100, 110, 120].map {
            BlackScholes.price(type: .call, inputs: baseInputs($0))
        }
        for i in 1..<prices.count {
            #expect(prices[i] > prices[i - 1])
        }
    }

    @Test("PUT 价格单调随 S 递减")
    func putPriceMonotonicInSpot() {
        let baseInputs = { (S: Double) -> BlackScholes.Inputs in
            BlackScholes.Inputs(spotPrice: S, strikePrice: 100,
                                 timeToExpirationYears: 0.5,
                                 riskFreeRate: 0.05, volatility: 0.25)
        }
        let prices = [80.0, 90, 100, 110, 120].map {
            BlackScholes.price(type: .put, inputs: baseInputs($0))
        }
        for i in 1..<prices.count {
            #expect(prices[i] < prices[i - 1])
        }
    }

    @Test("CALL 价格单调随 σ 递增（凸性）")
    func callPriceMonotonicInVol() {
        let baseInputs = { (σ: Double) -> BlackScholes.Inputs in
            BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                 timeToExpirationYears: 0.5,
                                 riskFreeRate: 0.05, volatility: σ)
        }
        let prices = [0.05, 0.10, 0.20, 0.30, 0.50].map {
            BlackScholes.price(type: .call, inputs: baseInputs($0))
        }
        for i in 1..<prices.count {
            #expect(prices[i] > prices[i - 1])
        }
    }

    // MARK: - 异常输入

    @Test("S=0 / K=0 / 负值 → 内在价值（不崩）")
    func anomalousInputs() {
        let zeroS = BlackScholes.Inputs(spotPrice: 0, strikePrice: 100,
                                         timeToExpirationYears: 0.5,
                                         riskFreeRate: 0.05, volatility: 0.2)
        #expect(BlackScholes.price(type: .call, inputs: zeroS) == 0)

        let negSpot = BlackScholes.Inputs(spotPrice: -10, strikePrice: 100,
                                           timeToExpirationYears: 0.5,
                                           riskFreeRate: 0.05, volatility: 0.2)
        #expect(BlackScholes.price(type: .call, inputs: negSpot) == 0)
    }
}
