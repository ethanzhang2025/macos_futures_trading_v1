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
    ///   - filterPattern: 仅含该形态（nil = 全部）· batch131
    ///   - filterCutoff: 仅含 startedAt >= cutoff 的 session（nil = 全部）· batch131
    ///   - filterLabel: 标题后追加的过滤说明（如 "本月 · 震荡"）· batch131
    ///   - title: 报告标题（默认 "训练月报"）
    ///   - generatedAt: 报告时间戳（默认 now · 测试可注入）
    ///   - recentLimit: 最近训练表格行数（默认 30）
    public static func generate(_ log: TrainingSessionLog,
                                filterPattern: TrainingScenarioPattern? = nil,
                                filterCutoff: Date? = nil,
                                filterLabel: String? = nil,
                                title: String = "训练月报",
                                generatedAt: Date = Date(),
                                recentLimit: Int = 30) -> String {
        // batch131 · 应用 filter（同时支持 pattern + cutoff · AND）
        var sessions = log.sessions
        if let p = filterPattern { sessions = sessions.filter { $0.scenarioPattern == p } }
        if let cutoff = filterCutoff { sessions = sessions.filter { $0.startedAt >= cutoff } }
        let scores = sessions.compactMap { log.score(for: $0.id) }

        var md = ""
        let titleSuffix = filterLabel.map { "（\($0)）" } ?? ""
        md += "# \(title)\(titleSuffix)\n\n"
        md += "> 生成时间：\(formatDateTime(generatedAt))\n\n"

        // 概览（基于 filtered sessions）
        md += "## 概览\n\n"
        md += "- 总训练次数：**\(sessions.count)**\n"
        let avg = scores.isEmpty ? 0.0
                  : Double(scores.map { $0.totalScore }.reduce(0, +)) / Double(scores.count)
        md += "- 平均分：**\(String(format: "%.1f", avg))**\n"
        if let best = scores.max(by: { $0.totalScore < $1.totalScore }) {
            md += "- 最佳：**\(best.totalScore)** 分（\(best.grade.emoji) \(best.grade.displayName) 级）\n"
        } else {
            md += "- 最佳：—\n"
        }
        md += "\n"

        // 等级分布（基于 filtered scores）
        md += "## 等级分布\n\n"
        var dist: [TrainingScore.Grade: Int] = [:]
        for g in TrainingScore.Grade.allCases { dist[g] = 0 }
        for s in scores { dist[s.grade, default: 0] += 1 }
        md += "| 等级 | 次数 |\n"
        md += "|------|------|\n"
        for grade in TrainingScore.Grade.allCases {
            md += "| \(grade.emoji) \(grade.displayName) | \(dist[grade] ?? 0) |\n"
        }
        md += "\n"

        // 形态分布（基于 filtered sessions）
        md += "## 形态分布\n\n"
        md += patternDistributionMarkdown(sessions: sessions, log: log)

        // 最近训练（filtered sessions desc by endedAt · 取前 recentLimit）
        md += "## 最近训练\n\n"
        let recent = sessions
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(max(0, recentLimit))
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

    /// 形态分布表（计数 + 平均分 · 仅显示 count > 0 的形态）· batch131 改用 sessions 子集
    private static func patternDistributionMarkdown(sessions: [TrainingSession],
                                                    log: TrainingSessionLog) -> String {
        var counts: [TrainingScenarioPattern: (count: Int, totalScore: Int)] = [:]
        for s in sessions {
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

    /// v15.23 batch133 · 单次 session 详细 markdown（训练完看分时复制 · 求点评/记笔记）
    /// 含：评分卡 / 形态 / 交易记录 N 笔 / 违规清单（kind+rule+message）
    public static func generateSingleSession(_ session: TrainingSession,
                                             score: TrainingScore,
                                             title: String? = nil) -> String {
        var md = ""
        let displayTitle = title ?? "训练分析 · \(session.scenarioName.isEmpty ? "未命名" : session.scenarioName)"
        md += "# \(displayTitle)\n\n"
        md += "> \(formatDateTime(session.endedAt)) · 时长 \(session.durationMinutes) 分钟\n\n"

        // 评分卡
        md += "## 评分\n\n"
        md += "- 总分：**\(score.totalScore)** / 100（\(score.grade.emoji) \(score.grade.displayName) 级）\n"
        md += "- 盈亏子分：\(score.pnlScore) / 50\n"
        md += "- 纪律子分：\(score.disciplineScore) / 50\n"
        if let pattern = session.scenarioPattern {
            md += "- 形态：\(pattern.emoji) \(pattern.displayName)\n"
        }
        let pnlPct = String(format: "%+.2f", (session.pnlPercent as NSDecimalNumber).doubleValue)
        let pnlAbs = String(format: "%+.2f", (session.pnl as NSDecimalNumber).doubleValue)
        md += "- 盈亏：\(pnlAbs) 元（\(pnlPct)%）\n\n"
        md += "**评语**：\(score.summary)\n\n"

        // 交易记录
        md += "## 交易记录\n\n"
        if session.trades.isEmpty {
            md += "_无成交_\n\n"
        } else {
            md += "共 \(session.trades.count) 笔\n\n"
        }

        // 违规清单
        md += "## 纪律违规\n\n"
        if session.violations.isEmpty {
            md += "_无违规 · 严守纪律 ✅_\n"
        } else {
            md += "| 时间 | 严重 | 类别 | 触发原因 |\n"
            md += "|------|------|------|----------|\n"
            for v in session.violations {
                let sev = v.severity == .error ? "🔴 违规" : "🟡 警告"
                md += "| \(formatDateTime(v.occurredAt)) | \(sev) | \(v.ruleKind.rawValue) | \(v.message) |\n"
            }
        }

        return md
    }

    private static func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: d)
    }
}
