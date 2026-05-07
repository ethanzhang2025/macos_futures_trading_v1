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
}
