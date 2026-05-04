// WP-53 v15.18 · Trade CSV 导出测试

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("TradeCSVExporter · Trade 流水导出（trader 操盘审计）")
struct TradeCSVExporterTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 30) -> Date {
        var c = DateComponents()
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeTrade(
        instrumentID: String = "rb2501",
        direction: Direction = .buy,
        offsetFlag: OffsetFlag = .open,
        price: Decimal = 3500,
        volume: Int = 1,
        commission: Decimal = 5,
        source: TradeSource = .wenhua,
        ref: String = "T001"
    ) -> Trade {
        Trade(
            tradeReference: ref,
            instrumentID: instrumentID,
            direction: direction,
            offsetFlag: offsetFlag,
            price: price,
            volume: volume,
            commission: commission,
            timestamp: utc(2026, 5, 3),
            source: source
        )
    }

    @Test("空输入 · 仅表头 + BOM")
    func emptyOutputsHeaderOnly() {
        let csv = TradeCSVExporter.export([])
        #expect(csv.hasPrefix("\u{FEFF}"))
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0].contains("成交时间"))
        #expect(lines[0].contains("开平"))
    }

    @Test("单条 · 字段顺序 + 中文方向 + 开平显示")
    func singleRow() {
        let t = makeTrade(direction: .buy, offsetFlag: .open, price: 3500)
        let csv = TradeCSVExporter.export([t])
        #expect(csv.contains("rb2501"))
        #expect(csv.contains(",买,"))
        #expect(csv.contains(",开仓,"))
        #expect(csv.contains("3500"))
    }

    @Test("方向 + 开平 4 组合 · 全文本输出")
    func allDirectionOffsetCombos() {
        let trades = [
            makeTrade(direction: .buy,  offsetFlag: .open),
            makeTrade(direction: .sell, offsetFlag: .closeToday),
            makeTrade(direction: .sell, offsetFlag: .closeYesterday),
            makeTrade(direction: .buy,  offsetFlag: .close)
        ]
        let csv = TradeCSVExporter.export(trades)
        #expect(csv.contains(",买,") && csv.contains(",卖,"))
        #expect(csv.contains("开仓") && csv.contains("平今")
                && csv.contains("平昨") && csv.contains("平仓"))
    }

    @Test("source 字段 · wenhua / generic / manual 全 raw")
    func sourceFieldRaw() {
        let trades = [
            makeTrade(source: .wenhua),
            makeTrade(source: .generic),
            makeTrade(source: .manual)
        ]
        let csv = TradeCSVExporter.export(trades)
        #expect(csv.contains("wenhua"))
        #expect(csv.contains("generic"))
        #expect(csv.contains("manual"))
    }

    @Test("RFC 4180 转义 · instrumentID 含逗号外加引号")
    func commaEscaped() {
        let t = makeTrade(instrumentID: "rb,abc")
        let csv = TradeCSVExporter.export([t])
        #expect(csv.contains("\"rb,abc\""))
    }

    @Test("UTF-8 BOM + CRLF · Excel 友好")
    func bomAndCrlf() {
        let csv = TradeCSVExporter.export([makeTrade()])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.hasSuffix("\r\n"))
    }
}
