// v16.24 · 训练 session CSV 导入测试

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("TrainingSessionCSVImporter · v16.24 训练历史 CSV 导入")
struct TrainingSessionCSVImporterTests {

    @Test("空字符串 / 仅 header → 空数组（不抛）")
    func empty() {
        #expect(TrainingSessionCSVImporter.parse("").isEmpty)
        let onlyHeader = "训练结束时间,时长(分),场景,形态,初始资金,最终资金,盈亏率%,总分,等级,盈亏子分,纪律子分,维度_盈亏,维度_纪律,维度_胜率,维度_风险,维度_效率,最弱维度,违规数,警告数,交易笔数\r\n"
            #expect(TrainingSessionCSVImporter.parse(onlyHeader).isEmpty)
    }

    @Test("export → import round-trip · session 数据保留")
    func roundTrip() {
        var log = TrainingSessionLog()
        let t0 = Date(timeIntervalSince1970: 1746360000)
        log.addSession(TrainingSession(
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 110_000,
            violations: [
                DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                    occurredAt: t0, severity: .error, message: "x"),
                DisciplineViolation(ruleID: UUID(), ruleKind: .maxHoldingMinutes,
                                    occurredAt: t0, severity: .warning, message: "y"),
            ],
            scenarioName: "测试场景",
            scenarioPattern: .uptrend))
        let csv = TrainingSessionCSVExporter.export(log)
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 1)
        let s = parsed[0]
        #expect(s.scenarioName == "测试场景")
        #expect(s.scenarioPattern == .uptrend)
        #expect(s.initialBalance == 100_000)
        #expect(s.finalBalance == 110_000)
        #expect(s.violations.filter { $0.severity == .error }.count == 1)
        #expect(s.violations.filter { $0.severity == .warning }.count == 1)
    }

    @Test("含 BOM 前缀 · 容忍剥除")
    func bomTolerance() {
        let header = "训练结束时间,时长(分),场景,形态,初始资金,最终资金,违规数,警告数,交易笔数"
        let row = "2026-05-09 10:00:00,60,场景A,上升趋势,100000,110000,0,0,0"
        let csv = "\u{FEFF}\(header)\r\n\(row)\r\n"
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 1)
        #expect(parsed[0].scenarioName == "场景A")
    }

    @Test("LF 单分隔符（非 CRLF）· 容忍")
    func lfOnly() {
        let header = "训练结束时间,时长(分),场景,形态,初始资金,最终资金"
        let row1 = "2026-05-09 10:00:00,30,A,震荡,100000,99000"
        let row2 = "2026-05-09 11:00:00,45,B,突破,100000,105000"
        let csv = "\(header)\n\(row1)\n\(row2)\n"
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 2)
    }

    @Test("含逗号引号字段 · 转义还原")
    func escape() {
        let header = "训练结束时间,时长(分),场景,形态,初始资金,最终资金"
        let row = #"2026-05-09 10:00:00,60,"含,逗号 ""引号""",上升趋势,100000,110000"#
        let csv = "\(header)\r\n\(row)\r\n"
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 1)
        #expect(parsed[0].scenarioName == "含,逗号 \"引号\"")
    }

    @Test("无效行（字段不全 / 无法解析）· 跳过不抛")
    func invalidRow() {
        let header = "训练结束时间,时长(分),场景,形态,初始资金,最终资金"
        let validRow = "2026-05-09 10:00:00,60,A,上升趋势,100000,110000"
        let badDate = "INVALID,60,B,震荡,100000,99000"
        let badNumber = "2026-05-09 11:00:00,xx,C,震荡,abc,99000"
        let csv = "\(header)\r\n\(validRow)\r\n\(badDate)\r\n\(badNumber)\r\n"
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 1)
        #expect(parsed[0].scenarioName == "A")
    }

    @Test("header 缺关键列 → 整体返回空（保护性）")
    func missingHeader() {
        let csv = "随便,column\r\nfoo,bar\r\n"
        #expect(TrainingSessionCSVImporter.parse(csv).isEmpty)
    }

    @Test("形态空字段 → scenarioPattern = nil（不抛）")
    func emptyPattern() {
        let header = "训练结束时间,时长(分),场景,形态,初始资金,最终资金"
        let row = "2026-05-09 10:00:00,60,A,,100000,110000"
        let csv = "\(header)\r\n\(row)\r\n"
        let parsed = TrainingSessionCSVImporter.parse(csv)
        #expect(parsed.count == 1)
        #expect(parsed[0].scenarioPattern == nil)
    }

    @Test("matchPatternByName · 中文 displayName → enum")
    func matchPatternByName() {
        #expect(TrainingSessionCSVImporter.matchPatternByName("上升趋势") == .uptrend)
        #expect(TrainingSessionCSVImporter.matchPatternByName("震荡") == .oscillation)
        #expect(TrainingSessionCSVImporter.matchPatternByName("假突破") == .fakeBreakout)
        #expect(TrainingSessionCSVImporter.matchPatternByName("不存在") == nil)
        #expect(TrainingSessionCSVImporter.matchPatternByName("") == nil)
    }
}
