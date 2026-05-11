// v17.37 D1/D2 · 公式回测引擎 v1（FormulaEngine + 简单 long-only 撮合）
//
// 设计取舍：
// - v1 long-only · single position · close 价撮合（保守 · 不偷看 high/low）
// - 信号语义：formula 输出 line 中目标值 > 0 → 持仓 · ≤ 0 / nil → 空仓
// - 上根空仓 + 本根信号 > 0 → 开仓（本根 close 撮合）
// - 上根持仓 + 本根信号 ≤ 0 → 平仓（本根 close 撮合）
// - 每根 bar 用 close 重估 equity（MTM）
// - 不接 ReplayDriver（v2 · 真行情联动留 Stage B）· 直接基于 [BarData]
//
// 输出指标（v1 · 经典 6 项）：
// - endingPnL · maxDrawdown · sharpe · winRate · expectancy · trade count

import Foundation

/// 单笔交易记录
public struct BacktestTrade: Sendable, Equatable {
    public let entryBarIndex: Int
    public let entryPrice: Decimal
    public let exitBarIndex: Int
    public let exitPrice: Decimal
    public var pnl: Decimal { exitPrice - entryPrice }
    public var pnlPercent: Decimal {
        guard entryPrice > 0 else { return 0 }
        return (exitPrice - entryPrice) / entryPrice
    }
    public var isWin: Bool { exitPrice > entryPrice }

    public init(entryBarIndex: Int, entryPrice: Decimal, exitBarIndex: Int, exitPrice: Decimal) {
        self.entryBarIndex = entryBarIndex
        self.entryPrice = entryPrice
        self.exitBarIndex = exitBarIndex
        self.exitPrice = exitPrice
    }
}

/// 回测结果汇总
public struct BacktestResult: Sendable, Equatable {
    public let trades: [BacktestTrade]
    /// equity 曲线 · count == bars.count · index i = 第 i 根 bar 收盘后的累计权益
    public let equityCurve: [Decimal]
    /// 最终 PnL（绝对值 · 单位与 bars 价格一致）
    public let endingPnL: Decimal
    /// 最大回撤（绝对值 · ≥ 0 · 权益曲线峰谷差）
    public let maxDrawdown: Decimal
    /// 夏普比率（按 bar 收益序列 · 无风险利率假定为 0 · 不年化 · 简单版）
    public let sharpe: Double
    /// 胜率（盈利 trade / 总 trade · 无 trade → 0）
    public let winRate: Double
    /// 期望值（平均每 trade PnL · 无 trade → 0）
    public let expectancy: Decimal
    public let initialEquity: Decimal

    public init(trades: [BacktestTrade], equityCurve: [Decimal],
                endingPnL: Decimal, maxDrawdown: Decimal,
                sharpe: Double, winRate: Double, expectancy: Decimal,
                initialEquity: Decimal) {
        self.trades = trades
        self.equityCurve = equityCurve
        self.endingPnL = endingPnL
        self.maxDrawdown = maxDrawdown
        self.sharpe = sharpe
        self.winRate = winRate
        self.expectancy = expectancy
        self.initialEquity = initialEquity
    }
}

public enum SimpleBacktestEngine {

    /// 跑回测
    /// - Parameters:
    ///   - formula: 已 parsed Formula
    ///   - bars: 输入 K 线
    ///   - signalLineName: 取哪条输出线作为信号（默认 "BUY"）· 大小写敏感
    ///   - initialEquity: 起始权益（默认 100000）
    /// - Returns: BacktestResult · 解释器报错 → 抛 Error
    public static func run(
        formula: Formula,
        bars: [BarData],
        signalLineName: String = "BUY",
        initialEquity: Decimal = 100_000
    ) throws -> BacktestResult {
        guard !bars.isEmpty else {
            return empty(initialEquity: initialEquity)
        }
        let interpreter = Interpreter()
        let lines = try interpreter.execute(formula: formula, bars: bars)
        guard let signal = lines.first(where: { $0.name == signalLineName }) else {
            throw InterpreterError(message: "回测：找不到信号输出 \(signalLineName)")
        }
        return runWithSignal(signal: signal.values, bars: bars, initialEquity: initialEquity)
    }

    /// 直接基于已计算的信号 series 跑（测试 / 不走 Formula 解释器路径）
    public static func runWithSignal(
        signal: [Decimal?],
        bars: [BarData],
        initialEquity: Decimal = 100_000
    ) -> BacktestResult {
        guard !bars.isEmpty else { return empty(initialEquity: initialEquity) }
        var trades: [BacktestTrade] = []
        var equityCurve: [Decimal] = []
        equityCurve.reserveCapacity(bars.count)

        var inPosition = false
        var entryPrice: Decimal = 0
        var entryIndex = 0
        var realizedPnL: Decimal = 0   // 已平仓累计

        for i in 0..<bars.count {
            let close = bars[i].close
            // 当前 bar 信号（上根末态决定本根行为 · 实际本根 close 撮合 · 简化无 slippage）
            let curSignal = i < signal.count ? signal[i] : nil
            let isLong = (curSignal ?? 0) > 0

            if !inPosition && isLong {
                // 开仓 · 本根 close 价
                inPosition = true
                entryPrice = close
                entryIndex = i
            } else if inPosition && !isLong {
                // 平仓 · 本根 close 价
                let trade = BacktestTrade(
                    entryBarIndex: entryIndex,
                    entryPrice: entryPrice,
                    exitBarIndex: i,
                    exitPrice: close
                )
                trades.append(trade)
                realizedPnL += trade.pnl
                inPosition = false
            }

            // 当前 equity = 起始 + 已实现 PnL + 未实现 PnL（持仓时）
            let unrealized: Decimal = inPosition ? (close - entryPrice) : 0
            equityCurve.append(initialEquity + realizedPnL + unrealized)
        }

        // 末尾仍持仓 · 强制按末 bar close 平仓（v1 简化 · 不留尾仓）
        if inPosition, let last = bars.last {
            let trade = BacktestTrade(
                entryBarIndex: entryIndex,
                entryPrice: entryPrice,
                exitBarIndex: bars.count - 1,
                exitPrice: last.close
            )
            trades.append(trade)
            realizedPnL += trade.pnl
        }
        let endingPnL = realizedPnL
        let metrics = computeMetrics(equityCurve: equityCurve, trades: trades, initialEquity: initialEquity)
        return BacktestResult(
            trades: trades,
            equityCurve: equityCurve,
            endingPnL: endingPnL,
            maxDrawdown: metrics.maxDD,
            sharpe: metrics.sharpe,
            winRate: metrics.winRate,
            expectancy: metrics.expectancy,
            initialEquity: initialEquity
        )
    }

    // MARK: - 私有：指标计算

    private struct Metrics {
        let maxDD: Decimal
        let sharpe: Double
        let winRate: Double
        let expectancy: Decimal
    }

    private static func computeMetrics(equityCurve: [Decimal], trades: [BacktestTrade], initialEquity: Decimal) -> Metrics {
        let maxDD = maxDrawdown(equityCurve: equityCurve)
        let sharpe = barReturnsSharpe(equityCurve: equityCurve)
        let wins = trades.filter { $0.isWin }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count)
        let totalPnL = trades.reduce(Decimal(0)) { $0 + $1.pnl }
        let expectancy = trades.isEmpty ? Decimal(0) : totalPnL / Decimal(trades.count)
        return Metrics(maxDD: maxDD, sharpe: sharpe, winRate: winRate, expectancy: expectancy)
    }

    /// 最大回撤 = max(peak - current) · 不归一化
    private static func maxDrawdown(equityCurve: [Decimal]) -> Decimal {
        var peak: Decimal = equityCurve.first ?? 0
        var maxDD: Decimal = 0
        for v in equityCurve {
            if v > peak { peak = v }
            let dd = peak - v
            if dd > maxDD { maxDD = dd }
        }
        return maxDD
    }

    /// Sharpe（v1 简化）：每 bar 增量收益序列 · mean/std · 不年化 · 收益 = equity[i] - equity[i-1]
    /// 标准差为 0 → 返回 0（避免 NaN）
    private static func barReturnsSharpe(equityCurve: [Decimal]) -> Double {
        guard equityCurve.count >= 2 else { return 0 }
        let returns: [Double] = (1..<equityCurve.count).map { i in
            NSDecimalNumber(decimal: equityCurve[i] - equityCurve[i - 1]).doubleValue
        }
        let n = Double(returns.count)
        let mean = returns.reduce(0, +) / n
        let variance = returns.reduce(0) { acc, r in acc + (r - mean) * (r - mean) } / n
        let std = variance.squareRoot()
        guard std > 1e-12 else { return 0 }
        return mean / std
    }

    private static func empty(initialEquity: Decimal) -> BacktestResult {
        BacktestResult(trades: [], equityCurve: [],
                        endingPnL: 0, maxDrawdown: 0,
                        sharpe: 0, winRate: 0, expectancy: 0,
                        initialEquity: initialEquity)
    }
}
