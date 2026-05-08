// OptionGreeks 单测（v15.28 · 期权 Phase 2）

import Foundation
import Testing
@testable import DataCore

@Suite("OptionGreeks · 5 大 Greeks 解析公式")
struct OptionGreeksTests {

    private let tolerance = 1e-3

    // 基准 ATM 输入：S=K=100, T=0.5, r=5%, σ=25%
    private let atm = BlackScholes.Inputs(
        spotPrice: 100, strikePrice: 100,
        timeToExpirationYears: 0.5,
        riskFreeRate: 0.05, volatility: 0.25
    )

    // MARK: - Delta

    @Test("CALL Delta · ATM ≈ 0.55-0.60（含 r、T 调整）")
    func callDeltaATM() {
        let g = OptionGreeks.compute(type: .call, inputs: atm)
        #expect(g.delta > 0.55 && g.delta < 0.65)
    }

    @Test("PUT Delta · ATM ≈ -0.40 ~ -0.45")
    func putDeltaATM() {
        let g = OptionGreeks.compute(type: .put, inputs: atm)
        #expect(g.delta < -0.35 && g.delta > -0.45)
    }

    @Test("CALL Delta - PUT Delta = e^(-qT) （PCP 推论 · q=0 → 1）")
    func deltaParity() {
        let inputs = BlackScholes.Inputs(spotPrice: 110, strikePrice: 100,
                                          timeToExpirationYears: 1, riskFreeRate: 0.05,
                                          volatility: 0.30)
        let cD = OptionGreeks.compute(type: .call, inputs: inputs).delta
        let pD = OptionGreeks.compute(type: .put, inputs: inputs).delta
        #expect(abs((cD - pD) - 1.0) < tolerance)   // q=0 时 = 1
    }

    @Test("CALL Delta 趋近 1 实值深 / 趋近 0 虚值深")
    func callDeltaExtremes() {
        let deepITM = BlackScholes.Inputs(spotPrice: 200, strikePrice: 100,
                                           timeToExpirationYears: 0.5,
                                           riskFreeRate: 0.05, volatility: 0.2)
        let deepOTM = BlackScholes.Inputs(spotPrice: 50, strikePrice: 100,
                                           timeToExpirationYears: 0.5,
                                           riskFreeRate: 0.05, volatility: 0.2)
        #expect(OptionGreeks.compute(type: .call, inputs: deepITM).delta > 0.95)
        #expect(OptionGreeks.compute(type: .call, inputs: deepOTM).delta < 0.05)
    }

    // MARK: - Gamma

    @Test("Gamma · CALL = PUT（看涨看跌对称）")
    func gammaCallPutEqual() {
        let cG = OptionGreeks.compute(type: .call, inputs: atm).gamma
        let pG = OptionGreeks.compute(type: .put, inputs: atm).gamma
        #expect(abs(cG - pG) < tolerance)
    }

    @Test("Gamma · ATM 最大 · 实值深 / 虚值深 衰减")
    func gammaPeakATM() {
        let atmG = OptionGreeks.compute(type: .call, inputs: atm).gamma
        let itmInputs = BlackScholes.Inputs(spotPrice: 130, strikePrice: 100,
                                             timeToExpirationYears: 0.5,
                                             riskFreeRate: 0.05, volatility: 0.25)
        let otmInputs = BlackScholes.Inputs(spotPrice: 70, strikePrice: 100,
                                             timeToExpirationYears: 0.5,
                                             riskFreeRate: 0.05, volatility: 0.25)
        let itmG = OptionGreeks.compute(type: .call, inputs: itmInputs).gamma
        let otmG = OptionGreeks.compute(type: .call, inputs: otmInputs).gamma
        #expect(atmG > itmG)
        #expect(atmG > otmG)
    }

    @Test("Gamma 必为正")
    func gammaPositive() {
        let g = OptionGreeks.compute(type: .call, inputs: atm)
        #expect(g.gamma > 0)
    }

    // MARK: - Vega

    @Test("Vega · CALL = PUT")
    func vegaCallPutEqual() {
        let cV = OptionGreeks.compute(type: .call, inputs: atm).vega
        let pV = OptionGreeks.compute(type: .put, inputs: atm).vega
        #expect(abs(cV - pV) < tolerance)
    }

    @Test("Vega · ATM 较大 · 远期 T 大 vega 大")
    func vegaScalesWithTime() {
        let near = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                        timeToExpirationYears: 0.1,
                                        riskFreeRate: 0.05, volatility: 0.25)
        let far  = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                        timeToExpirationYears: 1.0,
                                        riskFreeRate: 0.05, volatility: 0.25)
        let nearV = OptionGreeks.compute(type: .call, inputs: near).vega
        let farV  = OptionGreeks.compute(type: .call, inputs: far).vega
        #expect(farV > nearV)
    }

    // MARK: - Theta

    @Test("CALL Theta < 0 · 时间衰减")
    func callThetaNegative() {
        let g = OptionGreeks.compute(type: .call, inputs: atm)
        #expect(g.theta < 0)
    }

    @Test("PUT Theta · ATM 负值 · 远端可正（深虚 ITM PUT 例外）")
    func putThetaATMNegative() {
        let g = OptionGreeks.compute(type: .put, inputs: atm)
        #expect(g.theta < 0)
    }

    // MARK: - Rho

    @Test("CALL Rho > 0 · 利率↑ → CALL ↑")
    func callRhoPositive() {
        let g = OptionGreeks.compute(type: .call, inputs: atm)
        #expect(g.rho > 0)
    }

    @Test("PUT Rho < 0 · 利率↑ → PUT ↓")
    func putRhoNegative() {
        let g = OptionGreeks.compute(type: .put, inputs: atm)
        #expect(g.rho < 0)
    }

    // MARK: - 退化

    @Test("T=0 / σ=0 → 全 0 不崩")
    func degenerateInputs() {
        let zeroT = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                          timeToExpirationYears: 0,
                                          riskFreeRate: 0.05, volatility: 0.25)
        let g = OptionGreeks.compute(type: .call, inputs: zeroT)
        #expect(g == .zero)

        let zeroSigma = BlackScholes.Inputs(spotPrice: 100, strikePrice: 100,
                                             timeToExpirationYears: 0.5,
                                             riskFreeRate: 0.05, volatility: 0)
        let g2 = OptionGreeks.compute(type: .call, inputs: zeroSigma)
        #expect(g2 == .zero)
    }

    // MARK: - PCP 高阶

    @Test("Theta_call - Theta_put = q·S·e^(-qT) - r·K·e^(-rT)（q=0 简化为 -r·K·e^(-rT) ≈ -4.876）")
    func thetaPCP() {
        let S = 100.0, K = 100.0, T = 0.5, r = 0.05, σ = 0.25, q = 0.0
        let inputs = BlackScholes.Inputs(spotPrice: S, strikePrice: K,
                                          timeToExpirationYears: T,
                                          riskFreeRate: r, volatility: σ,
                                          dividendYield: q)
        let cT = OptionGreeks.compute(type: .call, inputs: inputs).theta
        let pT = OptionGreeks.compute(type: .put,  inputs: inputs).theta
        let theoretical = q * S * exp(-q * T) - r * K * exp(-r * T)
        // q=0 → -r·K·e^(-rT) ≈ -4.876
        #expect(abs((cT - pT) - theoretical) < tolerance)
    }
}
