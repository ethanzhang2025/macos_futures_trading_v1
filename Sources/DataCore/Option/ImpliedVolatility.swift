// 隐含波动率反推（v15.30 · 期权 Phase 3 · WP-期权 数学层）
//
// 输入：市场观察的期权价格（market price）
// 输出：使 BS(σ) = marketPrice 的 σ（隐含波动率）
//
// 算法：
//   1. Newton-Raphson 主算法（收敛快 · 用 vega 作 ∂price/∂σ）
//      - σ_{n+1} = σ_n - (BS(σ_n) - marketPrice) / vega(σ_n)
//      - 初值 σ_0 = 0.30（合理 ATM 猜测）
//      - 收敛 |BS(σ) - marketPrice| < tolerance
//   2. 失败 fallback：bisection 二分法
//      - 区间 [σLow=0.001, σHigh=5.0]（0.1% ~ 500% 覆盖所有合理 IV）
//      - 验证 f(low) × f(high) < 0（异号 = 有解）· 否则返 nil（市价不合理）
//
// 边界：
//   - 市价 < 内在价值 → nil（套利违例 · 不存在合法 IV）
//   - 市价 > 标的价 (CALL) / 市价 > 行权价 (PUT) → nil（同上）
//   - σ 接近 0 或 5 时 vega 退化 → bisection 接管

import Foundation

public enum ImpliedVolatility {

    /// 反推参数
    public struct Options: Sendable {
        public let initialGuess: Double      // 初始 σ 猜测（默认 0.30）
        public let tolerance: Double         // 收敛阈值（默认 1e-6 · 价差）
        public let maxNewtonIterations: Int  // Newton 最大迭代（默认 50）
        public let maxBisectionIterations: Int // bisection 最大迭代（默认 200）
        public let minSigma: Double          // bisection 下界（默认 0.001）
        public let maxSigma: Double          // bisection 上界（默认 5.0）

        public init(
            initialGuess: Double = 0.30,
            tolerance: Double = 1e-6,
            maxNewtonIterations: Int = 50,
            maxBisectionIterations: Int = 200,
            minSigma: Double = 0.001,
            maxSigma: Double = 5.0
        ) {
            self.initialGuess = initialGuess
            self.tolerance = tolerance
            self.maxNewtonIterations = maxNewtonIterations
            self.maxBisectionIterations = maxBisectionIterations
            self.minSigma = minSigma
            self.maxSigma = maxSigma
        }

        public static let `default` = Options()
    }

    /// 反推隐含波动率（自动选 Newton / bisection）
    /// - Parameters:
    ///   - type: CALL / PUT
    ///   - marketPrice: 市场观察价格
    ///   - inputs: BS 输入（除 σ 字段忽略外其他用上）
    ///   - options: 算法参数
    /// - Returns: 隐含波动率 σ；不存在合法 IV / 不收敛时返 nil
    public static func compute(
        type: OptionType,
        marketPrice: Double,
        inputs: BlackScholes.Inputs,
        options: Options = .default
    ) -> Double? {
        // 边界：市价必 ≥ 内在价值（套利约束）
        let intrinsic = computeIntrinsic(type: type, S: inputs.spotPrice, K: inputs.strikePrice,
                                          r: inputs.riskFreeRate, q: inputs.dividendYield,
                                          T: inputs.timeToExpirationYears)
        guard marketPrice >= intrinsic - options.tolerance else { return nil }
        // 输入退化（T<=0）→ 仅当市价 ≈ 内在价值时返 0；否则 nil
        guard inputs.timeToExpirationYears > 0 else {
            return abs(marketPrice - intrinsic) < options.tolerance ? 0 : nil
        }

        // 1. Newton-Raphson 尝试
        if let σ = newtonRaphson(type: type, marketPrice: marketPrice,
                                 inputs: inputs, options: options) {
            return σ
        }
        // 2. bisection fallback
        return bisection(type: type, marketPrice: marketPrice,
                         inputs: inputs, options: options)
    }

    // MARK: - Newton-Raphson

    private static func newtonRaphson(
        type: OptionType, marketPrice: Double,
        inputs: BlackScholes.Inputs, options: Options
    ) -> Double? {
        var σ = options.initialGuess
        for _ in 0..<options.maxNewtonIterations {
            let modified = inputsWithSigma(inputs, σ: σ)
            let price = BlackScholes.price(type: type, inputs: modified)
            let diff = price - marketPrice
            if abs(diff) < options.tolerance {
                guard σ >= options.minSigma && σ <= options.maxSigma else { return nil }
                return σ
            }
            let vega = OptionGreeks.compute(type: type, inputs: modified).vega
            // vega 太小 (近 ATM 末日 / 极端 OTM) → 不收敛 · 让 bisection 接管
            guard vega > 1e-10 else { return nil }
            σ -= diff / vega
            // 跳出合理范围 · 让 bisection 接管
            if σ <= options.minSigma || σ >= options.maxSigma { return nil }
        }
        return nil
    }

    // MARK: - bisection（二分法兜底）

    private static func bisection(
        type: OptionType, marketPrice: Double,
        inputs: BlackScholes.Inputs, options: Options
    ) -> Double? {
        var lo = options.minSigma
        var hi = options.maxSigma

        let priceLow = BlackScholes.price(type: type, inputs: inputsWithSigma(inputs, σ: lo))
        let priceHigh = BlackScholes.price(type: type, inputs: inputsWithSigma(inputs, σ: hi))

        // BS 价格随 σ 单调递增 · 因此目标价应在 [priceLow, priceHigh] 区间内
        if marketPrice < priceLow - options.tolerance { return nil }
        if marketPrice > priceHigh + options.tolerance { return nil }

        for _ in 0..<options.maxBisectionIterations {
            let mid = (lo + hi) / 2
            let priceMid = BlackScholes.price(type: type, inputs: inputsWithSigma(inputs, σ: mid))
            if abs(priceMid - marketPrice) < options.tolerance {
                return mid
            }
            if priceMid < marketPrice {
                lo = mid
            } else {
                hi = mid
            }
            if hi - lo < options.tolerance {
                return (lo + hi) / 2
            }
        }
        return (lo + hi) / 2   // 达到迭代上限 · 返当前最佳估计
    }

    // MARK: - private helpers

    private static func inputsWithSigma(_ orig: BlackScholes.Inputs, σ: Double) -> BlackScholes.Inputs {
        BlackScholes.Inputs(
            spotPrice: orig.spotPrice,
            strikePrice: orig.strikePrice,
            timeToExpirationYears: orig.timeToExpirationYears,
            riskFreeRate: orig.riskFreeRate,
            volatility: σ,
            dividendYield: orig.dividendYield
        )
    }

    /// 内在价值（含贴现 · 用于市价合法性检查）
    /// 严格说欧式期权下界 = max(S·e^(-qT) - K·e^(-rT), 0) for CALL / max(K·e^(-rT) - S·e^(-qT), 0) for PUT
    private static func computeIntrinsic(
        type: OptionType, S: Double, K: Double, r: Double, q: Double, T: Double
    ) -> Double {
        guard T > 0 else {
            switch type {
            case .call: return max(S - K, 0)
            case .put:  return max(K - S, 0)
            }
        }
        let discountedS = S * exp(-q * T)
        let discountedK = K * exp(-r * T)
        switch type {
        case .call: return max(discountedS - discountedK, 0)
        case .put:  return max(discountedK - discountedS, 0)
        }
    }
}
