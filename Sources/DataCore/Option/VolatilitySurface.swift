// 波动率曲面（v15.30 · 期权 Phase 3 · WP-期权 数学层）
//
// 期权交易者必看：IV 在 (strike × expiration) 二维网格上的形状
//
// 经典形态：
//   - Smile（笑）：ATM 最低 · 实虚两端高（股市常见）
//   - Skew（偏斜）：低 strike 高（put-skew · 危机保护溢价）
//   - Term Structure（期限结构）：远期 IV 通常高于近期（不确定性递增）
//
// 数据结构：
//   - VolatilityPoint = 单格（strike + T + IV）
//   - VolatilitySurface = 完整曲面（多 strike × 多 T）

import Foundation

/// 单格 IV 数据点
public struct VolatilityPoint: Sendable, Equatable {
    public let strikePrice: Double         // K
    public let timeToExpiration: Double    // T（年）
    public let impliedVolatility: Double   // σ（年化 · 0.20 = 20%）
    public let optionType: OptionType      // CALL / PUT（决定从哪边推 IV）
    public let marketPrice: Double         // 当时观察到的市价（调试用）

    public init(strikePrice: Double, timeToExpiration: Double,
                impliedVolatility: Double, optionType: OptionType,
                marketPrice: Double) {
        self.strikePrice = strikePrice
        self.timeToExpiration = timeToExpiration
        self.impliedVolatility = impliedVolatility
        self.optionType = optionType
        self.marketPrice = marketPrice
    }
}

/// 完整波动率曲面（多 strike × 多 T 的 IV 网格）
public struct VolatilitySurface: Sendable, Equatable {
    public let underlyingID: String
    public let underlyingName: String
    public let spotPrice: Double           // 标的现价（曲面的中心位）
    public let riskFreeRate: Double        // r（建曲面时使用）
    public let dividendYield: Double       // q
    public let points: [VolatilityPoint]   // 所有有效格点

    public init(underlyingID: String, underlyingName: String,
                spotPrice: Double, riskFreeRate: Double,
                dividendYield: Double, points: [VolatilityPoint]) {
        self.underlyingID = underlyingID
        self.underlyingName = underlyingName
        self.spotPrice = spotPrice
        self.riskFreeRate = riskFreeRate
        self.dividendYield = dividendYield
        self.points = points
    }

    /// 按 T 分组（按到期日切片）
    public var byExpiration: [Double: [VolatilityPoint]] {
        Dictionary(grouping: points, by: { $0.timeToExpiration })
    }

    /// 按 strike 分组（按行权价切片）
    public var byStrike: [Double: [VolatilityPoint]] {
        Dictionary(grouping: points, by: { $0.strikePrice })
    }

    /// 全部 strike（升序去重）
    public var allStrikes: [Double] {
        Array(Set(points.map { $0.strikePrice })).sorted()
    }

    /// 全部 T（升序去重）
    public var allExpirations: [Double] {
        Array(Set(points.map { $0.timeToExpiration })).sorted()
    }

    /// 找指定 (strike, T) 最贴近的点（用于查询）
    public func nearest(strike: Double, time: Double) -> VolatilityPoint? {
        guard !points.isEmpty else { return nil }
        return points.min { a, b in
            let da = abs(a.strikePrice - strike) + abs(a.timeToExpiration - time) * 100
            let db = abs(b.strikePrice - strike) + abs(b.timeToExpiration - time) * 100
            return da < db
        }
    }
}

// MARK: - Builder · 从期权链 + 市价表构建曲面

public enum VolatilitySurfaceBuilder {

    /// 从期权链 + 市价映射构建波动率曲面
    /// - Parameters:
    ///   - chain: 期权链（OptionChainBuilder.build 输出）
    ///   - prices: 市价映射 [合约 ID: 市价] · 缺数据的合约跳过
    ///   - spotPrice: 标的现价
    ///   - riskFreeRate: 无风险利率
    ///   - dividendYield: 分红率（默认 0）
    ///   - referenceDate: 计算 T 的基准日（默认今天）
    /// - Returns: 波动率曲面 · 仅含成功反推 IV 的格点
    public static func build(
        chain: OptionChain,
        prices: [String: Double],
        spotPrice: Double,
        riskFreeRate: Double,
        dividendYield: Double = 0,
        referenceDate: Date = Date()
    ) -> VolatilitySurface {
        var points: [VolatilityPoint] = []
        for slice in chain.slices {
            // 单 slice 的距到期年数（自然日 / 365）
            let days = slice.daysToExpiration(from: referenceDate)
            guard days > 0 else { continue }
            let T = Double(days) / 365.0

            for row in slice.rows {
                // 优先用 CALL 推 IV · 没有再用 PUT
                if let call = row.call, let price = prices[call.id] {
                    if let iv = solveIV(type: .call, price: price,
                                        K: call.strikePrice, T: T,
                                        S: spotPrice, r: riskFreeRate, q: dividendYield) {
                        points.append(VolatilityPoint(
                            strikePrice: NSDecimalNumber(decimal: call.strikePrice).doubleValue,
                            timeToExpiration: T,
                            impliedVolatility: iv,
                            optionType: .call,
                            marketPrice: price
                        ))
                    }
                } else if let put = row.put, let price = prices[put.id] {
                    if let iv = solveIV(type: .put, price: price,
                                        K: put.strikePrice, T: T,
                                        S: spotPrice, r: riskFreeRate, q: dividendYield) {
                        points.append(VolatilityPoint(
                            strikePrice: NSDecimalNumber(decimal: put.strikePrice).doubleValue,
                            timeToExpiration: T,
                            impliedVolatility: iv,
                            optionType: .put,
                            marketPrice: price
                        ))
                    }
                }
            }
        }
        return VolatilitySurface(
            underlyingID: chain.underlyingID,
            underlyingName: chain.underlyingName,
            spotPrice: spotPrice,
            riskFreeRate: riskFreeRate,
            dividendYield: dividendYield,
            points: points
        )
    }

    private static func solveIV(
        type: OptionType, price: Double, K: Decimal, T: Double,
        S: Double, r: Double, q: Double
    ) -> Double? {
        let inputs = BlackScholes.Inputs(
            spotPrice: S, strikePrice: NSDecimalNumber(decimal: K).doubleValue,
            timeToExpirationYears: T, riskFreeRate: r,
            volatility: 0.30, dividendYield: q  // volatility 字段在 IV.compute 内被重置
        )
        return ImpliedVolatility.compute(type: type, marketPrice: price, inputs: inputs)
    }
}
