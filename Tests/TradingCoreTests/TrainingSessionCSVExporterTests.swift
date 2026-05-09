// v16.20 · 训练 session CSV 导出测试

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("TrainingSessionCSVExporter · v16.20 训练历史 CSV")
struct TrainingSessionCSVExporterTests {

    private let t0 = Date(timeIntervalSince1970: 1746360000)

    private func makeSession(initial: Decimal = 100_000,
                              final: Decimal = 110_000,
                              pattern: TrainingScenarioPattern? = .uptrend,
                              scenarioName: String = "测试",
                              errors: Int = 0,
                              warnings: Int = 0) -> TrainingSession {
        var violations: [DisciplineViolation] = []
        for i in 0..<errors {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .stopLossPercent, occurredAt: t0,
                severity: .error, message: "e\(i)"))
        }
        for i in 0..<warnings {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .maxHoldingMinutes, occurredAt: t0,
                severity: .warning, message: "w\(i)"))
        }
        return TrainingSession(startedAt: t0, endedAt: t0.addingTimeInterval(3600),
                               initialBalance: initial, finalBalance: final,
                               violations: violations,
                               scenarioName: scenarioName,
                               scenarioPattern: pattern)
    }

    @Test("空 log → 仅 header + BOM + CRLF")
    func emptyLog() {
        let csv = TrainingSessionCSVExporter.export(TrainingSessionLog())
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.contains("训练结束时间"))
        #expect(csv.contains("总分"))
        #expect(csv.contains("最弱维度"))
        // 仅一行 header + 末尾 \r\n
        let dataLines = csv.split(separator: "\r\n", omittingEmptySubsequences: false)
        #expect(dataLines.count == 2)   // header 行 + 末尾空字符串
    }

    @Test("含 session · 含 v2 五维 + 时间降序")
    func withSessions() {
        var log = TrainingSessionLog()
        let earlier = TrainingSession(
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 100_000,   // 0% → pnl 30 / disc 50 / total 50 → D
            scenarioName: "早 session",
            scenarioPattern: .oscillation
        )
        let later = TrainingSession(
            startedAt: t0.addingTimeInterval(86400),
            endedAt: t0.addingTimeInterval(86400 + 3600),
            initialBalance: 100_000, finalBalance: 110_000,   // +10% → pnl 50 / disc 50 / total 100 → S
            scenarioName: "晚 session",
            scenarioPattern: .uptrend
        )
        log.addSession(earlier)
        log.addSession(later)
        let csv = TrainingSessionCSVExporter.export(log)
        // 时间降序 · 晚 session 在前
        let lines = csv.split(separator: "\r\n").map(String.init)
        #expect(lines.count == 3)   // header + 2 session
        #expect(lines[1].contains("晚 session"))   // newer first
        #expect(lines[2].contains("早 session"))
        // v2 五维写出
        #expect(csv.contains("100"))   // total = 100 for later
        #expect(csv.contains("上升趋势"))
        #expect(csv.contains("震荡"))
    }

    @Test("escape · 含逗号/引号/换行 → 加引号转义")
    func escapeFields() {
        var log = TrainingSessionLog()
        let s = TrainingSession(
            startedAt: t0, endedAt: t0.addingTimeInterval(3600),
            initialBalance: 100_000, finalBalance: 105_000,
            scenarioName: "含,逗号 \"引号\"",
            scenarioPattern: .uptrend
        )
        log.addSession(s)
        let csv = TrainingSessionCSVExporter.export(log)
        #expect(csv.contains(#""含,逗号 ""引号""""#))
    }

    @Test("无 pattern session · 形态列空")
    func noPattern() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(pattern: nil))
        let csv = TrainingSessionCSVExporter.export(log)
        // header + 1 行 data + 空末行
        let lines = csv.split(separator: "\r\n").map(String.init)
        #expect(lines.count == 2)
        // 形态列为空（,, 空字段）· 检查不抛 + 不写"nil"
        #expect(!csv.contains("nil"))
    }

    @Test("exportData · UTF-8 编码 · 含 BOM")
    func exportData() {
        var log = TrainingSessionLog()
        log.addSession(makeSession())
        let data = TrainingSessionCSVExporter.exportData(log)
        #expect(data.count > 0)
        // 前 3 字节应是 UTF-8 BOM (EF BB BF)
        #expect(data[0] == 0xEF)
        #expect(data[1] == 0xBB)
        #expect(data[2] == 0xBF)
    }
}
