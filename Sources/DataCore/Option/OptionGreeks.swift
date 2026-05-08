// Option Greeks 计算（v15.28+ Phase 2 · WP-期权 数学层）
//
// 5 大 Greeks 解析公式（基于 BlackScholes.computeD1D2）：
//
//   Delta（Δ · 价敏度）·  ∂V/∂S
//     CALL Delta = e^(-qT) · N(d1)         · 范围 [0, e^(-qT)] · 贴近 1 实值深 / 0 虚值深
//     PUT  Delta = -e^(-qT) · N(-d1)       · 范围 [-e^(-qT), 0]
//
//   Gamma（Γ · Delta 凸度）· ∂²V/∂S² = ∂Delta/∂S
//     Gamma = e^(-qT) · n(d1) / (S · σ√T)  · CALL/PUT 同值（看涨看跌对称）
//
//   Theta（Θ · 时间衰减）· ∂V/∂T（每年）· 通常报告每日（除以 365）
//     CALL Theta = -S·e^(-qT)·n(d1)·σ/(2√T) - r·K·e^(-rT)·N(d2) + q·S·e^(-qT)·N(d1)
//     PUT  Theta = -S·e^(-qT)·n(d1)·σ/(2√T) + r·K·e^(-rT)·N(-d2) - q·S·e^(-qT)·N(-d1)
//
//   Vega（ν · 波动敏度）· ∂V/∂σ · 每 100% 波动（通常 /100 报告每 1%）
//     Vega = S · e^(-qT) · n(d1) · √T      · CALL/PUT 同值 · 同 Gamma 对称
//
//   Rho（ρ · 利率敏度）· ∂V/∂r · 每 100% 利率（通常 /100 报告每 1%）
//     CALL Rho =  K·T·e^(-rT)·N(d2)
//     PUT  Rho = -K·T·e^(-rT)·N(-d2)
//
// PCP（看涨看跌平价 · 验证用）：
//   CALL - PUT = S·e^(-qT) - K·e^(-rT)
//   Delta_call - Delta_put = e^(-qT)
//   Gamma_call = Gamma_put / Vega_call = Vega_put / Theta_call - Theta_put = -q·S·e^(-qT) + r·K·e^(-rT)

import Foundation

public enum OptionGreeks {

    /// 5 个 Greeks 聚合输出
    public struct Result: Sendable, Equatable {
        public let delta: Double     // Δ · 价敏度
        public let gamma: Double     // Γ · Delta 凸度
        public let theta: Double     // Θ · 每年时间衰减（除 365 = 每日）
        public let vega: Double      // ν · 每 100% 波动（除 100 = 每 1%）
        public let rho: Double       // ρ · 每 100% 利率（除 100 = 每 1%）

        public init(delta: Double, gamma: Double, theta: Double, vega: Double, rho: Double) {
            self.delta = delta; self.gamma = gamma; self.theta = theta
            self.vega = vega; self.rho = rho
        }

        public static let zero = Result(delta: 0, gamma: 0, theta: 0, vega: 0, rho: 0)
    }

    /// 计算 5 个 Greeks
    /// 边界：T<=0 / σ<=0 / S<=0 / K<=0 → 全 0（避免 div-by-zero · 调用方降级）
    public static func compute(type: OptionType, inputs: BlackScholes.Inputs) -> Result {
        let S = inputs.spotPrice
        let K = inputs.strikePrice
        let T = inputs.timeToExpirationYears
        let r = inputs.riskFreeRate
        let σ = inputs.volatility
        let q = inputs.dividendYield

        guard S > 0, K > 0, σ > 0, T > 0 else { return .zero }

        let (d1, d2) = BlackScholes.computeD1D2(S: S, K: K, T: T, r: r, σ: σ, q: q)
        let nD1 = BlackScholes.normalCDF(d1)
        let nD2 = BlackScholes.normalCDF(d2)
        let nMinusD1 = BlackScholes.normalCDF(-d1)
        let nMinusD2 = BlackScholes.normalCDF(-d2)
        let pdfD1 = BlackScholes.normalPDF(d1)

        let discountQ = exp(-q * T)
        let discountR = exp(-r * T)
        let sqrtT = sqrt(T)

        // Delta
        let delta: Double
        switch type {
        case .call: delta = discountQ * nD1
        case .put:  delta = -discountQ * nMinusD1
        }

        // Gamma（CALL/PUT 同 · 对标的对称）
        let gamma = discountQ * pdfD1 / (S * σ * sqrtT)

        // Theta（每年 · 除以 365 = 每日）
        let theta: Double
        switch type {
        case .call:
            theta = -S * discountQ * pdfD1 * σ / (2 * sqrtT)
                  - r * K * discountR * nD2
                  + q * S * discountQ * nD1
        case .put:
            theta = -S * discountQ * pdfD1 * σ / (2 * sqrtT)
                  + r * K * discountR * nMinusD2
                  - q * S * discountQ * nMinusD1
        }

        // Vega（每 100% 波动 · CALL/PUT 同）
        let vega = S * discountQ * pdfD1 * sqrtT

        // Rho（每 100% 利率）
        let rho: Double
        switch type {
        case .call: rho =  K * T * discountR * nD2
        case .put:  rho = -K * T * discountR * nMinusD2
        }

        return Result(delta: delta, gamma: gamma, theta: theta, vega: vega, rho: rho)
    }
}
