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

/// 持仓方向（v17.47 D2 v2.3）· 老代码默认 .long 保持兼容
public enum TradeDirection: String, Sendable, Equatable, Codable {
    case long
    case short
}

/// 单笔交易记录
public struct BacktestTrade: Sendable, Equatable {
    public let entryBarIndex: Int
    public let entryPrice: Decimal
    public let exitBarIndex: Int
    public let exitPrice: Decimal
    public let direction: TradeDirection

    /// PnL（按方向算）· long: exit - entry · short: entry - exit
    public var pnl: Decimal {
        switch direction {
        case .long:  return exitPrice - entryPrice
        case .short: return entryPrice - exitPrice
        }
    }
    public var pnlPercent: Decimal {
        guard entryPrice > 0 else { return 0 }
        return pnl / entryPrice
    }
    public var isWin: Bool { pnl > 0 }

    public init(entryBarIndex: Int, entryPrice: Decimal,
                exitBarIndex: Int, exitPrice: Decimal,
                direction: TradeDirection = .long) {
        self.entryBarIndex = entryBarIndex
        self.entryPrice = entryPrice
        self.exitBarIndex = exitBarIndex
        self.exitPrice = exitPrice
        self.direction = direction
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
    /// v17.45 D2 v2 · Sortino 比率（mean / 下行偏差 · 仅算负收益的 std · ≥ 0 时返 0）
    public let sortino: Double
    /// v17.45 D2 v2 · Calmar 比率（endingPnL / maxDrawdown · maxDD = 0 时返 0 避 NaN）
    public let calmar: Double
    /// 胜率（盈利 trade / 总 trade · 无 trade → 0）
    public let winRate: Double
    /// 期望值（平均每 trade PnL · 无 trade → 0）
    public let expectancy: Decimal
    public let initialEquity: Decimal

    public init(trades: [BacktestTrade], equityCurve: [Decimal],
                endingPnL: Decimal, maxDrawdown: Decimal,
                sharpe: Double, sortino: Double = 0, calmar: Double = 0,
                winRate: Double, expectancy: Decimal,
                initialEquity: Decimal) {
        self.trades = trades
        self.equityCurve = equityCurve
        self.endingPnL = endingPnL
        self.maxDrawdown = maxDrawdown
        self.sharpe = sharpe
        self.sortino = sortino
        self.calmar = calmar
        self.winRate = winRate
        self.expectancy = expectancy
        self.initialEquity = initialEquity
    }
}

public enum SimpleBacktestEngine {

    /// 持仓状态（v17.47 D2 v2.3 · long-only → both long & short）
    private enum Position {
        case none
        case long(entryPrice: Decimal, entryIndex: Int)
        case short(entryPrice: Decimal, entryIndex: Int)
    }

    /// 跑回测
    /// - Parameters:
    ///   - formula: 已 parsed Formula
    ///   - bars: 输入 K 线
    ///   - signalLineName: 取哪条输出线作为信号（默认 "BUY"）· 大小写敏感
    ///   - initialEquity: 起始权益（默认 100000）
    ///   - commission: v17.46 D2 v2.2 · 每笔双向手续费（绝对额 · 开+平各扣一次 · 默认 0 同 v1）
    ///   - slippage: v17.46 D2 v2.2 · 滑点（绝对额 · 开仓 +slippage 买高 · 平仓 -slippage 卖低 · 默认 0）
    ///   - allowShort: v17.47 D2 v2.3 · 信号 < 0 时做空（默认 false 兼容 v1 long-only）
    /// - Returns: BacktestResult · 解释器报错 → 抛 Error
    public static func run(
        formula: Formula,
        bars: [BarData],
        signalLineName: String = "BUY",
        initialEquity: Decimal = 100_000,
        commission: Decimal = 0,
        slippage: Decimal = 0,
        allowShort: Bool = false
    ) throws -> BacktestResult {
        guard !bars.isEmpty else {
            return empty(initialEquity: initialEquity)
        }
        let interpreter = Interpreter()
        let lines = try interpreter.execute(formula: formula, bars: bars)
        guard let signal = lines.first(where: { $0.name == signalLineName }) else {
            throw InterpreterError(message: "回测：找不到信号输出 \(signalLineName)")
        }
        return runWithSignal(signal: signal.values, bars: bars,
                             initialEquity: initialEquity,
                             commission: commission, slippage: slippage,
                             allowShort: allowShort)
    }

    /// 直接基于已计算的信号 series 跑（测试 / 不走 Formula 解释器路径）
    public static func runWithSignal(
        signal: [Decimal?],
        bars: [BarData],
        initialEquity: Decimal = 100_000,
        commission: Decimal = 0,
        slippage: Decimal = 0,
        allowShort: Bool = false
    ) -> BacktestResult {
        guard !bars.isEmpty else { return empty(initialEquity: initialEquity) }
        var trades: [BacktestTrade] = []
        var equityCurve: [Decimal] = []
        equityCurve.reserveCapacity(bars.count)

        var position: Position = .none
        var realizedPnL: Decimal = 0

        // 信号符号 → 目标方向（none/long/short · 不开仓时 .none）
        func targetDirection(at i: Int) -> TradeDirection? {
            let v = (i < signal.count ? signal[i] : nil) ?? 0
            if v > 0 { return .long }
            if v < 0, allowShort { return .short }
            return nil
        }

        // 平仓 helper（含 slippage + commission · 更新 realizedPnL · 返回 trade）
        func close(position p: Position, at i: Int, barClose: Decimal) -> BacktestTrade? {
            switch p {
            case .none: return nil
            case .long(let entryPrice, let entryIndex):
                let exitPrice = barClose - slippage
                let t = BacktestTrade(entryBarIndex: entryIndex, entryPrice: entryPrice,
                                       exitBarIndex: i, exitPrice: exitPrice, direction: .long)
                trades.append(t)
                realizedPnL += t.pnl - commission
                return t
            case .short(let entryPrice, let entryIndex):
                let exitPrice = barClose + slippage   // 空头买回 · 不利方向是高价
                let t = BacktestTrade(entryBarIndex: entryIndex, entryPrice: entryPrice,
                                       exitBarIndex: i, exitPrice: exitPrice, direction: .short)
                trades.append(t)
                realizedPnL += t.pnl - commission
                return t
            }
        }

        for i in 0..<bars.count {
            let barClose = bars[i].close
            let target = targetDirection(at: i)

            switch (position, target) {
            case (.none, .some(.long)):
                position = .long(entryPrice: barClose + slippage, entryIndex: i)
            case (.none, .some(.short)):
                position = .short(entryPrice: barClose - slippage, entryIndex: i)   // 空头卖出 · 不利是低价
            case (.long, .none), (.short, .none):
                _ = close(position: position, at: i, barClose: barClose)
                position = .none
            case (.long, .some(.short)):
                // 反手：平多 + 开空（trader 反向信号自动反手）
                _ = close(position: position, at: i, barClose: barClose)
                position = .short(entryPrice: barClose - slippage, entryIndex: i)
            case (.short, .some(.long)):
                _ = close(position: position, at: i, barClose: barClose)
                position = .long(entryPrice: barClose + slippage, entryIndex: i)
            case (.none, .none), (.long, .some(.long)), (.short, .some(.short)):
                break   // 保持现状
            }

            // unrealized = 当前持仓的纸面 PnL（按方向算）
            let unrealized: Decimal = {
                switch position {
                case .none: return 0
                case .long(let entryPrice, _):  return barClose - entryPrice
                case .short(let entryPrice, _): return entryPrice - barClose
                }
            }()
            equityCurve.append(initialEquity + realizedPnL + unrealized)
        }

        // 末尾强平
        if case .none = position {} else if let last = bars.last {
            _ = close(position: position, at: bars.count - 1, barClose: last.close)
        }
        let endingPnL = realizedPnL
        let metrics = computeMetrics(equityCurve: equityCurve, trades: trades, initialEquity: initialEquity)
        return BacktestResult(
            trades: trades,
            equityCurve: equityCurve,
            endingPnL: endingPnL,
            maxDrawdown: metrics.maxDD,
            sharpe: metrics.sharpe,
            sortino: metrics.sortino,
            calmar: metrics.calmar,
            winRate: metrics.winRate,
            expectancy: metrics.expectancy,
            initialEquity: initialEquity
        )
    }

    // MARK: - 私有：指标计算

    private struct Metrics {
        let maxDD: Decimal
        let sharpe: Double
        let sortino: Double
        let calmar: Double
        let winRate: Double
        let expectancy: Decimal
    }

    private static func computeMetrics(equityCurve: [Decimal], trades: [BacktestTrade], initialEquity: Decimal) -> Metrics {
        let maxDD = maxDrawdown(equityCurve: equityCurve)
        let returns = barReturns(equityCurve: equityCurve)
        let sharpe = sharpeRatio(returns: returns)
        let sortino = sortinoRatio(returns: returns)
        let endingPnL = (equityCurve.last ?? initialEquity) - initialEquity
        let calmar = calmarRatio(endingPnL: endingPnL, maxDD: maxDD)
        let wins = trades.filter { $0.isWin }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count)
        let totalPnL = trades.reduce(Decimal(0)) { $0 + $1.pnl }
        let expectancy = trades.isEmpty ? Decimal(0) : totalPnL / Decimal(trades.count)
        return Metrics(maxDD: maxDD, sharpe: sharpe, sortino: sortino,
                       calmar: calmar, winRate: winRate, expectancy: expectancy)
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

    /// 每 bar 增量收益序列（equity[i] - equity[i-1]）· 用 Double 避免 Decimal 算 std 复杂
    /// equity 长度 < 2 → 空数组（调用方自处理）
    private static func barReturns(equityCurve: [Decimal]) -> [Double] {
        guard equityCurve.count >= 2 else { return [] }
        return (1..<equityCurve.count).map { i in
            NSDecimalNumber(decimal: equityCurve[i] - equityCurve[i - 1]).doubleValue
        }
    }

    /// Sharpe = mean / std · 无风险利率假定 0 · 不年化 · std=0 返 0 避 NaN
    private static func sharpeRatio(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0 }
        let n = Double(returns.count)
        let mean = returns.reduce(0, +) / n
        let variance = returns.reduce(0) { acc, r in acc + (r - mean) * (r - mean) } / n
        let std = variance.squareRoot()
        guard std > 1e-12 else { return 0 }
        return mean / std
    }

    /// v17.45 D2 v2 · Sortino = mean / 下行偏差（仅算负 returns 的 std）· 下行 std=0 返 0 避 NaN
    /// 与 Sharpe 区别：分母仅惩罚负向波动（trader 更在意亏损起伏 · 上行波动不算"风险"）
    private static func sortinoRatio(returns: [Double]) -> Double {
        guard !returns.isEmpty else { return 0 }
        let n = Double(returns.count)
        let mean = returns.reduce(0, +) / n
        let downside = returns.filter { $0 < 0 }
        guard !downside.isEmpty else { return 0 }
        let dN = Double(downside.count)
        let downVariance = downside.reduce(0) { acc, r in acc + r * r } / dN
        let downStd = downVariance.squareRoot()
        guard downStd > 1e-12 else { return 0 }
        return mean / downStd
    }

    /// v17.45 D2 v2 · Calmar = endingPnL / maxDrawdown · maxDD=0 返 0 避 NaN
    /// 与 Sharpe/Sortino 区别：分母是最大回撤（极端尾部风险）· trader 看"赚多少 vs 最差几把"
    private static func calmarRatio(endingPnL: Decimal, maxDD: Decimal) -> Double {
        let pnlD = (endingPnL as NSDecimalNumber).doubleValue
        let ddD = (maxDD as NSDecimalNumber).doubleValue
        guard ddD > 1e-12 else { return 0 }
        return pnlD / ddD
    }

    private static func empty(initialEquity: Decimal) -> BacktestResult {
        BacktestResult(trades: [], equityCurve: [],
                        endingPnL: 0, maxDrawdown: 0,
                        sharpe: 0, sortino: 0, calmar: 0,
                        winRate: 0, expectancy: 0,
                        initialEquity: initialEquity)
    }
}
