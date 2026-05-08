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

    // MARK: - V2 滚动 Z-score（v15.37 · 套利分析 V2）

    /// 滚动 Z-score 时序 · 每个点的 Z 用过去 window 根（含自身）的 mean/σ
    /// - Parameters:
    ///   - values: 价差时序
    ///   - window: 滚动窗口长度（典型 60-120 · 默认 60 = 1h@1m / 1d@15m）
    /// - Returns: [Double] 长度 = values.count · 不足 window 时 = 0（无意义点）
    public static func rollingZScores(_ values: [SpreadValue], window: Int = 60) -> [Double] {
        guard window >= 2, !values.isEmpty else { return Array(repeating: 0, count: values.count) }
        let series = values.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        var zs: [Double] = Array(repeating: 0, count: values.count)
        for i in 0..<values.count {
            guard i >= window - 1 else { continue }
            let lo = i - window + 1
            let slice = series[lo...i]
            let mean = slice.reduce(0, +) / Double(window)
            let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window - 1)
            let std = variance > 0 ? sqrt(variance) : 0
            zs[i] = std > 1e-9 ? (series[i] - mean) / std : 0
        }
        return zs
    }
}

// MARK: - V2 直方图（v15.37）

public struct SpreadHistogram: Sendable, Equatable {
    public let bins: [Bin]                 // bin 数组 · 升序
    public let binWidth: Double            // 单 bin 宽度
    public let totalCount: Int             // 样本总数
    public let modeBinIndex: Int           // 出现次数最多的 bin index
    public let currentBinIndex: Int        // 当前价差所在 bin（HUD 用 · -1 = 当前不在范围）

    public struct Bin: Sendable, Equatable {
        public let lowerBound: Double      // 桶左边界（含）
        public let upperBound: Double      // 桶右边界（不含 · 末桶含）
        public let count: Int              // 落入此桶的样本数
        public let frequency: Double       // count / totalCount
    }

    public static let empty = SpreadHistogram(
        bins: [], binWidth: 0, totalCount: 0,
        modeBinIndex: -1, currentBinIndex: -1
    )
}

public enum SpreadHistogramCalculator {

    /// 价差值直方图 · 等宽分桶 · 拟合正态分布参考（mean/σ 已知）
    /// - Parameters:
    ///   - values: 价差时序
    ///   - binCount: 桶数（默认 30 · trader 视觉舒适密度）
    ///   - currentValue: 当前价差（标记 currentBinIndex 用 · 默认末值）
    public static func compute(
        _ values: [SpreadValue], binCount: Int = 30, currentValue: Decimal? = nil
    ) -> SpreadHistogram {
        guard values.count >= 2, binCount >= 2 else { return .empty }
        let series = values.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        guard let lo = series.min(), let hi = series.max(), hi > lo else { return .empty }
        let pad = (hi - lo) * 0.02
        let viewLo = lo - pad
        let viewHi = hi + pad
        let width = (viewHi - viewLo) / Double(binCount)
        guard width > 1e-12 else { return .empty }

        // 分桶计数
        var counts = Array(repeating: 0, count: binCount)
        for v in series {
            let raw = (v - viewLo) / width
            let idx = min(binCount - 1, max(0, Int(raw)))
            counts[idx] += 1
        }
        let total = series.count

        // 找众数 bin
        var modeIdx = 0
        var maxC = counts.first ?? 0
        for (i, c) in counts.enumerated() where c > maxC {
            modeIdx = i
            maxC = c
        }

        // 当前 bin
        let curV = currentValue.map { NSDecimalNumber(decimal: $0).doubleValue } ?? series.last!
        let curIdx: Int
        if curV < viewLo || curV > viewHi {
            curIdx = -1
        } else {
            let raw = (curV - viewLo) / width
            curIdx = min(binCount - 1, max(0, Int(raw)))
        }

        // Bin 数组
        var bins: [SpreadHistogram.Bin] = []
        bins.reserveCapacity(binCount)
        for i in 0..<binCount {
            let lower = viewLo + Double(i) * width
            let upper = lower + width
            bins.append(SpreadHistogram.Bin(
                lowerBound: lower, upperBound: upper,
                count: counts[i],
                frequency: Double(counts[i]) / Double(total)
            ))
        }

        return SpreadHistogram(
            bins: bins, binWidth: width, totalCount: total,
            modeBinIndex: modeIdx, currentBinIndex: curIdx
        )
    }
}
