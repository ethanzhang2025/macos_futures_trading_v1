// 期权回测引擎（v15.33 · 期权 Phase 6.3 · WP-期权 回测层）
//
// 设计：
//   - 输入：OptionStrategy（在 t0 构造好的策略） + 时序样本 [date, spotPrice, IV]
//   - 算法：每个时点用 BS 重定价所有 leg · 加 underlying MTM · 出 PnL 曲线
//   - 输出：PnL 曲线 + totalPnL + maxDD + sharpe + winRate + bestDay/worstDay
//
// 边界：
//   - leg PnL 公式：direction.sign × (currentBSPrice - entryPremium) × quantity
//   - underlying PnL 公式：positionSize × (spotPrice_t - underlyingEntryPrice)
//   - 到期当天后样本：T → 0 · BS 退化到内在价值（与 leg.payoffAtExpiration 对齐）
//
// 假设：
//   - 每个样本都假定有效 IV（user 提供时序 · 不做 IV 反推）
//   - r/q 全程恒定（v1 · v2 可改时变）
//   - 不考虑滚动开仓 / 调仓 / 手续费 · 单一策略静态持有

import Foundation

/// 单时点样本（市场数据快照）
public struct OptionBacktestSample: Sendable, Equatable {
    public let date: Date
    public let spotPrice: Double
    public let impliedVolatility: Double    // 该时点的 IV（用户提供 · 不做反推）

    public init(date: Date, spotPrice: Double, impliedVolatility: Double) {
        self.date = date
        self.spotPrice = spotPrice
        self.impliedVolatility = impliedVolatility
    }
}

/// 单时点 PnL 分解（option MTM + underlying MTM = total）
public struct OptionBacktestPnL: Sendable, Equatable {
    public let date: Date
    public let spotPrice: Double
    public let optionMTM: Double          // 全部 option leg 的 MTM PnL
    public let underlyingMTM: Double      // 标的现货 MTM PnL
    public let totalPnL: Double           // = optionMTM + underlyingMTM

    public init(date: Date, spotPrice: Double, optionMTM: Double, underlyingMTM: Double) {
        self.date = date
        self.spotPrice = spotPrice
        self.optionMTM = optionMTM
        self.underlyingMTM = underlyingMTM
        self.totalPnL = optionMTM + underlyingMTM
    }
}

/// 回测结果（曲线 + 关键统计指标）
public struct OptionBacktestResult: Sendable, Equatable {
    public let curve: [OptionBacktestPnL]
    /// 末日 totalPnL（持有到结束的最终损益）
    public let endingPnL: Double
    /// 最大回撤（绝对值 · peak 到 trough · 不带负号）
    public let maxDrawdown: Double
    /// 年化 Sharpe（基于日 PnL 差分 · 假定 252 交易日）
    public let sharpeRatio: Double
    /// 胜率（totalPnL > 0 的样本占比）
    public let winRate: Double
    /// 最佳/最差日（按 totalPnL）
    public let bestDay: OptionBacktestPnL?
    public let worstDay: OptionBacktestPnL?
    /// 回测期间最高浮盈
    public let peakPnL: Double
    /// 回测期间最低浮亏
    public let troughPnL: Double
}

public enum OptionBacktester {

    /// 运行静态持有回测
    /// - Parameters:
    ///   - strategy: 在第一个样本时点构造的 OptionStrategy
    ///   - samples: 按时间升序的市场样本（建议日频 · 不做强校验）
    ///   - riskFreeRate: 无风险利率（年化 · 全程恒定）
    ///   - dividendYield: 股息率（年化 · 全程恒定）
    public static func run(
        strategy: OptionStrategy,
        samples: [OptionBacktestSample],
        riskFreeRate: Double = 0.03,
        dividendYield: Double = 0
    ) -> OptionBacktestResult {
        guard !samples.isEmpty else {
            return OptionBacktestResult(
                curve: [], endingPnL: 0, maxDrawdown: 0, sharpeRatio: 0,
                winRate: 0, bestDay: nil, worstDay: nil,
                peakPnL: 0, troughPnL: 0
            )
        }

        var curve: [OptionBacktestPnL] = []
        curve.reserveCapacity(samples.count)
        for sample in samples {
            let optionMTM = strategy.legs.reduce(0.0) { acc, leg in
                acc + legMTM(leg: leg, sample: sample,
                             riskFreeRate: riskFreeRate, dividendYield: dividendYield)
            }
            let underlyingMTM = Double(strategy.underlyingPositionSize)
                * (sample.spotPrice - strategy.underlyingEntryPrice)
            curve.append(OptionBacktestPnL(
                date: sample.date,
                spotPrice: sample.spotPrice,
                optionMTM: optionMTM,
                underlyingMTM: underlyingMTM
            ))
        }

        let pnls = curve.map { $0.totalPnL }
        let endingPnL = pnls.last ?? 0
        let maxDD = computeMaxDrawdown(pnls)
        let sharpe = computeSharpe(pnls)
        let wins = curve.filter { $0.totalPnL > 0 }.count
        let winRate = Double(wins) / Double(curve.count)
        let best = curve.max(by: { $0.totalPnL < $1.totalPnL })
        let worst = curve.min(by: { $0.totalPnL < $1.totalPnL })

        return OptionBacktestResult(
            curve: curve,
            endingPnL: endingPnL,
            maxDrawdown: maxDD,
            sharpeRatio: sharpe,
            winRate: winRate,
            bestDay: best,
            worstDay: worst,
            peakPnL: pnls.max() ?? 0,
            troughPnL: pnls.min() ?? 0
        )
    }

    // MARK: - 内部辅助

    /// 单 leg 在某时点的 MTM PnL（用 BS 重定价 · 与到期 payoff 自然衔接 · T→0 BS 退化为内在值）
    private static func legMTM(
        leg: OptionStrategyLeg,
        sample: OptionBacktestSample,
        riskFreeRate: Double,
        dividendYield: Double
    ) -> Double {
        let strike = NSDecimalNumber(decimal: leg.contract.strikePrice).doubleValue
        let daysToExp = daysBetween(from: sample.date, to: leg.contract.expirationDate)
        let T = max(Double(daysToExp) / 365.0, 1e-6)

        let inputs = BlackScholes.Inputs(
            spotPrice: sample.spotPrice,
            strikePrice: strike,
            timeToExpirationYears: T,
            riskFreeRate: riskFreeRate,
            volatility: sample.impliedVolatility,
            dividendYield: dividendYield
        )
        let currentPrice = BlackScholes.price(type: leg.contract.type, inputs: inputs)
        // long: gain when currentPrice > entryPremium · sign=+1
        // short: gain when currentPrice < entryPremium · sign=-1
        return leg.direction.sign * (currentPrice - leg.entryPremium) * Double(leg.quantity)
    }

    /// 最大回撤（绝对值 · peak 减 trough）
    /// 算法：单遍扫描 · 维护 running peak · 当前点距 peak 的差就是回撤候选
    private static func computeMaxDrawdown(_ pnls: [Double]) -> Double {
        guard !pnls.isEmpty else { return 0 }
        var peak = pnls[0]
        var maxDD: Double = 0
        for v in pnls {
            if v > peak { peak = v }
            let dd = peak - v
            if dd > maxDD { maxDD = dd }
        }
        return maxDD
    }

    /// 年化 Sharpe（日 PnL 差分 · 252 交易日年化）
    /// 注意：此处用绝对 PnL 差分（非收益率）· 适合 PnL 维度比较 · 不依赖初始本金
    private static func computeSharpe(_ pnls: [Double]) -> Double {
        guard pnls.count >= 2 else { return 0 }
        var diffs: [Double] = []
        diffs.reserveCapacity(pnls.count - 1)
        for i in 1..<pnls.count {
            diffs.append(pnls[i] - pnls[i - 1])
        }
        let n = Double(diffs.count)
        let mean = diffs.reduce(0, +) / n
        let variance = diffs.map { pow($0 - mean, 2) }.reduce(0, +) / n
        let std = sqrt(variance)
        guard std > 1e-9 else { return 0 }
        return mean / std * sqrt(252.0)
    }

    /// 整数自然日差（与 OptionContract.daysToExpiration 同口径）
    private static func daysBetween(from a: Date, to b: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: a),
                                       to: cal.startOfDay(for: b))
        return comps.day ?? 0
    }
}
