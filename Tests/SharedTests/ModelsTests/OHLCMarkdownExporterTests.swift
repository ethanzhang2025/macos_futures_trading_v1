// v15.21 batch87 · OHLCMarkdownExporter 测试

import Testing
import Foundation
@testable import Shared

@Suite("OHLCMarkdownExporter · v15.21 batch87")
struct OHLCMarkdownExporterTests {

    private func makeBar(open: Decimal, high: Decimal, low: Decimal, close: Decimal,
                         volume: Int = 100, oi: Decimal = 0,
                         time: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> KLine {
        KLine(instrumentID: "rb2510", period: .minute1, openTime: time,
              open: open, high: high, low: low, close: close,
              volume: volume, openInterest: oi, turnover: 0)
    }

    @Test("空数组返回空字符串")
    func empty() {
        #expect(OHLCMarkdownExporter.render([]) == "")
    }

    @Test("基本表格结构 · header + 分隔行 + 数据行")
    func basicStructure() {
        let bar = makeBar(open: 100, high: 110, low: 95, close: 105)
        let md = OHLCMarkdownExporter.render([bar])
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].contains("时间"))
        #expect(lines[0].contains("开"))
        #expect(lines[0].contains("涨跌%"))
        #expect(lines[1].contains("---"))
        #expect(lines[2].contains("100"))
        #expect(lines[2].contains("110"))
        #expect(lines[2].contains("95"))
        #expect(lines[2].contains("105"))
    }

    @Test("涨跌% 正值带 + 号 · 2 位小数")
    func changePercentPositive() {
        let s = OHLCMarkdownExporter.formatChangePercent(open: 100, close: 105)
        #expect(s == "+5.00%")
    }

    @Test("涨跌% 负值不重复负号")
    func changePercentNegative() {
        let s = OHLCMarkdownExporter.formatChangePercent(open: 100, close: 95)
        #expect(s == "-5.00%")
    }

    @Test("涨跌% open=0 fallback —")
    func changePercentZeroOpen() {
        let s = OHLCMarkdownExporter.formatChangePercent(open: 0, close: 100)
        #expect(s == "—")
    }

    @Test("涨跌% 平盘显示 0.00%")
    func changePercentFlat() {
        let s = OHLCMarkdownExporter.formatChangePercent(open: 100, close: 100)
        #expect(s == "0.00%")
    }

    @Test("多根 K 线全部展现 + 持仓量列存在")
    func multipleBars() {
        let bars = [
            makeBar(open: 100, high: 105, low: 99, close: 103, oi: Decimal(12345)),
            makeBar(open: 103, high: 110, low: 102, close: 108, oi: Decimal(13000)),
        ]
        let md = OHLCMarkdownExporter.render(bars)
        let lines = md.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)  // header + sep + 2 data rows
        #expect(md.contains("12345"))
        #expect(md.contains("13000"))
    }
}
