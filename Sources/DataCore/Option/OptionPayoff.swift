// 期权策略 PnL 分析（v15.31 · 期权 Phase 4 · WP-期权 策略层）
//
// 输入：OptionStrategy
// 输出：到期 PnL 曲线 + 关键指标（maxProfit / maxLoss / breakeven 数组）
//
// 算法：
//   - PnL 曲线：在 [spotMin, spotMax] 范围按 step 采样 · 默认 200 点
//   - maxProfit / maxLoss：在所有 strike 点 + 边界点上评估 PnL · 取 max/min
//     （理由：分段线性函数 · 极值必出现在 strike 转折点）
//   - breakeven：相邻 strike 间用线性插值找零点 · 多个 zero crossing 全列出

import Foundation

/// PnL 曲线单点
public struct PayoffPoint: Sendable, Equatable {
    public let spotPrice: Double
    public let pnl: Double
}

/// PnL 分析结果
public struct PayoffAnalysis: Sendable, Equatable {
    public let curve: [PayoffPoint]          // PnL 曲线（采样点）
    public let maxProfit: Double             // 最大潜在利润（+∞ 用 .infinity 表示）
    public let maxLoss: Double               // 最大潜在亏损（绝对值 · 不带负号）
    public let breakevens: [Double]          // 损益平衡点（PnL=0 的 spot 价 · 升序）
    public let isMaxProfitUnlimited: Bool    // 是否无限利润（如 long call）
    public let isMaxLossUnlimited: Bool      // 是否无限亏损（如 naked short call）
}

public enum OptionPayoffAnalyzer {

    /// 分析策略到期 PnL
    /// - Parameters:
    ///   - strategy: 期权策略组合
    ///   - spotMin / spotMax: PnL 曲线采样范围（默认基于 strike 自动）
    ///   - sampleCount: 采样点数（默认 200）
    /// - Returns: PnL 曲线 + 关键指标
    public static func analyze(
        strategy: OptionStrategy,
        spotMin: Double? = nil, spotMax: Double? = nil,
        sampleCount: Int = 200
    ) -> PayoffAnalysis {
        let strikes = strategy.distinctStrikes
        guard !strikes.isEmpty else {
            return PayoffAnalysis(curve: [], maxProfit: 0, maxLoss: 0,
                                  breakevens: [], isMaxProfitUnlimited: false,
                                  isMaxLossUnlimited: false)
        }
        // 采样范围：默认 [minStrike·0.7, maxStrike·1.3]
        let lo = spotMin ?? max(0.01, strikes.first! * 0.7)
        let hi = spotMax ?? strikes.last! * 1.3

        let step = (hi - lo) / Double(sampleCount - 1)
        var curve: [PayoffPoint] = []
        curve.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let s = lo + Double(i) * step
            curve.append(PayoffPoint(spotPrice: s, pnl: strategy.payoffAtExpiration(spotPrice: s)))
        }

        // 极值 + breakeven 在 strike 关键点上评估（分段线性）
        var keyPoints: [Double] = strikes
        keyPoints.append(lo)
        keyPoints.append(hi)
        // 加一些 strike 间中点和外推点作为 sanity（防止极端策略落在区间外）
        if let minStrike = strikes.first {
            keyPoints.append(minStrike * 0.5)
            keyPoints.append(minStrike * 0.1)
        }
        if let maxStrike = strikes.last {
            keyPoints.append(maxStrike * 1.5)
            keyPoints.append(maxStrike * 3)
        }
        keyPoints.sort()

        let pnls = keyPoints.map { strategy.payoffAtExpiration(spotPrice: $0) }
        let maxProfit = pnls.max() ?? 0
        let maxLossSigned = pnls.min() ?? 0

        // 判断利润/亏损是否无限：看 PnL 在远端的趋势
        let leftEdge = strategy.payoffAtExpiration(spotPrice: 0.01)
        let rightEdge = strategy.payoffAtExpiration(spotPrice: max(strikes.last! * 100, 1e6))
        // 如果右端 > 中段 max → 无限利润；左端 < 中段 min → 无限亏损
        let midRangeMax = pnls.max() ?? 0
        let midRangeMin = pnls.min() ?? 0
        let isMaxProfitUnlimited = rightEdge > midRangeMax + 0.01 || leftEdge > midRangeMax + 0.01
        let isMaxLossUnlimited = rightEdge < midRangeMin - 0.01 || leftEdge < midRangeMin - 0.01

        // 损益平衡点：相邻 strike 间符号变化 → 线性插值
        let breakevens = findBreakevens(strategy: strategy, strikes: strikes,
                                         spotMin: lo, spotMax: hi)

        return PayoffAnalysis(
            curve: curve,
            maxProfit: maxProfit,
            maxLoss: abs(maxLossSigned),
            breakevens: breakevens,
            isMaxProfitUnlimited: isMaxProfitUnlimited,
            isMaxLossUnlimited: isMaxLossUnlimited
        )
    }

    /// 查找 PnL 曲线零点（损益平衡点）
    /// 算法：在 [lo, strikes..., hi] 各分段上检测符号变化 + 二分细化
    private static func findBreakevens(
        strategy: OptionStrategy, strikes: [Double],
        spotMin: Double, spotMax: Double
    ) -> [Double] {
        var anchors = [spotMin] + strikes + [spotMax]
        anchors.sort()
        var result: [Double] = []
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i]
            let b = anchors[i + 1]
            let pa = strategy.payoffAtExpiration(spotPrice: a)
            let pb = strategy.payoffAtExpiration(spotPrice: b)
            if abs(pa) < 1e-6 { result.append(a); continue }
            if pa * pb < 0 {
                // 二分（PnL 在 [a, b] 内分段线性 · 50 次足够 1e-12 精度）
                var lo = a
                var hi = b
                var loV = pa
                for _ in 0..<50 {
                    let mid = (lo + hi) / 2
                    let pm = strategy.payoffAtExpiration(spotPrice: mid)
                    if abs(pm) < 1e-6 || (hi - lo) < 1e-6 {
                        result.append(mid); break
                    }
                    if loV * pm < 0 {
                        hi = mid
                    } else {
                        lo = mid; loV = pm
                    }
                }
            }
        }
        // 末点单独检查
        let pLast = strategy.payoffAtExpiration(spotPrice: spotMax)
        if abs(pLast) < 1e-6 { result.append(spotMax) }
        // 去重（线性扫描 · 容差 1e-3）
        var deduped: [Double] = []
        for v in result.sorted() {
            if let last = deduped.last, abs(v - last) < 1e-3 { continue }
            deduped.append(v)
        }
        return deduped
    }
}
