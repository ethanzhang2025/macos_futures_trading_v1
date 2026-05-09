// 皮尔逊相关系数（v15.48 · WP-行情 关联性矩阵）
//
// Pearson correlation：r = Σ((x-x̄)(y-ȳ)) / √(Σ(x-x̄)² · Σ(y-ȳ)²)
//
// 输入：两组等长时序（return / price 或归一化变化率）
// 输出：r ∈ [-1, +1] · +1 完美正相关 · -1 完美负相关 · 0 无关
//
// 用法：
//   - trader 选跨品种套利对（高正相关品种价差稳定 · 适合 mean-reverting）
//   - trader 找对冲品种（高负相关 · 反向头寸自然对冲）
//   - 板块内一致性（同板块预期高相关 · 异常低相关 = 异动品种）

import Foundation

public enum CorrelationCalculator {

    /// 皮尔逊相关系数（return-based · 自动转 log return）
    /// - Parameter prices1/prices2: 等长价格时序（≥ 2 点）
    /// - Returns: r ∈ [-1, +1] · 长度不一致或 < 2 点返 0
    public static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let n = Double(x.count)
        let xMean = x.reduce(0, +) / n
        let yMean = y.reduce(0, +) / n
        var num: Double = 0
        var denomX: Double = 0
        var denomY: Double = 0
        for i in 0..<x.count {
            let dx = x[i] - xMean
            let dy = y[i] - yMean
            num += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }
        let denom = sqrt(denomX * denomY)
        guard denom > 1e-12 else { return 0 }    // 防除零（常数序列）
        return num / denom
    }

    /// 价格序列 → log return 序列（log(p[i] / p[i-1]) · 长度 -1）
    /// trader 看相关性常用 return 而非价格本身（避免趋势污染）
    public static func logReturns(_ prices: [Double]) -> [Double] {
        guard prices.count >= 2 else { return [] }
        var rets: [Double] = []
        rets.reserveCapacity(prices.count - 1)
        for i in 1..<prices.count {
            let p0 = prices[i - 1]
            let p1 = prices[i]
            guard p0 > 0, p1 > 0 else { rets.append(0); continue }
            rets.append(log(p1 / p0))
        }
        return rets
    }

    /// 价格相关性（基于 log return · 主流方法）
    public static func priceCorrelation(_ prices1: [Double], _ prices2: [Double]) -> Double {
        let r1 = logReturns(prices1)
        let r2 = logReturns(prices2)
        return pearson(r1, r2)
    }
}

// MARK: - N×N 矩阵（多品种两两相关性）

public struct CorrelationMatrix: Sendable, Equatable {
    public let instrumentIDs: [String]                    // 行/列顺序
    public let values: [[Double]]                         // values[i][j] = corr(i, j)

    /// values[i][j] · 越界返 0
    public func value(row i: Int, col j: Int) -> Double {
        guard values.indices.contains(i), values[i].indices.contains(j) else { return 0 }
        return values[i][j]
    }

    public init(instrumentIDs: [String], values: [[Double]]) {
        self.instrumentIDs = instrumentIDs
        self.values = values
    }
}

public enum CorrelationMatrixCalculator {

    /// 多组时序两两计算相关系数（[id: prices] 输入 · 对称矩阵 · 对角线 = 1）
    public static func compute(seriesByID: [String: [Double]], orderedIDs: [String]? = nil) -> CorrelationMatrix {
        let ids = orderedIDs ?? seriesByID.keys.sorted()
        let n = ids.count
        var matrix: [[Double]] = Array(repeating: Array(repeating: 0, count: n), count: n)
        // 对称 · 只算 i <= j 然后 mirror
        for i in 0..<n {
            for j in i..<n {
                if i == j {
                    matrix[i][j] = 1
                } else {
                    let r = CorrelationCalculator.priceCorrelation(
                        seriesByID[ids[i]] ?? [],
                        seriesByID[ids[j]] ?? []
                    )
                    matrix[i][j] = r
                    matrix[j][i] = r
                }
            }
        }
        return CorrelationMatrix(instrumentIDs: ids, values: matrix)
    }
}
