// WP-50/53 v15.19 batch24 · 月度复盘 Markdown 报告生成（trader 月底一键生成可分享报告）
//
// 设计取舍：
// - 纯函数 · 输入 [ClosedPosition] + 月份 · 输出 Markdown String · 调用方负责写文件
// - 章节固定（概览 / 风险 / 盈利 / 连胜连败 / 心理标签 / 品种分布 / 时段分析）
// - 复用 ReviewAnalytics 全套指标（streak / risk / profit / instrument / session）+ EmotionAutoTagger
// - Asia/Shanghai 月份切片 · 与 trader 实际生活时区对齐

import Foundation
import Shared

public enum MonthlyReportGenerator {

    /// 生成指定月份的复盘 Markdown
    /// - Parameters:
    ///   - positions: 全量闭合持仓 · 内部按 closeTime 切片
    ///   - year: 公历年份（如 2026）
    ///   - month: 公历月（1-12）
    ///   - now: 报告生成时间（默认 Date()）
    ///   - timeZone: 月份切片时区（默认 Asia/Shanghai）
    public static func generate(
        positions: [ClosedPosition],
        year: Int,
        month: Int,
        now: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        // 月份起止
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let monthStart = cal.date(from: comps) ?? now
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now

        let title = "\(year) 年 \(month) 月复盘报告"
        return generateInRange(
            positions: positions, start: monthStart, end: monthEnd,
            title: title, now: now, timeZone: timeZone
        )
    }

    /// v15.23 batch196 · 通用区间报告（周报 / 任意自定义区间复用）
    /// - Parameters:
    ///   - start: 区间起（包含）
    ///   - end: 区间止（不包含）
    ///   - title: 报告标题（如 "近 7 天周报" / "2026-04 月报"）
    public static func generateInRange(
        positions: [ClosedPosition],
        start: Date,
        end: Date,
        title: String,
        now: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> String {
        let monthly = positions.filter { $0.closeTime >= start && $0.closeTime < end }
        return renderBody(
            slice: monthly, title: title, now: now, timeZone: timeZone
        )
    }

    /// v15.23 batch196 · 周报快捷入口（最近 7 天 · 与 trader 周复盘节奏一致）
    public static func generateWeekly(
        positions: [ClosedPosition],
        now: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.date(byAdding: .day, value: -7, to: now) ?? now
        return generateInRange(
            positions: positions, start: start, end: now,
            title: "近 7 天复盘周报", now: now, timeZone: timeZone
        )
    }

    /// 内部渲染（共用 month / week / range 三个入口）
    private static func renderBody(
        slice monthly: [ClosedPosition],
        title: String,
        now: Date,
        timeZone: TimeZone
    ) -> String {

        let streak = ReviewAnalytics.streakMetrics(from: monthly)
        let risk = ReviewAnalytics.riskAdjustedMetrics(from: monthly)
        let profit = ReviewAnalytics.profitabilityMetrics(from: monthly)
        let instrument = ReviewAnalytics.instrumentMatrix(from: monthly)
        let session = ReviewAnalytics.sessionPnL(from: monthly)
        let dd = ReviewAnalytics.maxDrawdownCurve(from: monthly)
        let tagsByPos = EmotionAutoTagger.tagAll(monthly)

        let nowFmt = DateFormatter()
        nowFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        nowFmt.timeZone = timeZone

        var md = ""
        md += "# \(title)\n\n"
        md += "_生成时间：\(nowFmt.string(from: now))（\(timeZone.identifier)）_\n\n"

        md += "## 概览\n\n"
        md += "| 指标 | 值 |\n|---|---|\n"
        md += "| 闭合笔数 | \(monthly.count) |\n"
        md += "| 总 PnL | \(signedDecimal(monthly.reduce(Decimal(0)) { $0 + $1.realizedPnL })) |\n"
        md += "| 胜率 | \(pct(profit.winRate)) |\n"
        md += "| 最大回撤 | -\(decimalAbs(dd.maxDrawdown)) |\n\n"

        md += "## 风险调整指标\n\n"
        md += "| 指标 | 值 |\n|---|---|\n"
        md += "| Sharpe（年化） | \(twoDecimal(risk.sharpeRatio)) |\n"
        md += "| Sortino（年化） | \(twoDecimal(risk.sortinoRatio)) |\n"
        md += "| Calmar | \(twoDecimal(risk.calmarRatio)) |\n"
        md += "| Recovery Factor | \(twoDecimal(risk.recoveryFactor)) |\n"
        md += "| 交易日数 | \(risk.tradingDays) |\n\n"

        md += "## 盈利能力\n\n"
        md += "| 指标 | 值 |\n|---|---|\n"
        md += "| Profit Factor | \(twoDecimal(profit.profitFactor)) |\n"
        md += "| Expectancy（单笔期望） | \(signedDecimal(profit.expectancy)) |\n"
        md += "| 总盈利 | \(decimalAbs(profit.grossWin)) |\n"
        md += "| 总亏损 | -\(decimalAbs(profit.grossLoss)) |\n"
        md += "| 最大单笔盈 | \(decimalAbs(profit.largestWin)) |\n"
        md += "| 最大单笔亏 | -\(decimalAbs(profit.largestLoss)) |\n"
        md += "| 盈利笔数 / 亏损笔数 | \(profit.winningTrades) / \(profit.losingTrades) |\n\n"

        md += "## 连胜连败\n\n"
        md += "- 最长连胜：**\(streak.maxWinningStreak) 笔**\n"
        md += "- 最长连败：**\(streak.maxLosingStreak) 笔**\n"
        md += "- 月末当前连续：\(streakLabel(streak))\n"
        md += "- 胜负切换次数：\(streak.switchCount)\n\n"

        // 心理风险标签分布
        md += "## 心理风险标签分布（自动建议）\n\n"
        var tagCounts: [EmotionAutoTagger.Tag: Int] = [:]
        for (_, tags) in tagsByPos {
            for t in tags { tagCounts[t, default: 0] += 1 }
        }
        if tagCounts.isEmpty {
            md += "_本月无显著心理风险信号 · 心态稳定_\n\n"
        } else {
            md += "| 标签 | 命中笔数 |\n|---|---|\n"
            for tag in EmotionAutoTagger.Tag.allCases {
                if let c = tagCounts[tag], c > 0 {
                    md += "| \(tag.displayName) | \(c) |\n"
                }
            }
            md += "\n"
        }

        // 品种 PnL 分布
        md += "## 品种 PnL 分布\n\n"
        if instrument.cells.isEmpty {
            md += "_本月无成交_\n\n"
        } else {
            md += "| 合约 | 笔数 | 总 PnL | 胜率 |\n|---|---|---|---|\n"
            let sorted = instrument.cells.sorted { $0.totalPnL > $1.totalPnL }
            for cell in sorted {
                md += "| \(cell.instrumentID) | \(cell.tradeCount) | \(signedDecimal(cell.totalPnL)) | \(pct(cell.winRate)) |\n"
            }
            md += "\n"
        }

        // 时段表现
        md += "## 时段表现\n\n"
        md += "| 时段 | 笔数 | 总 PnL | 胜率 |\n|---|---|---|---|\n"
        for b in session.buckets {
            md += "| \(slotLabel(b.slot)) | \(b.tradeCount) | \(signedDecimal(b.totalPnL)) | \(pct(b.winRate)) |\n"
        }
        md += "\n"

        md += "---\n_由 macOS 期货交易终端 v15.19 自动生成 · 数据基于本地 ClosedPosition_\n"
        return md
    }

    // MARK: - 格式化 helper（与 ReviewWindow 同等口径）

    private static func twoDecimal(_ v: Double) -> String { String(format: "%.2f", v) }

    private static func signedDecimal(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        if abs(n - n.rounded()) < 0.01 { return String(format: "%+.0f", n) }
        return String(format: "%+.2f", n)
    }

    private static func decimalAbs(_ v: Decimal) -> String {
        let n = abs(NSDecimalNumber(decimal: v).doubleValue)
        if abs(n - n.rounded()) < 0.01 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }

    private static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }

    private static func streakLabel(_ s: ReviewAnalytics.StreakMetrics) -> String {
        if s.currentStreak == 0 { return "无（月末无成交或全平）" }
        return s.currentStreakIsWinning ? "连胜 \(s.currentStreak) 笔" : "连败 \(abs(s.currentStreak)) 笔"
    }

    private static func slotLabel(_ slot: TradingSlot) -> String {
        switch slot {
        case .morning:   return "早盘 09:00-11:30"
        case .afternoon: return "午盘 13:00-15:00"
        case .night:     return "夜盘 21:00-23:59"
        case .midnight:  return "凌晨 00:00-02:30"
        case .other:     return "其他"
        }
    }
}
