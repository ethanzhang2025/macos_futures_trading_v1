// WP-54 v15.23 batch126 · 训练历史 markdown 月报告测试

import Testing
import Foundation
@testable import TradingCore

@Suite("TrainingMarkdownReport · WP-54 月报 markdown 导出")
struct TrainingMarkdownReportTests {

    private func makeSession(scenarioName: String = "test", pattern: TrainingScenarioPattern? = nil,
                             pnl: Double = 0) -> TrainingSession {
        TrainingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            initialBalance: 100_000,
            finalBalance: Decimal(100_000) + Decimal(pnl),
            trades: [], violations: [],
            scenarioName: scenarioName,
            scenarioPattern: pattern
        )
    }

    @Test("空 log → 仍生成有效 header + 暂无训练记录")
    func emptyLog() {
        let log = TrainingSessionLog()
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("# 训练月报"))
        #expect(md.contains("总训练次数：**0**"))
        #expect(md.contains("暂无训练记录"))
        #expect(md.contains("暂无形态记录"))
    }

    @Test("自定义 title 生效")
    func customTitle() {
        let md = TrainingMarkdownReport.generate(TrainingSessionLog(), title: "5 月战报")
        #expect(md.contains("# 5 月战报"))
    }

    @Test("3 个 session 生成 3 行表格")
    func threeRows() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(scenarioName: "震荡练习", pattern: .oscillation, pnl: 1000))
        log.addSession(makeSession(scenarioName: "趋势日", pattern: .uptrend, pnl: 5000))
        log.addSession(makeSession(scenarioName: "V 反", pattern: .vReversal, pnl: -500))
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("震荡练习"))
        #expect(md.contains("趋势日"))
        #expect(md.contains("V 反"))
        #expect(md.contains("〰️"))
        #expect(md.contains("📈"))
        #expect(md.contains("✓"))
    }

    @Test("形态分布只显示出现过的形态 · 计数正确")
    func patternDistribution() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(pattern: .oscillation))
        log.addSession(makeSession(pattern: .oscillation))
        log.addSession(makeSession(pattern: .uptrend))
        let md = TrainingMarkdownReport.generate(log)
        // 形态分布表里 oscillation 应该是 2 · uptrend 1
        let lines = md.components(separatedBy: "\n")
        let oscLine = lines.first { $0.contains("震荡") && $0.contains("|") }
        #expect(oscLine?.contains("| 2 |") == true || oscLine?.contains(" 2 ") == true)
        // downtrend 没出现 · 不应在分布里
        let dnLine = lines.first { $0.contains("下降趋势") && $0.contains("|") }
        #expect(dnLine == nil)
    }

    @Test("session 无 pattern → 暂无形态记录")
    func sessionsWithoutPattern() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(pattern: nil))
        log.addSession(makeSession(pattern: nil))
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("暂无形态记录"))
    }

    @Test("recentLimit 限制表格行数")
    func recentLimitRespected() {
        var log = TrainingSessionLog()
        for _ in 0..<10 {
            log.addSession(makeSession(scenarioName: "x", pattern: .oscillation))
        }
        let md = TrainingMarkdownReport.generate(log, recentLimit: 3)
        // 表格行（| date | ... |）不算 header 应该刚好 3
        let dataRows = md.components(separatedBy: "\n").filter {
            $0.hasPrefix("| 20") || $0.hasPrefix("| 19")
        }
        #expect(dataRows.count == 3)
    }

    @Test("markdown 含必要 sections")
    func sectionsPresent() {
        let md = TrainingMarkdownReport.generate(TrainingSessionLog())
        #expect(md.contains("## 概览"))
        #expect(md.contains("## 等级分布"))
        #expect(md.contains("## 形态分布"))
        #expect(md.contains("## 最近训练"))
    }

    @Test("filterPattern 仅含该形态 session（batch131）")
    func filterPatternApplied() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(scenarioName: "震荡 1", pattern: .oscillation))
        log.addSession(makeSession(scenarioName: "趋势 1", pattern: .uptrend))
        log.addSession(makeSession(scenarioName: "震荡 2", pattern: .oscillation))
        let md = TrainingMarkdownReport.generate(log, filterPattern: .oscillation)
        #expect(md.contains("震荡 1"))
        #expect(md.contains("震荡 2"))
        #expect(!md.contains("趋势 1"))
        #expect(md.contains("总训练次数：**2**"))
    }

    @Test("filterCutoff 仅含 startedAt >= cutoff（batch131）")
    func filterCutoffApplied() {
        var log = TrainingSessionLog()
        // 2 个老 session（startedAt = 0）+ 1 个新 session（startedAt = now）
        let oldDate = Date(timeIntervalSince1970: 0)
        let newDate = Date()
        log.addSession(TrainingSession(
            startedAt: oldDate, endedAt: oldDate.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 100_000,
            scenarioName: "古早", scenarioPattern: .uptrend))
        log.addSession(TrainingSession(
            startedAt: newDate.addingTimeInterval(-300), endedAt: newDate,
            initialBalance: 100_000, finalBalance: 105_000,
            scenarioName: "今日", scenarioPattern: .uptrend))
        // cutoff = 1 小时前 · 应仅含「今日」
        let cutoff = newDate.addingTimeInterval(-3600)
        let md = TrainingMarkdownReport.generate(log, filterCutoff: cutoff)
        #expect(md.contains("今日"))
        #expect(!md.contains("古早"))
        #expect(md.contains("总训练次数：**1**"))
    }

    @Test("filterLabel 出现在标题后缀（batch131）")
    func filterLabelInTitle() {
        let md = TrainingMarkdownReport.generate(
            TrainingSessionLog(), filterLabel: "本月 · 震荡")
        #expect(md.contains("（本月 · 震荡）"))
    }

    @Test("generateSingleSession · 含评分 + 形态 + 评语（batch133）")
    func singleSessionBasic() {
        let session = makeSession(scenarioName: "急涨练习", pattern: .uptrend, pnl: 5000)
        let scorer = TrainingScorer.score(session)
        let md = TrainingMarkdownReport.generateSingleSession(session, score: scorer)
        #expect(md.contains("# 训练分析"))
        #expect(md.contains("急涨练习"))
        #expect(md.contains("\(scorer.totalScore)"))
        #expect(md.contains("📈 上升趋势"))
        #expect(md.contains("评语"))
    }

    @Test("generateSingleSession · 无违规显示「严守纪律 ✅」")
    func singleSessionNoViolations() {
        let session = makeSession(scenarioName: "完美", pattern: .oscillation)
        let scorer = TrainingScorer.score(session)
        let md = TrainingMarkdownReport.generateSingleSession(session, score: scorer)
        #expect(md.contains("严守纪律"))
    }

    @Test("generateSingleSession · 自定义 title")
    func singleSessionCustomTitle() {
        let session = makeSession()
        let scorer = TrainingScorer.score(session)
        let md = TrainingMarkdownReport.generateSingleSession(session, score: scorer, title: "求师傅点评")
        #expect(md.contains("# 求师傅点评"))
    }

    @Test("v16.6 · generateSingleSession · subScores 非 nil 时含五维章节 + 改进建议")
    func singleSessionSubScores() {
        let session = makeSession(scenarioName: "v2 测试", pattern: .uptrend, pnl: 5000)
        let scorer = TrainingScorer.score(session)
        let md = TrainingMarkdownReport.generateSingleSession(session, score: scorer)
        #expect(scorer.subScores != nil)
        #expect(md.contains("## 五维细分"))
        #expect(md.contains("最弱"))
        #expect(md.contains("改进建议"))
    }

    @Test("v16.6 · generateSingleSession · subScores=nil 时不输出五维章节（兼容老 score）")
    func singleSessionNoSubScores() {
        let session = makeSession(scenarioName: "v1 老评分")
        let oldScore = TrainingScore(totalScore: 60, pnlScore: 30, disciplineScore: 30,
                                     grade: .C, summary: "old")
        let md = TrainingMarkdownReport.generateSingleSession(session, score: oldScore)
        #expect(!md.contains("## 五维细分"))
    }

    // MARK: - v16.15 · 月报 / 周报训练 annex

    @Test("v16.15 · generateMonthlyAnnex · 空 log → 提示文案 + 训练频率建议")
    func annex_emptyLog() {
        let md = TrainingMarkdownReport.generateMonthlyAnnex(
            TrainingSessionLog(),
            start: Date().addingTimeInterval(-86400 * 30),
            end: Date()
        )
        #expect(md.contains("## 训练评分关联"))
        #expect(md.contains("本区间无训练记录"))
    }

    @Test("v16.15 · generateMonthlyAnnex · 区间外 session 不计入")
    func annex_outOfRange() {
        var log = TrainingSessionLog()
        let now = Date()
        let oldDate = now.addingTimeInterval(-86400 * 60)   // 60 天前
        log.addSession(TrainingSession(
            startedAt: oldDate, endedAt: oldDate.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 110_000,
            scenarioPattern: .uptrend))
        let md = TrainingMarkdownReport.generateMonthlyAnnex(
            log,
            start: now.addingTimeInterval(-86400 * 7),
            end: now
        )
        #expect(md.contains("本区间无训练记录"))
    }

    // MARK: - v16.21 · setup ↔ pattern cross-reference

    @Test("v16.21 · matchPattern · 包含匹配（setup 名含 displayName）")
    func match_contains() {
        // 中文 setup 名含 pattern.displayName 子串
        #expect(TrainingMarkdownReport.matchPattern(setupName: "趋势顺势上升趋势") == .uptrend)
        #expect(TrainingMarkdownReport.matchPattern(setupName: "震荡反转") == .oscillation)
        #expect(TrainingMarkdownReport.matchPattern(setupName: "突破后回踩") == .breakout)
        // 不匹配
        #expect(TrainingMarkdownReport.matchPattern(setupName: "完全不相关") == nil)
    }

    @Test("v16.21 · matchPattern · 多 pattern 命中取最长 displayName")
    func match_longest() {
        // "假突破" 同时含 "突破" 和 "假突破" · 应取后者（更精确）
        #expect(TrainingMarkdownReport.matchPattern(setupName: "假突破回踩") == .fakeBreakout)
    }

    @Test("v16.21 · crossAdvice · 4 象限")
    func crossAdvice_quadrants() {
        // (实盘强 0.6 / 训练强 80) → 双强
        #expect(TrainingMarkdownReport.crossAdvice(realWinRate: 0.6, trainAvg: 80, trainCount: 5)
                .contains("双强"))
        // (实盘强 / 训练弱) → 抽空补练
        #expect(TrainingMarkdownReport.crossAdvice(realWinRate: 0.6, trainAvg: 50, trainCount: 5)
                .contains("抽空补练"))
        // (实盘弱 / 训练强) → 执行偏差
        #expect(TrainingMarkdownReport.crossAdvice(realWinRate: 0.4, trainAvg: 80, trainCount: 5)
                .contains("执行偏差"))
        // (实盘弱 / 训练弱) → 双弱
        #expect(TrainingMarkdownReport.crossAdvice(realWinRate: 0.4, trainAvg: 50, trainCount: 5)
                .contains("双弱"))
        // 无训练
        #expect(TrainingMarkdownReport.crossAdvice(realWinRate: 0.4, trainAvg: 0, trainCount: 0)
                .contains("无训练记录"))
    }

    @Test("v16.21 · generateSetupPatternCrossReference · 空 setup → 提示文案")
    func crossRef_emptySetups() {
        let md = TrainingMarkdownReport.generateSetupPatternCrossReference(
            TrainingSessionLog(),
            setups: [],
            start: Date().addingTimeInterval(-86400 * 30),
            end: Date()
        )
        #expect(md.contains("交叉分析"))
        #expect(md.contains("无具名 setup"))
    }

    @Test("v16.21 · generateSetupPatternCrossReference · 含表格 + 双弱建议")
    func crossRef_table() {
        var log = TrainingSessionLog()
        let now = Date()
        // 训练 uptrend × 1 低分（双弱触发）
        log.addSession(TrainingSession(
            startedAt: now.addingTimeInterval(-86400),
            endedAt: now.addingTimeInterval(-86400 + 3600),
            initialBalance: 100_000, finalBalance: 95_000,
            violations: [
                DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                    occurredAt: now, severity: .error, message: "x"),
                DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                    occurredAt: now, severity: .error, message: "y"),
            ],
            scenarioPattern: .uptrend))
        let md = TrainingMarkdownReport.generateSetupPatternCrossReference(
            log,
            setups: [
                TrainingMarkdownReport.SetupSlice(setupName: "上升趋势", tradeCount: 10, winRate: 0.4),
            ],
            start: now.addingTimeInterval(-86400 * 7),
            end: now
        )
        #expect(md.contains("上升趋势"))
        #expect(md.contains("📈"))   // matched pattern emoji
        #expect(md.contains("双弱"))  // 实盘 0.4 + 训练 < 70
    }

    @Test("v16.21 · generateSetupPatternCrossReference · 跳过 (未标) 桶")
    func crossRef_skipUnlabeled() {
        let md = TrainingMarkdownReport.generateSetupPatternCrossReference(
            TrainingSessionLog(),
            setups: [
                TrainingMarkdownReport.SetupSlice(setupName: "(未标)", tradeCount: 5, winRate: 0.5),
            ],
            start: Date().addingTimeInterval(-86400 * 7),
            end: Date()
        )
        #expect(md.contains("无具名 setup"))   // (未标) 被过滤
    }

    @Test("v16.15 · generateMonthlyAnnex · 多 pattern 表格 + 弱项加练建议")
    func annex_patternTable() {
        var log = TrainingSessionLog()
        let now = Date()
        // uptrend × 2 (高分) + oscillation × 1 (低分)
        for _ in 0..<2 {
            log.addSession(TrainingSession(
                startedAt: now.addingTimeInterval(-86400),
                endedAt: now.addingTimeInterval(-86400 + 3600),
                initialBalance: 100_000, finalBalance: 110_000,   // total = 100
                scenarioPattern: .uptrend))
        }
        log.addSession(TrainingSession(
            startedAt: now.addingTimeInterval(-86400 * 2),
            endedAt: now.addingTimeInterval(-86400 * 2 + 3600),
            initialBalance: 100_000, finalBalance: 95_000,   // total < 60
            violations: [
                DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                    occurredAt: now, severity: .error, message: "x"),
                DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                    occurredAt: now, severity: .error, message: "y"),
            ],
            scenarioPattern: .oscillation))
        let md = TrainingMarkdownReport.generateMonthlyAnnex(
            log,
            start: now.addingTimeInterval(-86400 * 7),
            end: now
        )
        #expect(md.contains("📈 上升趋势"))
        #expect(md.contains("〰️ 震荡"))
        #expect(md.contains("🏆 强项"))   // uptrend 100 分
        #expect(md.contains("薄弱"))      // oscillation < 60
    }

    // MARK: - v15.23 batch197 · 周报

    @Test("batch197 · 周报标题为「训练周报」")
    func weeklyTitle() {
        let md = TrainingMarkdownReport.generateWeekly(TrainingSessionLog())
        #expect(md.contains("# 训练周报"))
    }

    @Test("batch197 · 周报仅含最近 7 天 startedAt session")
    func weeklyOnlyRecent7Days() {
        var log = TrainingSessionLog()
        let now = Date()
        // 30 天前的旧 session（应被排除）
        let oldDate = now.addingTimeInterval(-30 * 86_400)
        log.addSession(TrainingSession(
            startedAt: oldDate, endedAt: oldDate.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 100_000,
            scenarioName: "古早", scenarioPattern: .uptrend))
        // 3 天前 session（应保留）
        let recentDate = now.addingTimeInterval(-3 * 86_400)
        log.addSession(TrainingSession(
            startedAt: recentDate, endedAt: recentDate.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 102_000,
            scenarioName: "本周练", scenarioPattern: .uptrend))
        let md = TrainingMarkdownReport.generateWeekly(log, generatedAt: now)
        #expect(md.contains("本周练"))
        #expect(!md.contains("古早"))
        #expect(md.contains("总训练次数：**1**"))
    }

    // MARK: - v16.63 · 五维平均章节

    @Test("v16.63 · 含 v2 subScores 的 session 输出五维平均章节")
    func fiveDimAverageSection() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(scenarioName: "s1", pnl: 5000))   // 评分含 subScores
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("五维平均"))
        #expect(md.contains("v2 评分"))
        #expect(md.contains("最弱"))   // 必有最弱标记
    }

    @Test("v16.63 · 空 log 不输出五维平均章节")
    func fiveDimAverageEmptyLog() {
        let md = TrainingMarkdownReport.generate(TrainingSessionLog())
        #expect(!md.contains("五维平均"))
    }

    // MARK: - v16.153 · 月报最弱维度 5 步改进 plan 章节

    @Test("v16.153 · 含 v2 subScores 的 session 输出改进 plan 章节（含 5 步）")
    func monthlyImprovementPlanSection() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(scenarioName: "s1", pnl: -5000))   // 大亏 → 触发 risk/pnl 弱
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("改进 plan"))
        #expect(md.contains("均分"))
        // 5 步全部在 markdown 里（按 1./2./3./4./5. numbered）
        for n in 1...5 {
            #expect(md.contains("\(n). "))
        }
    }

    @Test("v16.153 · 空 log 不输出改进 plan 章节（无 v2 subScores）")
    func monthlyImprovementPlanEmptyLog() {
        let md = TrainingMarkdownReport.generate(TrainingSessionLog())
        #expect(!md.contains("改进 plan"))
    }

    // MARK: - v16.86/91 · streak overview

    @Test("v16.91 · 当前 ≥ 历史最长 → 新纪录提示")
    func streakNewRecord() {
        var log = TrainingSessionLog()
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        // 连续 3 天（今天 + 昨天 + 前天）· 历史最长 = 3 · 当前 = 3
        for offset in 0...2 {
            let d = cal.date(byAdding: .day, value: -offset, to: now)!
            log.addSession(TrainingSession(
                startedAt: d, endedAt: d.addingTimeInterval(60),
                initialBalance: 100_000, finalBalance: 100_000))
        }
        let md = TrainingMarkdownReport.generate(log, generatedAt: now)
        #expect(md.contains("当前连训"))
        #expect(md.contains("新纪录"))
    }

    @Test("v16.91 · 当前已中断但历史 ≥ 3 天 → 重启提示")
    func streakInterruptedShowsHistory() {
        var log = TrainingSessionLog()
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        // 5 天前-7 天前 = 历史 3 连训 · 今天/昨天 = 0 · 当前断
        for offset in 5...7 {
            let d = cal.date(byAdding: .day, value: -offset, to: now)!
            log.addSession(TrainingSession(
                startedAt: d, endedAt: d.addingTimeInterval(60),
                initialBalance: 100_000, finalBalance: 100_000))
        }
        let md = TrainingMarkdownReport.generate(log, generatedAt: now)
        #expect(md.contains("历史最长连训"))
        #expect(md.contains("重新开始"))
    }

    // MARK: - v16.118 · 时长分布章节

    @Test("v16.118 · 含 session → 输出时长分布 3 段")
    func durationDistributionSection() {
        var log = TrainingSessionLog()
        // 3 个不同时长 session
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        log.addSession(TrainingSession(   // 10 分（短）
            startedAt: t0, endedAt: t0.addingTimeInterval(600),
            initialBalance: 100_000, finalBalance: 100_000))
        log.addSession(TrainingSession(   // 20 分（中）
            startedAt: t0, endedAt: t0.addingTimeInterval(1200),
            initialBalance: 100_000, finalBalance: 100_000))
        log.addSession(TrainingSession(   // 60 分（长）
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 100_000))
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("训练时长分布"))
        #expect(md.contains("🏃 短"))
        #expect(md.contains("🎯 中"))
        #expect(md.contains("🧘 长"))
    }

    @Test("v16.118 · 空 log 不输出时长分布章节")
    func durationDistributionEmptyLog() {
        let md = TrainingMarkdownReport.generate(TrainingSessionLog())
        #expect(!md.contains("训练时长分布"))
    }

    @Test("v16.118 · 过半短时 → 建议 ≥ 15 分专注")
    func durationSuggestionShortHeavy() {
        var log = TrainingSessionLog()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 3 个 5 分钟（短）+ 1 个 20 分钟（中）→ 75% 短
        for _ in 0..<3 {
            log.addSession(TrainingSession(
                startedAt: t0, endedAt: t0.addingTimeInterval(300),
                initialBalance: 100_000, finalBalance: 100_000))
        }
        log.addSession(TrainingSession(
            startedAt: t0, endedAt: t0.addingTimeInterval(1200),
            initialBalance: 100_000, finalBalance: 100_000))
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("可能过于试探"))
        #expect(md.contains("建议至少 15 分钟"))
    }

    @Test("v16.118 · 过半长时 → 建议拆短")
    func durationSuggestionLongHeavy() {
        var log = TrainingSessionLog()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // 3 个 60 分钟（长）+ 1 个 20 分钟（中）→ 75% 长
        for _ in 0..<3 {
            log.addSession(TrainingSession(
                startedAt: t0, endedAt: t0.addingTimeInterval(3600),
                initialBalance: 100_000, finalBalance: 100_000))
        }
        log.addSession(TrainingSession(
            startedAt: t0, endedAt: t0.addingTimeInterval(1200),
            initialBalance: 100_000, finalBalance: 100_000))
        let md = TrainingMarkdownReport.generate(log)
        #expect(md.contains("单次过长可能效率递减"))
        #expect(md.contains("建议拆短"))
    }
}
