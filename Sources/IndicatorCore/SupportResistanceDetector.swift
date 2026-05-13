// v17.166 · 支撑阻力自动识别（trader 不用手画 · 基于 ZigZag pivot 聚类 · 高频价格区强度自动凸显）
//
// 算法栈：
// 1. ZigZag 摆动检测 → 全图 pivot 列表（high/low 不区分 · 都是有意义的反转点）
// 2. 价格聚类：按 clusterTolerance(默认 0.5%) 把相邻 pivot 价格归到同一 "level"
//    用区间平均价代表 level · 用聚类成员数 = strength
// 3. 取强度前 N（默认 8）个 level · 按价格升序输出
// 4. 当前价 vs level 判 isResistance（level > current → 阻力 · level < current → 支撑）
//
// 不做（v2/v3）：
// - 加入 Pivot Point R3/S3 / Volume Profile POC（多源聚类需更复杂权重）
// - 时间衰减（最近 pivot 权重更高 · v2）
// - 突破后转换（阻力突破成支撑 · v2）

import Foundation
import Shared

/// 支撑阻力 level
public struct SupportResistanceLevel: Sendable, Equatable {
    public let price: Decimal
    /// 聚类成员数 · 越大说明该价位被多次回踩 · 越强
    public let touchCount: Int
    /// 强度 0..1（touchCount 相对最高 touchCount 的归一化值）
    public let strength: Double
    /// 是支撑（level < currentPrice）还是阻力（level > currentPrice）
    public let isResistance: Bool

    public init(price: Decimal, touchCount: Int, strength: Double, isResistance: Bool) {
        self.price = price
        self.touchCount = touchCount
        self.strength = strength
        self.isResistance = isResistance
    }
}

public struct SupportResistanceParams: Sendable, Equatable {
    /// ZigZag 摆动阈值百分比（默认 2 · 比 PatternDetector 更敏感 · 捕更多反转点）
    public var zigzagPercent: Decimal
    /// 价格聚类容忍 0.005 = 0.5% · 价差占 base 比例 ≤ tolerance 归同 level
    public var clusterTolerance: Double
    /// 输出 level 上限（按 touchCount 降序取前 N）
    public var maxLevels: Int

    public init(
        zigzagPercent: Decimal = 2,
        clusterTolerance: Double = 0.005,
        maxLevels: Int = 8
    ) {
        self.zigzagPercent = zigzagPercent
        self.clusterTolerance = clusterTolerance
        self.maxLevels = maxLevels
    }

    public static let `default` = SupportResistanceParams()
}

public enum SupportResistanceDetector {

    /// 检测 K 线序列的支撑阻力 level
    /// - Returns: 按价格升序排列的 levels · 含 isResistance/strength
    public static func detect(kline: KLineSeries, params: SupportResistanceParams = .default) throws -> [SupportResistanceLevel] {
        guard kline.count > 0 else { return [] }
        let zigzag = try ZigZag.calculate(kline: kline, params: [params.zigzagPercent])[0].values
        let pivots = zigzag.compactMap { $0 }  // 只保留非 nil 价格
        guard !pivots.isEmpty else { return [] }

        // 聚类：把价差 ≤ tolerance 的 pivot 归同一 cluster
        // 算法：先排序价格 · 然后用 1D 区间扫描合并（gap > tolerance 即新 cluster）
        let sortedPrices = pivots.sorted()
        var clusters: [[Decimal]] = []
        var currentCluster: [Decimal] = []
        for p in sortedPrices {
            if currentCluster.isEmpty {
                currentCluster.append(p)
                continue
            }
            // 用 cluster 平均价作 base 算距离 · 避免 cluster 漂移
            let avg = average(currentCluster)
            let pD = doubleValue(p)
            let avgD = doubleValue(avg)
            let diff = abs(pD - avgD) / avgD
            if diff <= params.clusterTolerance {
                currentCluster.append(p)
            } else {
                clusters.append(currentCluster)
                currentCluster = [p]
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        // 转 level · touchCount = cluster 大小 · 单 pivot cluster 也算
        // 优化：单 pivot 的 cluster touchCount = 1 · 价值不大 · 过滤掉
        let validClusters = clusters.filter { $0.count >= 2 }
        guard !validClusters.isEmpty else { return [] }

        let maxTouch = validClusters.map(\.count).max() ?? 1
        let currentPrice = kline.closes.last ?? 0

        var levels: [SupportResistanceLevel] = validClusters.map { cluster in
            let avg = average(cluster)
            let strength = Double(cluster.count) / Double(maxTouch)
            let isResistance = avg > currentPrice
            return SupportResistanceLevel(
                price: avg,
                touchCount: cluster.count,
                strength: strength,
                isResistance: isResistance
            )
        }

        // 按 touchCount 降序取前 N · 再按价格升序输出
        levels.sort { $0.touchCount > $1.touchCount }
        let topN = Array(levels.prefix(params.maxLevels))
        return topN.sorted { $0.price < $1.price }
    }

    // MARK: - helpers

    private static func average(_ prices: [Decimal]) -> Decimal {
        guard !prices.isEmpty else { return 0 }
        let sum = prices.reduce(Decimal(0), +)
        return Kernels.round8(sum / Decimal(prices.count))
    }

    private static func doubleValue(_ d: Decimal) -> Double {
        NSDecimalNumber(decimal: d).doubleValue
    }
}
