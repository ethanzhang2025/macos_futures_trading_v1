// WP-50 v15.18 · ClosedPosition CSV 导出测试

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("ClosedPositionCSVExporter · CSV 导出（trader 报税 / 复盘归档）")
struct ClosedPositionCSVExporterTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 14, _ mi: Int = 30) -> Date {
        var c = DateComponents()
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func position(
        instrumentID: String = "rb2501",
        side: PositionSide = .long,
        openPrice: Decimal = 3500,
        closePrice: Decimal = 3600,
        volume: Int = 1,
        pnl: Decimal = 100,
        commission: Decimal = 5,
        openOffsetMin: Int = 60,
        closeAt: Date? = nil
    ) -> ClosedPosition {
        let close = closeAt ?? utc(2026, 5, 3)
        let open = close.addingTimeInterval(TimeInterval(-openOffsetMin * 60))
        return ClosedPosition(
            instrumentID: instrumentID, side: side,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: open, closeTime: close,
            openPrice: openPrice, closePrice: closePrice,
            volume: volume,
            realizedPnL: pnl, totalCommission: commission
        )
    }

    @Test("空输入 · 仅表头 + BOM + CRLF")
    func emptyOutputsHeaderOnly() {
        let csv = ClosedPositionCSVExporter.export([])
        #expect(csv.hasPrefix("\u{FEFF}"))
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0].contains("平仓时间"))
        #expect(lines[0].contains("持仓分钟"))
    }

    @Test("单条 · 字段顺序 + 中文方向 + 时区上海")
    func singleRowFields() {
        let p = position(side: .long, openPrice: 3500, closePrice: 3600, volume: 2, pnl: 200)
        let csv = ClosedPositionCSVExporter.export([p])
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.count >= 2)
        let row = lines[1]
        #expect(row.contains("rb2501"))
        #expect(row.contains("多"))
        #expect(row.contains("3500"))
        #expect(row.contains("3600"))
        #expect(row.contains(",2,"))    // volume
        #expect(row.contains("200"))
        #expect(row.contains("60"))     // 持仓分钟
    }

    @Test("空头方向显示「空」")
    func shortSide() {
        let p = position(side: .short)
        let csv = ClosedPositionCSVExporter.export([p])
        #expect(csv.contains(",空,"))
    }

    @Test("RFC 4180 转义 · instrumentID 含逗号 · 外加引号")
    func commaInFieldEscaped() {
        let p = position(instrumentID: "rb,2501")
        let csv = ClosedPositionCSVExporter.export([p])
        #expect(csv.contains("\"rb,2501\""))
    }

    @Test("RFC 4180 转义 · 含双引号内部双写")
    func doubleQuoteEscaped() {
        let p = position(instrumentID: "rb\"abc")
        let csv = ClosedPositionCSVExporter.export([p])
        // 外加引号 · 内部 "" 双写
        #expect(csv.contains("\"rb\"\"abc\""))
    }

    @Test("Decimal 精度保留 · stringValue 不截断")
    func decimalPrecisionPreserved() {
        let p = position(openPrice: Decimal(string: "3500.1234")!, closePrice: Decimal(string: "3600.5678")!)
        let csv = ClosedPositionCSVExporter.export([p])
        #expect(csv.contains("3500.1234"))
        #expect(csv.contains("3600.5678"))
    }

    @Test("UTF-8 BOM + CRLF · Excel 识别中文友好")
    func bomAndCrlf() {
        let csv = ClosedPositionCSVExporter.export([position()])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.hasSuffix("\r\n"))
    }

    @Test("exportData · UTF-8 编码非空")
    func exportDataNonEmpty() {
        let data = ClosedPositionCSVExporter.exportData([position()])
        #expect(data.count > 50)
        // 验证 BOM 字节序列 EF BB BF
        #expect(data[0] == 0xEF)
        #expect(data[1] == 0xBB)
        #expect(data[2] == 0xBF)
    }
}
