// v17.39 D5 · 公式回测月度 markdown annex（跨平台 · Linux 可测）
//
// 用途：
// - ReviewWindow exportMonthlyReport 月底导出时拼到训练 annex 之后
// - 与 TrainingMarkdownReport.generateMonthlyAnnex 对位 · 风格保持一致
//
// 输入：BacktestHistoryLog + 区间 [start, end)
// 输出：markdown 文本段（空区间 → 仍输出标题 + "无回测记录"提示）

import Foundation

public enum BacktestMarkdownReport {

    /// 月度 annex（与训练 annex 同模式）· 时区由调用方决定 [start, end)
    /// - Parameters:
    ///   - log: 历史集合
    ///   - start: 起始（含）
    ///   - end: 结束（不含）
    ///   - rowLimit: 表格最多行数（默认 20）
    public static func generateMonthlyAnnex(
        _ log: BacktestHistoryLog,
        start: Date,
        end: Date,
        rowLimit: Int = 20
    ) -> String {
        let entries = log.entries(in: start..<end)
        var md = ""
        md += "\n## 公式回测（v17.39 D5）\n\n"

        guard !entries.isEmpty else {
            md += "_本月无保存的回测记录_\n"
            return md
        }

        // 概览
        let count = entries.count
        let pnls = entries.map { ($0.endingPnL as NSDecimalNumber).doubleValue }
        let avgPnL = pnls.reduce(0, +) / Double(count)
        let bestPnL = pnls.max() ?? 0
        let worstPnL = pnls.min() ?? 0
        let avgSharpe = entries.map { $0.sharpe }.reduce(0, +) / Double(count)
        let avgSortino = entries.map { $0.sortino }.reduce(0, +) / Double(count)
        let avgCalmar = entries.map { $0.calmar }.reduce(0, +) / Double(count)
        let avgWinRate = entries.map { $0.winRate }.reduce(0, +) / Double(count)

        md += "- 区间内保存次数：**\(count)**\n"
        md += "- 平均 endingPnL：**\(String(format: "%+.2f", avgPnL))**（最佳 \(String(format: "%+.2f", bestPnL)) · 最差 \(String(format: "%+.2f", worstPnL))）\n"
        md += "- 平均 Sharpe：**\(String(format: "%.2f", avgSharpe))** · Sortino：**\(String(format: "%.2f", avgSortino))** · Calmar：**\(String(format: "%.2f", avgCalmar))** · 胜率：**\(String(format: "%.0f%%", avgWinRate * 100))**\n\n"

        // 明细表（按时间倒序 · 截 rowLimit）
        md += "### 明细（最近 \(min(rowLimit, count)) 条）\n\n"
        md += "| 时间 | 信号 | 标的 | bars | trades | endingPnL | maxDD | Sharpe | Sortino | Calmar | 胜率 | 期望/笔 |\n"
        md += "|------|------|------|------|--------|-----------|-------|--------|---------|--------|------|---------|\n"
        for e in entries.prefix(rowLimit) {
            let pnl = (e.endingPnL as NSDecimalNumber).doubleValue
            let dd = (e.maxDrawdown as NSDecimalNumber).doubleValue
            let exp = (e.expectancy as NSDecimalNumber).doubleValue
            md += "| \(BacktestHistoryEntry.dateLabel(e.createdAt))"
            md += " | \(e.signalLineName)"
            md += " | \(trajectoryDisplay(e.trajectoryRaw))"
            md += " | \(e.barCount)"
            md += " | \(e.tradeCount)"
            md += " | \(String(format: "%+.2f", pnl))"
            md += " | \(String(format: "%.2f", dd))"
            md += " | \(String(format: "%.2f", e.sharpe))"
            md += " | \(String(format: "%.2f", e.sortino))"
            md += " | \(String(format: "%.2f", e.calmar))"
            md += " | \(String(format: "%.0f%%", e.winRate * 100))"
            md += " | \(String(format: "%+.2f", exp)) |\n"
        }
        if count > rowLimit {
            md += "\n_…还有 \(count - rowLimit) 条未显示_\n"
        }
        return md
    }

    private static func trajectoryDisplay(_ raw: String) -> String {
        switch raw {
        case "random":   return "随机游走"
        case "up":       return "上涨趋势"
        case "down":     return "下跌趋势"
        case "sideways": return "横盘震荡"
        default:         return raw
        }
    }
}
