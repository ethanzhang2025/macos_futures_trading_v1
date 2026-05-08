// 套利策略回测引擎（v15.37 · 套利分析 V2）
//
// 输入：
//   - SpreadValue 时序
//   - 信号序列（SpreadSignalGenerator 输出 · 严格 entry/exit 成对）
// 输出：
//   - SpreadTrade[] · 单笔交易记录
//   - SpreadBacktestSummary · 总结指标（胜率/平均收益/maxDD/平均持仓周期）
//
// PnL 计算：
//   - 做多价差：pnl = exitValue - entryValue（价差走高 = 赚）
//   - 做空价差：pnl = entryValue - exitValue（价差走低 = 赚）
//   - 不含交易成本（v2 简化 · v3 加 commission）
//
// 假设：
//   - 单边持仓 · 不重叠 · 信号已严格 entry/exit 成对（generator 保证）
//   - 1 单位仓位 / 不滚动 / 不杠杆 · PnL 量纲 = 价差量纲

import Foundation

public struct SpreadTrade: Sendable, Equatable {
    public let entryIndex: Int
    public let exitIndex: Int
    public let entryTime: Date
    public let exitTime: Date
    public let side: SpreadSignal.Side
    public let entryValue: Decimal
    public let exitValue: Decimal
    public let pnl: Decimal             // 单笔 PnL（按仓位 1 单位）
    public let holdingBars: Int         // 持仓周期（exit - entry）

    public init(entryIndex: Int, exitIndex: Int, entryTime: Date, exitTime: Date,
                side: SpreadSignal.Side, entryValue: Decimal, exitValue: Decimal,
                pnl: Decimal, holdingBars: Int) {
        self.entryIndex = entryIndex
        self.exitIndex = exitIndex
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.side = side
        self.entryValue = entryValue
        self.exitValue = exitValue
        self.pnl = pnl
        self.holdingBars = holdingBars
    }

    /// 是否盈利
    public var isWin: Bool { pnl > 0 }
}

public struct SpreadBacktestSummary: Sendable, Equatable {
    public let totalTrades: Int
    public let wins: Int
    public let losses: Int
    public let winRate: Double             // wins / totalTrades · [0, 1]
    public let totalPnL: Decimal
    public let avgPnL: Decimal             // totalPnL / totalTrades
    public let maxWinPnL: Decimal          // 最赚一笔
    public let maxLossPnL: Decimal         // 最亏一笔（带负号）
    public let avgHoldingBars: Double      // 平均持仓周期
    public let maxDrawdown: Decimal        // 累积 PnL 最大回撤（绝对值）
    public let cumulativePnL: [Decimal]    // 按交易顺序累积 PnL（曲线 · 长度 = totalTrades + 1 · [0] = 0）

    public static let empty = SpreadBacktestSummary(
        totalTrades: 0, wins: 0, losses: 0, winRate: 0,
        totalPnL: 0, avgPnL: 0, maxWinPnL: 0, maxLossPnL: 0,
        avgHoldingBars: 0, maxDrawdown: 0, cumulativePnL: [0]
    )
}

public enum SpreadBacktester {

    /// 把信号序列转 trade · 计算 summary
    public static func run(signals: [SpreadSignal]) -> (trades: [SpreadTrade], summary: SpreadBacktestSummary) {
        // 信号按 (entry, exit) 成对配对（generator 保证顺序 + 单边）
        var trades: [SpreadTrade] = []
        var pendingEntry: SpreadSignal? = nil

        for sig in signals {
            switch sig.action {
            case .entry:
                pendingEntry = sig
            case .exit:
                guard let entry = pendingEntry, entry.side == sig.side else {
                    pendingEntry = nil
                    continue
                }
                let pnl: Decimal
                switch sig.side {
                case .long:  pnl = sig.value - entry.value      // 做多 · 价差涨赚
                case .short: pnl = entry.value - sig.value      // 做空 · 价差跌赚
                }
                trades.append(SpreadTrade(
                    entryIndex: entry.index, exitIndex: sig.index,
                    entryTime: entry.openTime, exitTime: sig.openTime,
                    side: entry.side,
                    entryValue: entry.value, exitValue: sig.value,
                    pnl: pnl, holdingBars: sig.index - entry.index
                ))
                pendingEntry = nil
            }
        }

        let summary = computeSummary(trades: trades)
        return (trades, summary)
    }

    // MARK: - 内部统计

    private static func computeSummary(trades: [SpreadTrade]) -> SpreadBacktestSummary {
        guard !trades.isEmpty else { return .empty }
        let n = trades.count
        var totalPnL = Decimal(0)
        var wins = 0
        var maxWin = trades.first!.pnl
        var maxLoss = trades.first!.pnl
        var totalHolding = 0
        var cumulative: [Decimal] = [0]
        cumulative.reserveCapacity(n + 1)

        for t in trades {
            totalPnL += t.pnl
            if t.isWin { wins += 1 }
            if t.pnl > maxWin { maxWin = t.pnl }
            if t.pnl < maxLoss { maxLoss = t.pnl }
            totalHolding += t.holdingBars
            cumulative.append(totalPnL)
        }

        // maxDD：累积 PnL 最大回撤（peak 减 trough）
        var peak = cumulative[0]
        var maxDD = Decimal(0)
        for v in cumulative {
            if v > peak { peak = v }
            let dd = peak - v
            if dd > maxDD { maxDD = dd }
        }

        return SpreadBacktestSummary(
            totalTrades: n,
            wins: wins,
            losses: n - wins,
            winRate: Double(wins) / Double(n),
            totalPnL: totalPnL,
            avgPnL: totalPnL / Decimal(n),
            maxWinPnL: maxWin,
            maxLossPnL: maxLoss,
            avgHoldingBars: Double(totalHolding) / Double(n),
            maxDrawdown: maxDD,
            cumulativePnL: cumulative
        )
    }
}
