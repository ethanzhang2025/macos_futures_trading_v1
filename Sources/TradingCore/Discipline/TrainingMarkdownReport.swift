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

    /// v15.23 batch197 · 训练周报（最近 7 天 · 与 ReviewWindow 周报节奏对齐）
    /// 复用 generate · 设置 cutoff = now - 7d · title = "训练周报"
    public static func generateWeekly(_ log: TrainingSessionLog,
                                       generatedAt: Date = Date()) -> String {
        let cutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -7, to: generatedAt) ?? generatedAt
        return generate(log,
                        filterCutoff: cutoff,
                        title: "训练周报",
                        generatedAt: generatedAt,
                        recentLimit: 50)
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

        // v16.6 评分 v2 · 五维细分 + weakness（subScores 非 nil 时输出）
        if let sub = score.subScores {
            md += "## 五维细分（仅作分析视角 · 不计入总分）\n\n"
            md += "| 维度 | 得分 |\n"
            md += "|------|------|\n"
            for entry in sub.ordered {
                let mark = (entry.dimension == sub.weakest) ? " ⚠️ 最弱" : ""
                md += "| \(entry.dimension.emoji) \(entry.dimension.displayName) | \(entry.score) / 100\(mark) |\n"
            }
            md += "\n**💡 改进建议**（最弱：\(sub.weakest.emoji) \(sub.weakest.displayName)）：\(sub.weakness)\n\n"
        }

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

    // MARK: - v16.15 · 月报 / 周报 训练 annex（与 ReviewWindow.MonthlyReportGenerator 拼接）

    /// 训练 annex（区间内 · 用于复盘月报/周报追加）
    /// - 输出含：区间训练总数 + 各 pattern 计数/均分/最佳 + 弱项加练建议
    /// - 区间内 0 训练时返回提示文案 · 不返回空字符串（让 trader 知道 annex 触发但无数据）
    public static func generateMonthlyAnnex(_ log: TrainingSessionLog,
                                             start: Date,
                                             end: Date) -> String {
        let inRange = log.sessions.filter { $0.startedAt >= start && $0.startedAt < end }
        var md = "## 训练评分关联（M5 模拟训练 · 区间内）\n\n"
        guard !inRange.isEmpty else {
            md += "_本区间无训练记录 · 建议每周 ≥ 3 次同形态训练 · 与实盘 setup 形成正反馈_\n\n"
            return md
        }
        let scores = inRange.compactMap { log.score(for: $0.id)?.totalScore }
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let best = scores.max() ?? 0
        md += "- 训练次数：**\(inRange.count)** · 平均 **\(avg)** 分 · 最佳 **\(best)** 分\n\n"

        // 各 pattern 分布
        struct Bucket { var count = 0; var totalScore = 0; var bestScore = 0 }
        var byPattern: [TrainingScenarioPattern: Bucket] = [:]
        for s in inRange {
            guard let p = s.scenarioPattern,
                  let total = log.score(for: s.id)?.totalScore else { continue }
            var b = byPattern[p] ?? Bucket()
            b.count += 1
            b.totalScore += total
            b.bestScore = max(b.bestScore, total)
            byPattern[p] = b
        }
        if byPattern.isEmpty {
            md += "_无 pattern 标注的训练（建议从训练面板的推荐场景启动 · 自动带 pattern）_\n\n"
            return md
        }
        md += "| 形态 | 次数 | 平均分 | 最佳 | 建议 |\n|---|---|---|---|---|\n"
        for pat in TrainingScenarioPattern.allCases {
            guard let b = byPattern[pat], b.count > 0 else { continue }
            let patAvg = b.totalScore / b.count
            let advice: String
            if patAvg < 60 {
                advice = "⚠️ 薄弱 · 加练 ≥ 3 次"
            } else if patAvg < 70 {
                advice = "🟡 待巩固 · 复盘+1 次"
            } else if patAvg < 85 {
                advice = "🟢 良好"
            } else {
                advice = "🏆 强项"
            }
            md += "| \(pat.emoji) \(pat.displayName) | \(b.count) | \(patAvg) | \(b.bestScore) | \(advice) |\n"
        }
        md += "\n"
        // 全局提示：均分 < 70 时给整体建议
        if avg < 70 {
            md += "_⚠️ 整体训练均分 \(avg) 分（< B 级）· 建议本月加大训练频率 · 重点攻克薄弱形态_\n\n"
        }
        return md
    }

    /// v16.21 · 实盘 setup ↔ 训练 pattern cross-reference
    /// 用包含匹配（实盘 setup 名是否含 pattern displayName 子串 · 大小写不敏感）
    /// 输出：实盘 setup 笔数/胜率 / 训练 pattern 次数/均分 / 双弱建议
    /// - 不依赖 JournalCore · 调用方传 SetupSlice 简单元组数组
    public struct SetupSlice: Sendable, Equatable {
        public let setupName: String
        public let tradeCount: Int
        public let winRate: Double      // 0..1
        public init(setupName: String, tradeCount: Int, winRate: Double) {
            self.setupName = setupName
            self.tradeCount = tradeCount
            self.winRate = winRate
        }
    }

    public static func generateSetupPatternCrossReference(_ log: TrainingSessionLog,
                                                           setups: [SetupSlice],
                                                           start: Date,
                                                           end: Date) -> String {
        var md = "## 实盘 setup ↔ 训练 pattern 交叉分析（v16.21）\n\n"
        let labeled = setups.filter { !$0.setupName.isEmpty
                                      && $0.setupName != "(未标)" }
        guard !labeled.isEmpty else {
            md += "_本区间无具名 setup 实盘记录 · 先在交易日志窗给开仓 trade 打 setup 标签_\n\n"
            return md
        }
        let inRange = log.sessions.filter { $0.startedAt >= start && $0.startedAt < end }
        // 训练 pattern 桶（区间内）
        struct PatBucket { var count = 0; var totalScore = 0 }
        var byPattern: [TrainingScenarioPattern: PatBucket] = [:]
        for s in inRange {
            guard let p = s.scenarioPattern,
                  let total = log.score(for: s.id)?.totalScore else { continue }
            var b = byPattern[p] ?? PatBucket()
            b.count += 1; b.totalScore += total
            byPattern[p] = b
        }
        md += "| 实盘 setup | 实盘笔数 | 实盘胜率 | 关联 pattern | 训练次数 | 训练均分 | 综合建议 |\n"
        md += "|---|---|---|---|---|---|---|\n"
        for slice in labeled {
            let matched = matchPattern(setupName: slice.setupName)
            let bucket = matched.flatMap { byPattern[$0] }
            let patStr = matched.map { "\($0.emoji) \($0.displayName)" } ?? "—"
            let trainCount = bucket?.count ?? 0
            let trainAvg = (bucket?.count ?? 0) > 0 ? (bucket!.totalScore / bucket!.count) : 0
            let trainStr = trainCount > 0 ? "\(trainCount)" : "—"
            let trainAvgStr = trainCount > 0 ? "\(trainAvg)" : "—"
            let advice = crossAdvice(realWinRate: slice.winRate, trainAvg: trainAvg, trainCount: trainCount)
            md += "| \(slice.setupName) | \(slice.tradeCount) | \(Int((slice.winRate * 100).rounded()))% | "
            md += "\(patStr) | \(trainStr) | \(trainAvgStr) | \(advice) |\n"
        }
        md += "\n"
        return md
    }

    /// 包含匹配：setup 名是否含 pattern displayName 子串（大小写不敏感）
    /// 多 pattern 命中时取最长 displayName（更精确）
    static func matchPattern(setupName: String) -> TrainingScenarioPattern? {
        let needle = setupName.lowercased()
        let candidates = TrainingScenarioPattern.allCases.compactMap { pat -> (TrainingScenarioPattern, Int)? in
            let name = pat.displayName.lowercased()
            return needle.contains(name) ? (pat, pat.displayName.count) : nil
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    /// 综合建议：实盘胜率 vs 训练均分 4 象限
    static func crossAdvice(realWinRate: Double, trainAvg: Int, trainCount: Int) -> String {
        guard trainCount > 0 else { return "🟦 无训练记录 · 建议加练" }
        let realStrong = realWinRate >= 0.55
        let trainStrong = trainAvg >= 70
        switch (realStrong, trainStrong) {
        case (true, true):   return "✅ 双强 · 保持节奏"
        case (true, false):  return "🟡 实盘强 / 训练弱 · 抽空补练"
        case (false, true):  return "🟠 训练好但实盘差 · 复盘执行偏差"
        case (false, false): return "🔴 双弱 · 优先加练 + 减仓"
        }
    }
}
