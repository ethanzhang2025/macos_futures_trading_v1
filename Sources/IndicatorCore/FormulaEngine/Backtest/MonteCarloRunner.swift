// v17.51 D2 v2.4 · Monte Carlo 鲁棒性测试
//
// 用途：
// - trader 跑同一公式 N 次（不同 seed → 不同 mock 轨迹）
// - 看 PnL 分布（avg ± std · p5/median/p95）+ profitable 占比
// - 判断"是真的稳定策略 · 还是单次 lucky"
//
// 设计：
// - bars 由调用方按 seed 生成（barsForSeed closure · 解耦 mock 模型）
// - 单 seed 编译/运行失败 → 跳过（不阻塞其他 seed · 与 GridSearch 同模式）
// - 统计基于 endingPnL（Decimal → Double 一次 · 分布算法用 Double）

import Foundation

/// Monte Carlo 跑批结果（runs + 统计 · trader 一眼判稳定性）
public struct MonteCarloResult: Sendable {
    public let runs: [BacktestResult]
    public let avgPnL: Double           // 平均 endingPnL
    public let stdPnL: Double           // 标准差（衡量"不同 seed 间稳定性"）
    public let minPnL: Double
    public let maxPnL: Double
    public let medianPnL: Double        // p50
    public let p5PnL: Double            // 5% 分位（最差 5%）
    public let p95PnL: Double           // 95% 分位（最好 5%）
    public let profitableRatio: Double  // endingPnL > 0 的 run 占比

    public init(runs: [BacktestResult], avgPnL: Double, stdPnL: Double,
                minPnL: Double, maxPnL: Double, medianPnL: Double,
                p5PnL: Double, p95PnL: Double, profitableRatio: Double) {
        self.runs = runs
        self.avgPnL = avgPnL
        self.stdPnL = stdPnL
        self.minPnL = minPnL
        self.maxPnL = maxPnL
        self.medianPnL = medianPnL
        self.p5PnL = p5PnL
        self.p95PnL = p95PnL
        self.profitableRatio = profitableRatio
    }
}

public enum MonteCarloRunner {

    /// 跑 Monte Carlo · 不同 seed × 同公式
    /// - Parameters:
    ///   - formula: 已 parsed Formula
    ///   - seeds: 种子列表（与 bars 一一对应）
    ///   - barsForSeed: 按 seed 生成 K 线的 closure（调用方提供 mock 模型 · 测试可注入 deterministic generator）
    ///   - signalLineName / initialEquity / commission / slippage / allowShort: 同 SimpleBacktestEngine.run
    /// - Returns: MonteCarloResult · seeds 空 → empty 结果
    public static func run(
        formula: Formula,
        seeds: [Int],
        barsForSeed: (Int) -> [BarData],
        signalLineName: String = "BUY",
        initialEquity: Decimal = 100_000,
        commission: Decimal = 0,
        slippage: Decimal = 0,
        allowShort: Bool = false
    ) -> MonteCarloResult {
        var runs: [BacktestResult] = []
        runs.reserveCapacity(seeds.count)
        for seed in seeds {
            let bars = barsForSeed(seed)
            if bars.isEmpty { continue }
            do {
                let r = try SimpleBacktestEngine.run(
                    formula: formula, bars: bars,
                    signalLineName: signalLineName,
                    initialEquity: initialEquity,
                    commission: commission, slippage: slippage,
                    allowShort: allowShort
                )
                runs.append(r)
            } catch {
                continue   // 单 seed 失败不阻塞
            }
        }
        return makeResult(runs: runs)
    }

    /// 基于已跑完的 runs 算统计（测试可直接喂 results · 跳过 SimpleBacktestEngine）
    public static func makeResult(runs: [BacktestResult]) -> MonteCarloResult {
        guard !runs.isEmpty else {
            return MonteCarloResult(runs: [], avgPnL: 0, stdPnL: 0,
                                     minPnL: 0, maxPnL: 0, medianPnL: 0,
                                     p5PnL: 0, p95PnL: 0, profitableRatio: 0)
        }
        let pnls: [Double] = runs.map { ($0.endingPnL as NSDecimalNumber).doubleValue }
        let sorted = pnls.sorted()
        let n = Double(pnls.count)
        let avg = pnls.reduce(0, +) / n
        let variance = pnls.reduce(0) { acc, p in acc + (p - avg) * (p - avg) } / n
        let std = variance.squareRoot()
        let profitable = pnls.filter { $0 > 0 }.count
        return MonteCarloResult(
            runs: runs,
            avgPnL: avg, stdPnL: std,
            minPnL: sorted.first ?? 0, maxPnL: sorted.last ?? 0,
            medianPnL: percentile(sorted, 0.50),
            p5PnL: percentile(sorted, 0.05),
            p95PnL: percentile(sorted, 0.95),
            profitableRatio: Double(profitable) / n
        )
    }

    /// 分位数（线性插值 · 与 numpy.percentile linear 默认行为对位）
    /// pct ∈ [0, 1] · sorted 必须已排序
    private static func percentile(_ sorted: [Double], _ pct: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let rank = pct * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = rank - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }
}
