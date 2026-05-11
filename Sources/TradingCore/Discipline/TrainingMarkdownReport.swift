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

        // v16.169 · 目录（章节锚点 · 长月报 trader 快速跳转）· markdown 渲染器自动锚点 ## X → #x
        // v16.186 · 加 v16.176/183/185 新章节
        md += "## 目录\n\n"
        md += "1. [概览](#概览)\n"
        md += "2. [等级分布](#等级分布)\n"
        md += "3. [形态分布](#形态分布)\n"
        md += "4. [五维平均](#五维平均-v2-评分)\n"
        md += "5. [改进 plan](#改进-plan)\n"
        md += "6. [本月最强 / 最弱 session](#本月最强-session)\n"
        md += "7. [单笔盈利冠军](#单笔盈利冠军)\n"
        md += "7a. [最常违反规则](#本月最常违反规则)\n"
        md += "8. [训练时长分布](#训练时长分布)\n"
        md += "9. [30 天训练日历](#最近-30-天训练习惯-emoji-日历)\n"
        md += "9a. [14 天每日平均分](#近-14-天每日平均分)\n"
        md += "10. [每周分布](#每周分布哪天最活跃)\n"
        md += "11. [最佳训练时段](#最佳训练时段)\n"
        md += "12. [总分趋势 sparkline](#最近-n-次总分趋势)\n"
        md += "13. [本月 vs 上月](#本月-vs-上月)\n"
        md += "14. [最近训练](#最近训练)\n"
        md += "15. [心理风险洞察](#心理风险洞察-v1638--月度最弱心理--改进建议)\n\n"

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
        // v16.123 · 累计训练时长 + milestone（与 v16.122 HistoryPanel 同 5 级 emoji）
        let totalMinutes = sessions.map { $0.durationMinutes }.reduce(0, +)
        if totalMinutes > 0 {
            let hours = Double(totalMinutes) / 60.0
            let milestone: String = {
                switch hours {
                case 1000...:  return "🌟"
                case 500...:   return "👑"
                case 100...:   return "🏆"
                case 50...:    return "🚀"
                case 10...:    return "🎯"
                default:       return "⏱"
                }
            }()
            md += "- 累计训练时长：\(milestone) **\(String(format: "%.1f", hours))** 小时\n"
        }

        // v16.86 · 连训天数（与 ControlBar/HistoryPanel 同算法 · 月报展示 trader 习惯）
        // v16.91 · 加 personal best 对比（v16.89）· 当前 ≥ 历史 → 🎉 新纪录
        let streak = log.consecutiveTrainingDays(asOf: generatedAt)
        let bestStreak = log.longestStreakEver()
        if streak >= 2 {
            let isNewRecord = streak >= bestStreak
            let emoji: String = {
                if isNewRecord { return "🎉" }
                switch streak {
                case 30...:  return "🏆"
                case 14...:  return "🚀"
                case 7...:   return "🔥🔥"
                default:     return "🔥"
                }
            }()
            md += "- 当前连训：\(emoji) **\(streak)** 天"
            if isNewRecord {
                md += "（**新纪录**！超越历史最长）\n"
            } else {
                md += "（历史最长 \(bestStreak) 天）\n"
            }
        } else if bestStreak >= 3 {
            md += "- 历史最长连训：🏅 \(bestStreak) 天（当前已中断 · 重新开始即可！）\n"
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

        // v16.63 · 五维平均（仅含 v2 subScores 的 session · 旧 session 自动跳过）
        md += fiveDimAverageMarkdown(sessions: sessions, log: log)

        // v16.153 · 月报最弱维度 5 步行动 plan（trader 月度回顾自带行动建议）
        md += monthlyImprovementPlanMarkdown(sessions: sessions, log: log)

        // v16.161 · 月报最强 session 引用（trader 月度回顾本月 best · 强化正向反馈）
        md += monthlyBestSessionMarkdown(sessions: sessions, log: log)

        // v16.165 · 月报最弱 session 引用（trader 月度看 worst 对照学习）
        md += monthlyWorstSessionMarkdown(sessions: sessions, log: log)

        // v16.188 · 本月最常违反规则 Top 3（trader 月度看纪律弱点）
        md += mostViolatedRulesMarkdown(sessions: sessions)

        // v16.172 · 单笔盈利最大 session（与 score-best 互补 · pnl 维度的最大单笔）
        md += monthlyMaxPnlSessionMarkdown(sessions: sessions, log: log)

        // v16.118 · 训练时长分布（短/中/长 · trader 看专注时长习惯）
        md += durationDistributionMarkdown(sessions: sessions)

        // v16.164 · 最近 30 天训练日历 mini sparkline（emoji 方块 · trader 看习惯密度）
        md += recentTrainingCalendarMarkdown(sessions: sessions, generatedAt: generatedAt)

        // v16.191 · 近 14 天每日平均分 sparkline（与 v16.164 次数日历不同视角）
        md += dailyAverageScoreSparklineMarkdown(sessions: sessions, log: log, generatedAt: generatedAt)

        // v16.170 · 每周分布表（周一-周日 训练次数 · trader 看哪天最活跃）
        md += weekdayDistributionMarkdown(sessions: sessions)

        // v16.185 · 最佳训练时段（按 hour 分布 · trader 知道高效交易时段）
        md += hourOfDayDistributionMarkdown(sessions: sessions)

        // v16.176 · 最近 N 次总分 sparkline（emoji bar 横排 · 分数走势可视化）
        md += scoreTrendSparklineMarkdown(sessions: sessions, log: log)

        // v16.183 · 本月 vs 上月对比（5 维 + 总分趋势）· 仅全量月报输出（filterCutoff 不为 nil 跳过）
        if filterCutoff == nil {
            md += monthOverMonthComparisonMarkdown(log: log, generatedAt: generatedAt)
        }

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

        // v16.180 · markdown footer · 数据来源 + 字段说明（trader 月度回顾时知道数据背景）
        md += "\n---\n\n"
        md += "_数据来源：本地训练日志（TrainingSessionLog · 不上云）· 总分 v1 (pnl×2 + discipline×2) · 五维 v2 (pnl/discipline/winRate/risk/efficiency) · 评分细节见五维公式 hover_\n"

        return md
    }

    /// v16.118 · 训练时长分布 markdown 章节（短/中/长 3 段 · trader 专注习惯）
    /// 短：< 15 分（试探 / 中断）· 中：15-30 分（专注训练）· 长：> 30 分（完整复盘）
    private static func durationDistributionMarkdown(sessions: [TrainingSession]) -> String {
        guard !sessions.isEmpty else { return "" }
        let shortCount = sessions.filter { $0.durationMinutes < 15 }.count
        let mediumCount = sessions.filter { $0.durationMinutes >= 15 && $0.durationMinutes <= 30 }.count
        let longCount = sessions.filter { $0.durationMinutes > 30 }.count
        let total = sessions.count
        func pct(_ n: Int) -> String {
            String(format: "%.0f", Double(n) / Double(total) * 100)
        }
        var md = "## 训练时长分布（trader 专注习惯）\n\n"
        md += "| 分段 | 次数 | 占比 |\n"
        md += "|------|------|------|\n"
        md += "| 🏃 短 (< 15 分) | \(shortCount) | \(pct(shortCount))% |\n"
        md += "| 🎯 中 (15-30 分) | \(mediumCount) | \(pct(mediumCount))% |\n"
        md += "| 🧘 长 (> 30 分) | \(longCount) | \(pct(longCount))% |\n"
        md += "\n"
        // 建议
        if shortCount > total / 2 {
            md += "**💡 建议**：超过半数训练 < 15 分钟 · 可能过于试探 / 中断频繁 · 建议至少 15 分钟一次专注训练\n\n"
        } else if longCount > total / 2 {
            md += "**💡 建议**：超过半数训练 > 30 分钟 · 单次过长可能效率递减 · 建议拆短 + 中间休息\n\n"
        }
        return md
    }

    /// v16.63 · 五维平均 markdown 章节（与 HistoryPanel fiveDimAverageRow / CSV 五维列同源）
    /// 仅 v2 subScores 非 nil 的 session 参与 · 老 session 自动跳过
    /// 输出表格 · 最弱维度 emoji 加 ⚠ 标记 · trader 月度看五维倾向
    private static func fiveDimAverageMarkdown(sessions: [TrainingSession],
                                                log: TrainingSessionLog) -> String {
        let subs = sessions.compactMap { log.score(for: $0.id)?.subScores }
        guard !subs.isEmpty else { return "" }
        let n = subs.count
        let avgPnl = subs.map(\.pnl).reduce(0, +) / n
        let avgDisc = subs.map(\.discipline).reduce(0, +) / n
        let avgWin = subs.map(\.winRate).reduce(0, +) / n
        let avgRisk = subs.map(\.risk).reduce(0, +) / n
        let avgEff = subs.map(\.efficiency).reduce(0, +) / n
        let items: [(TrainingSubScores.Dimension, Int)] = [
            (.pnl, avgPnl), (.discipline, avgDisc), (.winRate, avgWin),
            (.risk, avgRisk), (.efficiency, avgEff),
        ]
        let worst = items.min(by: { $0.1 < $1.1 })?.0 ?? .pnl
        var md = "## 五维平均（v2 评分 · \(n) 次）\n\n"
        md += "| 维度 | 均分 |\n"
        md += "|------|------|\n"
        for (dim, avg) in items {
            let marker = dim == worst ? " ⚠ 最弱" : ""
            md += "| \(dim.emoji) \(dim.displayName) | \(avg)\(marker) |\n"
        }
        md += "\n"
        return md
    }

    /// v16.170 · 每周分布表 · 哪一天 trader 最活跃训练
    /// Calendar.weekday: 1=周日 / 2=周一 / ... / 7=周六（gregorian 默认）
    /// 输出表格 · 最活跃日加 🔥 标记
    private static func weekdayDistributionMarkdown(sessions: [TrainingSession]) -> String {
        guard !sessions.isEmpty else { return "" }
        let cal = Calendar(identifier: .gregorian)
        var counts: [Int: Int] = [:]   // weekday → count
        for s in sessions {
            let wd = cal.component(.weekday, from: s.endedAt)
            counts[wd, default: 0] += 1
        }
        let names = [1: "周日", 2: "周一", 3: "周二", 4: "周三",
                     5: "周四", 6: "周五", 7: "周六"]
        // 周一开头排序（trader 习惯）：2,3,4,5,6,7,1
        let order = [2, 3, 4, 5, 6, 7, 1]
        let maxCount = counts.values.max() ?? 0
        var md = "## 每周分布（哪天最活跃）\n\n"
        md += "| 星期 | 次数 |\n|------|------|\n"
        for wd in order {
            let cnt = counts[wd] ?? 0
            let marker = (cnt > 0 && cnt == maxCount) ? " 🔥" : ""
            md += "| \(names[wd] ?? "?") | \(cnt)\(marker) |\n"
        }
        md += "\n"
        return md
    }

    /// v16.165 · 月报最弱 session 引用 · trader 月度看 worst 对照学习（与 best 对比）
    /// 找 totalScore 最低的 session（同分取最近）· best/worst 同分时跳过（避免重复）
    private static func monthlyWorstSessionMarkdown(sessions: [TrainingSession],
                                                     log: TrainingSessionLog) -> String {
        let scored = sessions.compactMap { s -> (TrainingSession, TrainingScore)? in
            guard let sc = log.score(for: s.id) else { return nil }
            return (s, sc)
        }
        guard scored.count >= 2 else { return "" }   // 至少 2 个才有 worst 概念
        let sortedDesc = scored.sorted {
            if $0.1.totalScore != $1.1.totalScore { return $0.1.totalScore > $1.1.totalScore }
            return $0.0.endedAt > $1.0.endedAt
        }
        // best 与 worst 同分则跳过（数据一致 · 不重复）
        guard sortedDesc.first!.1.totalScore != sortedDesc.last!.1.totalScore else { return "" }
        let worst = sortedDesc.last!
        let s = worst.0
        let sc = worst.1
        var md = "## 本月最弱 session · \(sc.grade.emoji) \(sc.totalScore) 分\n\n"
        md += "- 场景：**\(s.scenarioName.isEmpty ? "未命名" : s.scenarioName)**"
        if let pat = s.scenarioPattern {
            md += " · \(pat.emoji) \(pat.displayName)"
        }
        md += "\n"
        let pnlPct = (s.pnlPercent as NSDecimalNumber).doubleValue
        md += String(format: "- 盈亏：%+.2f%% · 总分 %d · %@ 级\n", pnlPct, sc.totalScore, sc.grade.displayName)
        if let sub = sc.subScores {
            md += "- 5 维："
            md += sub.ordered.map { "\($0.dimension.emoji) \($0.score)" }.joined(separator: " / ")
            md += "\n"
        }
        md += "- 💡 复盘建议：对照本月最强 session 找差异 · 找出可复制的成功模式\n"
        md += "\n"
        return md
    }

    /// v16.191 · 近 14 天每日平均分 sparkline · emoji bar 5 级 · 与 v16.176 总分趋势不同维度
    /// 那个是按 session 排 · 这个是按日期排 · 同日多 session 取均
    private static func dailyAverageScoreSparklineMarkdown(sessions: [TrainingSession],
                                                            log: TrainingSessionLog,
                                                            generatedAt: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: generatedAt)
        var dailyAvg: [Date: Int] = [:]
        // 初始化 14 天 + 0 占位
        for offset in 0..<14 {
            if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                dailyAvg[d] = 0
            }
        }
        // 聚合：按日 group sessions · 取每天的 score 均值
        var dailyScores: [Date: [Int]] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.endedAt)
            guard dailyAvg[day] != nil, let score = log.score(for: s.id)?.totalScore else { continue }
            dailyScores[day, default: []].append(score)
        }
        for (day, scores) in dailyScores {
            dailyAvg[day] = scores.reduce(0, +) / max(1, scores.count)
        }
        let nonZero = dailyAvg.values.filter { $0 > 0 }
        guard nonZero.count >= 3 else { return "" }   // < 3 天数据无趋势可言
        let barEmoji: (Int) -> String = { s in
            switch s {
            case 80...:  return "█"
            case 60...:  return "▇"
            case 40...:  return "▅"
            case 20...:  return "▃"
            case 1...:   return "▁"
            default:     return "·"   // 0 = 无训练
            }
        }
        var md = "## 近 14 天每日平均分\n\n"
        md += "```\n"
        for offset in (0..<14).reversed() {
            if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                md += barEmoji(dailyAvg[d] ?? 0)
            }
        }
        md += "\n```\n\n"
        let avg = nonZero.reduce(0, +) / nonZero.count
        md += "- 训练 \(nonZero.count) 天 · 每日均分 \(avg)（仅含训练日）· · = 无训练\n\n"
        return md
    }

    /// v16.183 · 本月 vs 上月对比 · 总分平均 + 次数 + 5 维平均 delta
    /// 仅在全量月报输出（generate 不传 filterCutoff 时） · 防与 filtered 月份月报冲突
    private static func monthOverMonthComparisonMarkdown(log: TrainingSessionLog,
                                                          generatedAt: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let thisMonthStart = cal.dateInterval(of: .month, for: generatedAt)?.start ?? generatedAt
        guard let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) else { return "" }

        let thisMonth = log.sessions.filter { $0.startedAt >= thisMonthStart }
        let lastMonth = log.sessions.filter {
            $0.startedAt >= lastMonthStart && $0.startedAt < thisMonthStart
        }
        guard !thisMonth.isEmpty || !lastMonth.isEmpty else { return "" }
        guard !lastMonth.isEmpty else { return "" }   // 上月无数据无法对比

        // 总分平均
        let avgScore: ([TrainingSession]) -> Int = { sessions in
            let scores = sessions.compactMap { log.score(for: $0.id)?.totalScore }
            guard !scores.isEmpty else { return 0 }
            return scores.reduce(0, +) / scores.count
        }
        let thisAvg = avgScore(thisMonth)
        let lastAvg = avgScore(lastMonth)
        let delta = thisAvg - lastAvg
        let trend = delta > 0 ? "↑" : (delta < 0 ? "↓" : "=")
        let trendEmoji = delta > 0 ? "📈" : (delta < 0 ? "📉" : "➡️")

        var md = "## 本月 vs 上月\n\n"
        md += "| 指标 | 上月 | 本月 | 变化 |\n|------|------|------|------|\n"
        md += "| 训练次数 | \(lastMonth.count) | \(thisMonth.count) | \(thisMonth.count - lastMonth.count >= 0 ? "+" : "")\(thisMonth.count - lastMonth.count) |\n"
        md += "| 平均总分 | \(lastAvg) | \(thisAvg) | \(trend) \(delta >= 0 ? "+" : "")\(delta) \(trendEmoji) |\n"
        // 5 维平均对比（仅当两月都有 v2 subScores）
        let thisSubs = thisMonth.compactMap { log.score(for: $0.id)?.subScores }
        let lastSubs = lastMonth.compactMap { log.score(for: $0.id)?.subScores }
        if !thisSubs.isEmpty && !lastSubs.isEmpty {
            let avg5: ([TrainingSubScores]) -> [(TrainingSubScores.Dimension, Int)] = { subs in
                let n = subs.count
                return [
                    (.pnl, subs.map(\.pnl).reduce(0, +) / n),
                    (.discipline, subs.map(\.discipline).reduce(0, +) / n),
                    (.winRate, subs.map(\.winRate).reduce(0, +) / n),
                    (.risk, subs.map(\.risk).reduce(0, +) / n),
                    (.efficiency, subs.map(\.efficiency).reduce(0, +) / n),
                ]
            }
            let thisAvgs = avg5(thisSubs)
            let lastAvgs = avg5(lastSubs)
            for i in 0..<thisAvgs.count {
                let dim = thisAvgs[i].0
                let t = thisAvgs[i].1
                let l = lastAvgs[i].1
                let d = t - l
                md += "| \(dim.emoji) \(dim.displayName) | \(l) | \(t) | \(d >= 0 ? "+" : "")\(d) |\n"
            }
        }
        md += "\n"
        return md
    }

    /// v16.185 · 最佳训练时段 · 按开始时段（hour）分布 · 4 段汇总（凌晨 / 上午 / 下午 / 夜晚）
    /// trader 看自己最高效的训练 hour · 调整作息
    private static func hourOfDayDistributionMarkdown(sessions: [TrainingSession]) -> String {
        guard !sessions.isEmpty else { return "" }
        let cal = Calendar(identifier: .gregorian)
        // 4 时段桶：凌晨 0-6 / 上午 6-12 / 下午 12-18 / 夜晚 18-24
        var buckets = ["🌙 凌晨 (0-6)": 0, "🌅 上午 (6-12)": 0, "☀️ 下午 (12-18)": 0, "🌃 夜晚 (18-24)": 0]
        for s in sessions {
            let hour = cal.component(.hour, from: s.startedAt)
            switch hour {
            case 0..<6:   buckets["🌙 凌晨 (0-6)"]! += 1
            case 6..<12:  buckets["🌅 上午 (6-12)"]! += 1
            case 12..<18: buckets["☀️ 下午 (12-18)"]! += 1
            default:      buckets["🌃 夜晚 (18-24)"]! += 1
            }
        }
        let order = ["🌙 凌晨 (0-6)", "🌅 上午 (6-12)", "☀️ 下午 (12-18)", "🌃 夜晚 (18-24)"]
        let maxCount = buckets.values.max() ?? 0
        var md = "## 最佳训练时段\n\n"
        md += "| 时段 | 次数 |\n|------|------|\n"
        for label in order {
            let cnt = buckets[label] ?? 0
            let marker = (cnt > 0 && cnt == maxCount) ? " ⭐" : ""
            md += "| \(label) | \(cnt)\(marker) |\n"
        }
        md += "\n"
        return md
    }

    /// v16.176 · 最近 N 次总分 sparkline · emoji bar 高度按分数（0-100）
    /// 取最近 20 次（按 endedAt desc）· 翻成时间正序展示
    /// emoji 高度 5 级：▁ < 20 / ▃ 20-39 / ▅ 40-59 / ▇ 60-79 / █ 80+
    private static func scoreTrendSparklineMarkdown(sessions: [TrainingSession],
                                                     log: TrainingSessionLog) -> String {
        let scored = sessions.compactMap { s -> Int? in log.score(for: s.id).map { $0.totalScore } }
        guard scored.count >= 2 else { return "" }
        // 按时间排序 desc → 取前 N → 反转为正序展示
        let recent = sessions.sorted { $0.endedAt > $1.endedAt }.prefix(20)
        let scoresInOrder = recent.compactMap { log.score(for: $0.id)?.totalScore }.reversed()
        guard scoresInOrder.count >= 2 else { return "" }
        let barEmoji: (Int) -> String = { s in
            switch s {
            case 80...:  return "█"
            case 60...:  return "▇"
            case 40...:  return "▅"
            case 20...:  return "▃"
            default:     return "▁"
            }
        }
        var md = "## 最近 \(scoresInOrder.count) 次总分趋势\n\n"
        md += "```\n"
        md += scoresInOrder.map { barEmoji($0) }.joined()
        md += "\n"
        // 第二行：标注前后分数
        let first = scoresInOrder.first ?? 0
        let last = scoresInOrder.last ?? 0
        md += String(repeating: " ", count: 0) + "\(first)"
        md += String(repeating: " ", count: max(0, scoresInOrder.count - 4))
        md += " \(last)\n"
        md += "```\n\n"
        let delta = last - first
        md += "- 起始 \(first) → 最新 \(last) · 趋势 \(delta >= 0 ? "+" : "")\(delta)\n\n"
        return md
    }

    /// v16.188 · 本月最常违反规则 Top 3 · trader 月度看纪律弱点
    /// 按 ruleKind 分组计数 · 总数排序 desc · 仅 ≥ 1 violation 输出
    private static func mostViolatedRulesMarkdown(sessions: [TrainingSession]) -> String {
        let allViolations = sessions.flatMap(\.violations)
        guard !allViolations.isEmpty else { return "" }
        let grouped = Dictionary(grouping: allViolations, by: { $0.ruleKind })
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        let top = grouped.prefix(3)
        var md = "## 本月最常违反规则\n\n"
        md += "| 排名 | 规则 | 次数 |\n|------|------|------|\n"
        for (idx, item) in top.enumerated() {
            let medal = ["🥇", "🥈", "🥉"][idx]
            md += "| \(medal) | \(item.kind.displayName) | \(item.count) |\n"
        }
        let totalCount = allViolations.count
        md += "\n_共 \(totalCount) 次违规 · 集中于上述 \(top.count) 类规则 · 建议优先复盘 \(top.first?.kind.displayName ?? "") 类_\n\n"
        return md
    }

    /// v16.172 · 单笔盈利率最大的 session · 与 v16.161 totalScore-best 互补
    /// 若已与 best 同一 session（盈利冠军同时也是分数冠军 · 已展示）→ 跳过避免重复
    private static func monthlyMaxPnlSessionMarkdown(sessions: [TrainingSession],
                                                      log: TrainingSessionLog) -> String {
        guard !sessions.isEmpty else { return "" }
        // 取 pnlPercent 最大（最赚 · 不取绝对值 · 大亏损不算 highlight）
        let topPnL = sessions.sorted {
            ($0.pnlPercent as NSDecimalNumber).doubleValue > ($1.pnlPercent as NSDecimalNumber).doubleValue
        }.first!
        let pnlPct = (topPnL.pnlPercent as NSDecimalNumber).doubleValue
        guard pnlPct > 0 else { return "" }   // 全月亏损不输出
        // 找 best score session（v16.161 同算法 · 同 session 则跳过）
        let scored = sessions.compactMap { s -> (TrainingSession, TrainingScore)? in
            guard let sc = log.score(for: s.id) else { return nil }
            return (s, sc)
        }
        let bestScoreSession = scored.sorted {
            if $0.1.totalScore != $1.1.totalScore { return $0.1.totalScore > $1.1.totalScore }
            return $0.0.endedAt > $1.0.endedAt
        }.first?.0
        if bestScoreSession?.id == topPnL.id { return "" }   // 已展示
        var md = "## 单笔盈利冠军\n\n"
        md += "- 场景：**\(topPnL.scenarioName.isEmpty ? "未命名" : topPnL.scenarioName)**"
        if let pat = topPnL.scenarioPattern {
            md += " · \(pat.emoji) \(pat.displayName)"
        }
        md += "\n"
        md += String(format: "- 盈亏率：**+%.2f%%**（最高单笔）\n", pnlPct)
        if let sc = log.score(for: topPnL.id) {
            md += "- 总分：\(sc.totalScore) · \(sc.grade.emoji) \(sc.grade.displayName) 级\n"
        }
        md += "\n"
        return md
    }

    /// v16.164 · 最近 30 天训练日历 mini sparkline · GitHub contributions 风
    /// emoji 方块按当日训练次数：⬜ 0 / 🟦 1 / 🟩 2 / 🟧 3 / 🟥 ≥ 4
    /// 输出 5 行 × 7 day（最右下角 = 今天 · 从 30 天前补齐对齐周一）
    private static func recentTrainingCalendarMarkdown(sessions: [TrainingSession],
                                                        generatedAt: Date) -> String {
        guard !sessions.isEmpty else { return "" }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: generatedAt)
        // 算每日 session 计数（最近 30 天）
        var dayCounts: [Date: Int] = [:]
        for offset in 0..<30 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            dayCounts[d] = 0
        }
        for s in sessions {
            let day = cal.startOfDay(for: s.endedAt)
            if let _ = dayCounts[day] {
                dayCounts[day, default: 0] += 1
            }
        }
        // 排成 5 行 × 7 列（最近 35 天 · 不足补 ⬛ 占位）
        let cellEmoji: (Int) -> String = { n in
            switch n {
            case 0: return "⬜"
            case 1: return "🟦"
            case 2: return "🟩"
            case 3: return "🟧"
            default: return "🟥"
            }
        }
        var md = "## 最近 30 天训练习惯（emoji 日历）\n\n"
        md += "图例：⬜ 0 次 / 🟦 1 次 / 🟩 2 次 / 🟧 3 次 / 🟥 ≥ 4 次\n\n```\n"
        // 5 行 × 7 day · 第 5 行最右是今天 · 从 i=29 倒序往左排
        for row in 0..<5 {
            var line = ""
            for col in 0..<7 {
                let offset = (4 - row) * 7 + (6 - col)   // 0 = 今天 · 最大 34
                if offset >= 30 {
                    line += "⬛"
                } else if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                    line += cellEmoji(dayCounts[d] ?? 0)
                } else {
                    line += "⬛"
                }
            }
            md += line + "\n"
        }
        md += "```\n\n"
        let trainedDays = dayCounts.values.filter { $0 > 0 }.count
        md += "- 30 天内训练 \(trainedDays) 天 · 占比 \(trainedDays * 100 / 30)%\n\n"
        return md
    }

    /// v16.161 · 月报最强 session 引用 · trader 月度回顾正向反馈
    /// 找 totalScore 最高的 session（同分取最近）· 输出场景 + 形态 + 5 维 + pnl%
    /// 老 log 无 score 的 session 跳过 · 全空返回 ""
    private static func monthlyBestSessionMarkdown(sessions: [TrainingSession],
                                                    log: TrainingSessionLog) -> String {
        let scored = sessions.compactMap { s -> (TrainingSession, TrainingScore)? in
            guard let sc = log.score(for: s.id) else { return nil }
            return (s, sc)
        }
        guard !scored.isEmpty else { return "" }
        // 同分取最近的（endedAt 大）· 用 sort 简化
        let best = scored.sorted {
            if $0.1.totalScore != $1.1.totalScore { return $0.1.totalScore > $1.1.totalScore }
            return $0.0.endedAt > $1.0.endedAt
        }.first!
        let s = best.0
        let sc = best.1
        var md = "## 本月最强 session · \(sc.grade.emoji) \(sc.totalScore) 分\n\n"
        md += "- 场景：**\(s.scenarioName.isEmpty ? "未命名" : s.scenarioName)**"
        if let pat = s.scenarioPattern {
            md += " · \(pat.emoji) \(pat.displayName)"
        }
        md += "\n"
        let pnlPct = (s.pnlPercent as NSDecimalNumber).doubleValue
        md += String(format: "- 盈亏：%+.2f%% · 总分 %d · %@ 级\n", pnlPct, sc.totalScore, sc.grade.displayName)
        if let sub = sc.subScores {
            md += "- 5 维："
            md += sub.ordered.map { "\($0.dimension.emoji) \($0.score)" }.joined(separator: " / ")
            md += "\n"
        }
        md += "\n"
        return md
    }

    /// v16.153 · 月报基于 5 维平均最弱维度输出 5 步改进 plan（复用 v16.147 TrainingScorer.improvementPlan）
    /// 仅 v2 subScores 非 nil 的 session 参与 · 老 session 自动跳过返回 ""
    private static func monthlyImprovementPlanMarkdown(sessions: [TrainingSession],
                                                        log: TrainingSessionLog) -> String {
        let subs = sessions.compactMap { log.score(for: $0.id)?.subScores }
        guard !subs.isEmpty else { return "" }
        let n = subs.count
        let items: [(TrainingSubScores.Dimension, Int)] = [
            (.pnl, subs.map(\.pnl).reduce(0, +) / n),
            (.discipline, subs.map(\.discipline).reduce(0, +) / n),
            (.winRate, subs.map(\.winRate).reduce(0, +) / n),
            (.risk, subs.map(\.risk).reduce(0, +) / n),
            (.efficiency, subs.map(\.efficiency).reduce(0, +) / n),
        ]
        guard let weakest = items.min(by: { $0.1 < $1.1 }) else { return "" }
        let plan = TrainingScorer.improvementPlan(for: weakest.0, score: weakest.1)
        var md = "## 改进 plan · \(weakest.0.emoji) \(weakest.0.displayName)（均分 \(weakest.1)）\n\n"
        for (idx, step) in plan.enumerated() {
            md += "\(idx + 1). \(step)\n"
        }
        md += "\n"
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
    /// 多 pattern 命中时取最长 displayName（更精确 · "假突破" > "突破"）
    /// v16.47 · 改 public · 让 ReviewWindow setupPatternHeatmapView 复用同算法
    public static func matchPattern(setupName: String) -> TrainingScenarioPattern? {
        let needle = setupName.lowercased()
        let matched = TrainingScenarioPattern.allCases.filter {
            needle.contains($0.displayName.lowercased())
        }
        return matched.max(by: { $0.displayName.count < $1.displayName.count })
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
