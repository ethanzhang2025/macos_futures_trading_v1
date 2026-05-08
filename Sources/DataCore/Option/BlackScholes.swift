// Black-Scholes 期权定价（v15.28+ Phase 2 · WP-期权 数学层）
//
// 经典 Black-Scholes-Merton 1973 模型：欧式期权理论价 + Greeks
// 美式期权暂用 BS 近似（v3 接二叉树 / 蒙特卡洛）
//
// 核心公式（不分红 · 含连续分红率扩展 q）：
//   d1 = [ln(S/K) + (r - q + σ²/2)T] / (σ√T)
//   d2 = d1 - σ√T
//
//   CALL = S·e^(-qT)·N(d1) - K·e^(-rT)·N(d2)
//   PUT  = K·e^(-rT)·N(-d2) - S·e^(-qT)·N(-d1)
//
//   PCP（看涨看跌平价）：CALL - PUT = S·e^(-qT) - K·e^(-rT)
//
// 数值实现：
//   - N(x) 累积正态 · 用 Abramowitz-Stegun 7.1.26 多项式逼近（精度 7e-8）
//   - n(x) pdf · 直接 1/√(2π) · e^(-x²/2)
//
// 单位约定：
//   - 价格、行权价：与现价同量纲（ETF 期权用元 · 期货期权用价位）
//   - 时间 T：年化（30 天 = 30/365）
//   - 利率 r、分红率 q、波动率 σ：年化 · 小数（0.05 = 5%）

import Foundation

public enum BlackScholes {

    /// 输入参数（Double 数学库友好 · v3 可包 Decimal 适配）
    public struct Inputs: Sendable {
        public let spotPrice: Double         // S · 标的现价
        public let strikePrice: Double       // K · 行权价
        public let timeToExpirationYears: Double // T · 距到期年数（30 天 = 30/365）
        public let riskFreeRate: Double      // r · 无风险年化利率（0.025 = 2.5%）
        public let volatility: Double        // σ · 年化波动率（0.20 = 20%）
        public let dividendYield: Double     // q · 连续分红率（默认 0 · 期货期权用 0 即可）

        public init(
            spotPrice: Double, strikePrice: Double,
            timeToExpirationYears: Double, riskFreeRate: Double,
            volatility: Double, dividendYield: Double = 0
        ) {
            self.spotPrice = spotPrice
            self.strikePrice = strikePrice
            self.timeToExpirationYears = timeToExpirationYears
            self.riskFreeRate = riskFreeRate
            self.volatility = volatility
            self.dividendYield = dividendYield
        }
    }

    // MARK: - 理论价

    /// 欧式期权理论价
    /// 边界处理：
    ///   - T <= 0 → 内在价值（max(S-K, 0) for CALL · max(K-S, 0) for PUT）
    ///   - σ <= 0 或 S/K <= 0 → 0（异常输入降级）
    public static func price(type: OptionType, inputs: Inputs) -> Double {
        let S = inputs.spotPrice
        let K = inputs.strikePrice
        let T = inputs.timeToExpirationYears
        let r = inputs.riskFreeRate
        let σ = inputs.volatility
        let q = inputs.dividendYield

        guard S > 0, K > 0, σ > 0, T > 0 else {
            // 退化为内在价值
            switch type {
            case .call: return Swift.max(S - K, 0)
            case .put:  return Swift.max(K - S, 0)
            }
        }

        let (d1, d2) = computeD1D2(S: S, K: K, T: T, r: r, σ: σ, q: q)
        let discountQ = exp(-q * T)
        let discountR = exp(-r * T)

        switch type {
        case .call:
            return S * discountQ * normalCDF(d1) - K * discountR * normalCDF(d2)
        case .put:
            return K * discountR * normalCDF(-d2) - S * discountQ * normalCDF(-d1)
        }
    }

    // MARK: - 累积正态 N(x)（Abramowitz-Stegun 7.1.26）

    /// 标准正态累积分布 P(X ≤ x) · 精度 ~7.5e-8
    public static func normalCDF(_ x: Double) -> Double {
        let absX = abs(x)
        if absX > 8 { return x > 0 ? 1 : 0 }   // 超出有效范围

        // Abramowitz-Stegun 7.1.26 系数
        let a1 =  0.254829592
        let a2 = -0.284496736
        let a3 =  1.421413741
        let a4 = -1.453152027
        let a5 =  1.061405429
        let p = 0.3275911

        let sign: Double = x < 0 ? -1 : 1
        let xAbs = absX / sqrt(2.0)
        let t = 1.0 / (1.0 + p * xAbs)
        let erf = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-xAbs * xAbs)
        return 0.5 * (1.0 + sign * erf)
    }

    /// 标准正态密度 n(x) = 1/√(2π) · e^(-x²/2)
    public static func normalPDF(_ x: Double) -> Double {
        return exp(-x * x / 2) / sqrt(2 * .pi)
    }

    // MARK: - d1 / d2

    /// 计算 d1 / d2（公开 · Greeks 共用 · 失败返 (0,0) 由调用方处理）
    public static func computeD1D2(
        S: Double, K: Double, T: Double, r: Double, σ: Double, q: Double
    ) -> (d1: Double, d2: Double) {
        guard S > 0, K > 0, σ > 0, T > 0 else { return (0, 0) }
        let σSqrtT = σ * sqrt(T)
        let d1 = (log(S / K) + (r - q + σ * σ / 2) * T) / σSqrtT
        let d2 = d1 - σSqrtT
        return (d1, d2)
    }
}
