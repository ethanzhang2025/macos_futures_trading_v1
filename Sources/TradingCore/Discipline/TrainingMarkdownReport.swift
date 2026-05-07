// WP-54 v15.23 batch126 · 训练历史 markdown 月报告生成（跨平台 · Linux 可测）
//
// 用途：trader 月度复盘可一键导出 markdown · 复制到笔记/微信/同行交流
// 输出格式：
//   # 标题
//   ## 概览（次数/平均/最佳）
//   ## 等级分布（S/A/B/C/D 表）
//   ## 形态分布（9 种 emoji 计数 + 平均分）
//   ## 最近训练（30 行 markdown 表格）

import Foundation

public enum TrainingMarkdownReport {

    /// 生成 markdown 文本
    /// - Parameters:
    ///   - log: 训练历史
    ///   - title: 报告标题（默认 "训练月报"）
    ///   - generatedAt: 报告时间戳（默认 now · 测试可注入）
    ///   - recentLimit: 最近训练表格行数（默认 30）
    public static func generate(_ log: TrainingSessionLog,
                                title: String = "训练月报",
                                generatedAt: Date = Date(),
                                recentLimit: Int = 30) -> String {
        var md = ""

        md += "# \(title)\n\n"
        md += "> 生成时间：\(formatDateTime(generatedAt))\n\n"

        // 概览
        md += "## 概览\n\n"
        md += "- 总训练次数：**\(log.sessionCount)**\n"
        md += "- 平均分：**\(String(format: "%.1f", log.averageScore))**\n"
        if let best = log.bestScore {
            md += "- 最佳：**\(best.totalScore)** 分（\(best.grade.emoji) \(best.grade.displayName) 级）\n"
        } else {
            md += "- 最佳：—\n"
        }
        md += "\n"

        // 等级分布
        md += "## 等级分布\n\n"
        let dist = log.gradeDistribution
        md += "| 等级 | 次数 |\n"
        md += "|------|------|\n"
        for grade in TrainingScore.Grade.allCases {
            md += "| \(grade.emoji) \(grade.displayName) | \(dist[grade] ?? 0) |\n"
        }
        md += "\n"

        // 形态分布
        md += "## 形态分布\n\n"
        md += patternDistributionMarkdown(log)

        // 最近训练
        md += "## 最近训练\n\n"
        let recent = log.recentSessions(limit: recentLimit)
        if recent.isEmpty {
            md += "_暂无训练记录_\n"
        } else {
            md += "| 日期 | 场景 | 形态 | 总分 | 等级 | 盈亏% |\n"
            md += "|------|------|------|------|------|-------|\n"
            for session in recent {
                let s = log.score(for: session.id)
                let date = formatDateTime(session.endedAt)
                let scenarioName = session.scenarioName.isEmpty ? "—" : session.scenarioName
                let patternStr = session.scenarioPattern
                    .map { "\($0.emoji) \($0.displayName)" } ?? "—"
                let total = "\(s?.totalScore ?? 0)"
                let grade = s?.grade.emoji ?? "—"
                let pnlPct = String(format: "%+.2f", (session.pnlPercent as NSDecimalNumber).doubleValue)
                md += "| \(date) | \(scenarioName) | \(patternStr) | \(total) | \(grade) | \(pnlPct)% |\n"
            }
        }

        return md
    }

    /// 形态分布表（计数 + 平均分 · 仅显示 count > 0 的形态）
    private static func patternDistributionMarkdown(_ log: TrainingSessionLog) -> String {
        var counts: [TrainingScenarioPattern: (count: Int, totalScore: Int)] = [:]
        for s in log.sessions {
            guard let p = s.scenarioPattern else { continue }
            let scoreVal = log.score(for: s.id)?.totalScore ?? 0
            let cur = counts[p] ?? (0, 0)
            counts[p] = (cur.count + 1, cur.totalScore + scoreVal)
        }
        guard !counts.isEmpty else { return "_暂无形态记录_\n\n" }
        var md = "| 形态 | 次数 | 平均分 |\n"
        md += "|------|------|--------|\n"
        for pat in TrainingScenarioPattern.allCases {
            guard let entry = counts[pat], entry.count > 0 else { continue }
            let avg = entry.count > 0 ? entry.totalScore / entry.count : 0
            md += "| \(pat.emoji) \(pat.displayName) | \(entry.count) | \(avg) |\n"
        }
        md += "\n"
        return md
    }

    private static func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: d)
    }
}
