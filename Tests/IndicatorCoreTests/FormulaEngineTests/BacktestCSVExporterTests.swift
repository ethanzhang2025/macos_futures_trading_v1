// v17.49 D5 v2 · BacktestHistoryCSVExporter 单测

import Testing
import Foundation
@testable import IndicatorCore

private func makeEntry(pnl: Double, signalLine: String = "BUY", trajectory: String = "random",
                        commission: Decimal = 0, slippage: Decimal = 0,
                        allowShort: Bool = false) -> BacktestHistoryEntry {
    BacktestHistoryEntry(
        id: UUID(), createdAt: Date(timeIntervalSince1970: 1746979200),  // 2026-05-11 16:00 UTC
        signalLineName: signalLine,
        trajectoryRaw: trajectory,
        barCount: 200, initialEquity: 100_000,
        endingPnL: Decimal(pnl), maxDrawdown: 50,
        sharpe: 0.85, sortino: 1.20, calmar: 4.50,
        winRate: 0.55, expectancy: 30, tradeCount: 10,
        commission: commission, slippage: slippage, allowShort: allowShort
    )
}

@Suite("BacktestHistoryCSVExporter · v17.49 D5 v2 CSV 导出")
struct BacktestHistoryCSVExporterTests {

    @Test("空 entries · 仅返回表头 + BOM")
    func emptyEntries() {
        let csv = BacktestHistoryCSVExporter.export([])
        #expect(csv.hasPrefix("\u{FEFF}"))   // UTF-8 BOM
        #expect(csv.contains("保存时间"))
        #expect(csv.contains("Sortino"))
        #expect(csv.contains("Calmar"))
        #expect(csv.contains("commission"))
        #expect(csv.contains("allowShort"))
    }

    @Test("header 16 字段（含 Sortino/Calmar/3 个成本）")
    func headerStructure() {
        #expect(BacktestHistoryCSVExporter.header.count == 16)
        #expect(BacktestHistoryCSVExporter.header.first == "保存时间")
        #expect(BacktestHistoryCSVExporter.header.last == "allowShort")
    }

    @Test("单条 entry · row 含全部 16 字段")
    func singleEntry() {
        let csv = BacktestHistoryCSVExporter.export([
            makeEntry(pnl: 1234.5, commission: 3, slippage: 1, allowShort: true)
        ])
        // 含 BOM + 表头 + 1 行 + 末尾换行
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)   // header + row + 末尾空行
        // row 必含关键字段
        #expect(csv.contains("BUY"))
        #expect(csv.contains("随机游走"))
        #expect(csv.contains("1234.5"))
        #expect(csv.contains("1.20"))   // sortino
        #expect(csv.contains("4.50"))   // calmar
        #expect(csv.contains(",3,"))    // commission
        #expect(csv.contains(",1,"))    // slippage
        #expect(csv.contains(",1\r\n")) // allowShort=true → "1"
    }

    @Test("CRLF 行尾 · 末尾换行 · BOM 头")
    func formatConformance() {
        let csv = BacktestHistoryCSVExporter.export([makeEntry(pnl: 100)])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.hasSuffix("\r\n"))
        #expect(csv.contains("\r\n"))
    }

    @Test("trajectory 翻译 · raw 不在 map 中 → 保留原值（容错）")
    func trajectoryUnknown() {
        let csv = BacktestHistoryCSVExporter.export([
            makeEntry(pnl: 100, trajectory: "unknown_mode")
        ])
        #expect(csv.contains("unknown_mode"))
    }

    @Test("signalLineName 含逗号 · 自动加引号 + 转义")
    func escapeComma() {
        let csv = BacktestHistoryCSVExporter.export([
            makeEntry(pnl: 100, signalLine: "BUY,SELL")
        ])
        #expect(csv.contains("\"BUY,SELL\""))
    }

    @Test("exportData · UTF-8 编码 · BOM 0xEF 0xBB 0xBF 开头")
    func exportDataBytes() {
        let data = BacktestHistoryCSVExporter.exportData([makeEntry(pnl: 100)])
        let bytes = [UInt8](data)
        #expect(bytes.count >= 3)
        #expect(bytes[0] == 0xEF)
        #expect(bytes[1] == 0xBB)
        #expect(bytes[2] == 0xBF)
    }

    @Test("多条 entry · 行数对齐")
    func multipleEntries() {
        let entries = (0..<5).map { i in
            makeEntry(pnl: Double(i * 100))
        }
        let csv = BacktestHistoryCSVExporter.export(entries)
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: false)
        // header + 5 entries + 末尾空 = 7
        #expect(lines.count == 7)
    }
}
