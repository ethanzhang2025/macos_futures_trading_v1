// 价差统计指标（v15.27 · WP-套利分析 V1）
//
// 套利交易者必看：
//   - mean / stdDev：基线 + 波动率
//   - current：当前价差值
//   - zScore：偏离均值多少个标准差（|z|>2 = 极值 · 套利入场信号）
//   - percentile：当前在历史分位数（0~1 · 0.5=中位）
//   - min / max / range：历史极值
//   - upperBand / lowerBand：±2σ 通道（趋势回归区间）
//
// 输入：[SpreadValue]（SpreadCalculator 输出）
// 输出：SpreadStatistics 聚合结果

import Foundation

public struct SpreadStatistics: Sendable, Equatable {
    public let count: Int                  // 样本数
    public let current: Decimal            // 当前价差（最后一根）
    public let mean: Decimal               // 均值
    public let stdDev: Decimal             // 标准差
    public let zScore: Decimal             // 当前 Z-score = (current - mean) / stdDev
    public let percentile: Double          // 当前在历史分位数 [0, 1]（0=最低，1=最高）
    public let min: Decimal                // 历史最低
    public let max: Decimal                // 历史最高
    public let range: Decimal              // max - min
    public let upperBand2σ: Decimal        // mean + 2σ（套利做空入场区）
    public let lowerBand2σ: Decimal        // mean - 2σ（套利做多入场区）

    public static let empty = SpreadStatistics(
        count: 0, current: 0, mean: 0, stdDev: 0, zScore: 0, percentile: 0,
        min: 0, max: 0, range: 0, upperBand2σ: 0, lowerBand2σ: 0
    )
}

public enum SpreadStatisticsCalculator {

    /// 输入价差时序 → 聚合统计指标
    /// 空 / 单点 → 返 .empty 不抛
    public static func compute(_ values: [SpreadValue]) -> SpreadStatistics {
        guard !values.isEmpty else { return .empty }
        let n = values.count
        let series = values.map { $0.value }

        let current = series.last ?? 0
        let sum = series.reduce(Decimal(0), +)
        let mean = sum / Decimal(n)

        // 标准差（样本 · n-1）· n=1 时退化为 0
        let stdDev: Decimal
        if n > 1 {
            let variance = series.reduce(Decimal(0)) { acc, v in
                let diff = v - mean
                return acc + diff * diff
            } / Decimal(n - 1)
            stdDev = sqrtDecimal(variance)
        } else {
            stdDev = 0
        }

        let zScore: Decimal = (stdDev > 0) ? (current - mean) / stdDev : 0

        // 排序（局部副本 · 原序列保持时序）
        let sorted = series.sorted()
        let minV = sorted.first ?? 0
        let maxV = sorted.last ?? 0
        let range = maxV - minV

        // 当前分位数（小于等于 current 的占比 · 末位排名 / n）
        let belowEqualCount = sorted.filter { $0 <= current }.count
        let percentile = Double(belowEqualCount) / Double(n)

        let upper = mean + 2 * stdDev
        let lower = mean - 2 * stdDev

        return SpreadStatistics(
            count: n,
            current: current,
            mean: mean,
            stdDev: stdDev,
            zScore: zScore,
            percentile: percentile,
            min: minV,
            max: maxV,
            range: range,
            upperBand2σ: upper,
            lowerBand2σ: lower
        )
    }

    // 牛顿迭代 sqrt（Decimal · 10 次足够 6 位精度）
    private static func sqrtDecimal(_ value: Decimal) -> Decimal {
        guard value > 0 else { return 0 }
        let dval = NSDecimalNumber(decimal: value).doubleValue
        return Decimal(dval.squareRoot())
    }
}
