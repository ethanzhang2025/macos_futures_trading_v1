// v17.83 D4 v3 · 多品种 / 多周期组合回测引擎
//
// 设计意图：
// - trader 实战痛点：单一品种单一周期跑出"赚"的策略可能是过拟合
// - 真信号应在 ≥3 品种 × ≥3 周期组合矩阵上都鲁棒（不要求每个 cell 都赚 · 但 positive cells % 应 ≥ 60%）
// - 提供"矩阵热图 + 鲁棒性汇总"两层结果
//
// 输入：公式 + N 个 (symbol, periodLabel, bars) cell · cell 间互独立
// 输出：每个 cell BacktestResult + RobustnessReport（跨 cell 平均 + 命中率）
//
// 实现：
// - 复用 SimpleBacktestEngine.run · 单 cell 失败（解释器错 / bars 不足）静默跳过
// - 不并行（v1 顺序跑 · cell 数 < 50 时性能足够 · 并行留 v2）

import Foundation

/// 单个回测 cell（一个品种 + 一个周期）
public struct BacktestCell: Sendable {
    public let symbol: String       // 如 "rb2510"
    public let periodLabel: String  // 如 "5m" · "1H"
    public let bars: [BarData]

    public init(symbol: String, periodLabel: String, bars: [BarData]) {
        self.symbol = symbol
        self.periodLabel = periodLabel
        self.bars = bars
    }
}

/// 单 cell 的回测结果（含元数据）
public struct BacktestCellOutcome: Sendable {
    public let symbol: String
    public let periodLabel: String
    public let result: BacktestResult

    public init(symbol: String, periodLabel: String, result: BacktestResult) {
        self.symbol = symbol
        self.periodLabel = periodLabel
        self.result = result
    }
}

/// 鲁棒性汇总（跨 cell 平均 + 命中率 · trader 看"真信号还是过拟合"）
public struct RobustnessReport: Sendable {
    /// 实际成功跑通的 cell 数（≤ 输入 cell 数 · 解释器失败/bars 不足 cell 不计）
    public let cellCount: Int
    /// PnL > 0 的 cell 数
    public let positiveCellCount: Int
    /// positive / total 比率（[0, 1]）· trader 阈值参考：≥ 0.6 = 鲁棒
    public let positiveRate: Double
    /// 跨 cell 平均 endingPnL（按 Double 平均 · 各 cell PnL 量纲一致才有意义）
    public let avgEndingPnL: Double
    /// 跨 cell 平均 Sharpe
    public let avgSharpe: Double
    /// 跨 cell 平均胜率
    public let avgWinRate: Double
    /// 总 trade 数（跨 cell 累加）
    public let totalTradeCount: Int
    /// 最佳 cell（endingPnL desc 第一 · 空时 nil）
    public let bestCell: BacktestCellOutcome?
    /// 最差 cell（endingPnL asc 第一 · 空时 nil）
    public let worstCell: BacktestCellOutcome?

    public init(cellCount: Int, positiveCellCount: Int, positiveRate: Double,
                avgEndingPnL: Double, avgSharpe: Double, avgWinRate: Double,
                totalTradeCount: Int,
                bestCell: BacktestCellOutcome?, worstCell: BacktestCellOutcome?) {
        self.cellCount = cellCount
        self.positiveCellCount = positiveCellCount
        self.positiveRate = positiveRate
        self.avgEndingPnL = avgEndingPnL
        self.avgSharpe = avgSharpe
        self.avgWinRate = avgWinRate
        self.totalTradeCount = totalTradeCount
        self.bestCell = bestCell
        self.worstCell = worstCell
    }
}

/// 多品种多周期组合回测总结果
public struct MultiAssetBacktestResult: Sendable {
    public let outcomes: [BacktestCellOutcome]
    public let robustness: RobustnessReport
    /// 输入 cell 数（含失败 · 与 outcomes.count 之差 = 失败 cell 数）
    public let inputCellCount: Int

    public var failedCellCount: Int { inputCellCount - outcomes.count }

    public init(outcomes: [BacktestCellOutcome], robustness: RobustnessReport, inputCellCount: Int) {
        self.outcomes = outcomes
        self.robustness = robustness
        self.inputCellCount = inputCellCount
    }
}

public enum MultiAssetMultiPeriodBacktest {

    /// 跑组合回测
    /// - Parameters:
    ///   - formula: 已 parsed Formula（同一公式应用到所有 cell · 验证策略跨标的/周期鲁棒性）
    ///   - cells: cell 列表（symbol × period 的笛卡尔积或手动选）
    ///   - signalLineName: 信号 line 名（默认 "BUY"）
    ///   - initialEquity: 起始权益（每 cell 独立 · 默认 100k）
    ///   - commission / slippage / allowShort: 同 SimpleBacktestEngine
    /// - Returns: 各 cell outcomes（按 endingPnL desc）+ 鲁棒性报告
    public static func run(
        formula: Formula,
        cells: [BacktestCell],
        signalLineName: String = "BUY",
        initialEquity: Decimal = 100_000,
        commission: Decimal = 0,
        slippage: Decimal = 0,
        allowShort: Bool = false
    ) -> MultiAssetBacktestResult {
        var outcomes: [BacktestCellOutcome] = []
        outcomes.reserveCapacity(cells.count)
        for cell in cells {
            guard !cell.bars.isEmpty else { continue }
            do {
                let result = try SimpleBacktestEngine.run(
                    formula: formula,
                    bars: cell.bars,
                    signalLineName: signalLineName,
                    initialEquity: initialEquity,
                    commission: commission,
                    slippage: slippage,
                    allowShort: allowShort
                )
                outcomes.append(BacktestCellOutcome(
                    symbol: cell.symbol,
                    periodLabel: cell.periodLabel,
                    result: result
                ))
            } catch {
                continue   // 单 cell 失败不阻塞其他 cell
            }
        }
        outcomes.sort {
            ($0.result.endingPnL as NSDecimalNumber).doubleValue
                > ($1.result.endingPnL as NSDecimalNumber).doubleValue
        }
        let robustness = summarize(outcomes: outcomes)
        return MultiAssetBacktestResult(
            outcomes: outcomes,
            robustness: robustness,
            inputCellCount: cells.count
        )
    }

    /// 鲁棒性汇总（跨 cell 平均 + 命中率 + best/worst）
    static func summarize(outcomes: [BacktestCellOutcome]) -> RobustnessReport {
        let n = outcomes.count
        guard n > 0 else {
            return RobustnessReport(
                cellCount: 0, positiveCellCount: 0, positiveRate: 0,
                avgEndingPnL: 0, avgSharpe: 0, avgWinRate: 0,
                totalTradeCount: 0,
                bestCell: nil, worstCell: nil
            )
        }
        let pnls = outcomes.map { ($0.result.endingPnL as NSDecimalNumber).doubleValue }
        let positives = pnls.filter { $0 > 0 }.count
        let avgPnL = pnls.reduce(0, +) / Double(n)
        let avgSharpe = outcomes.map(\.result.sharpe).reduce(0, +) / Double(n)
        let avgWinRate = outcomes.map(\.result.winRate).reduce(0, +) / Double(n)
        let totalTrades = outcomes.reduce(0) { $0 + $1.result.trades.count }
        // outcomes 已按 endingPnL desc 排序 → first = best · last = worst
        let best = outcomes.first
        let worst = outcomes.last
        return RobustnessReport(
            cellCount: n,
            positiveCellCount: positives,
            positiveRate: Double(positives) / Double(n),
            avgEndingPnL: avgPnL,
            avgSharpe: avgSharpe,
            avgWinRate: avgWinRate,
            totalTradeCount: totalTrades,
            bestCell: best,
            worstCell: worst
        )
    }
}
