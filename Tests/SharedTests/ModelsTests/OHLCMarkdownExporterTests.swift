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

    @Test("v15.21 batch124 · 涨跌% 极端值（接近 0 不丢小数 · 大值不溢出）")
    func changePercentExtremes() {
        // 微小变化（< 0.01%）显示 +0.00%
        let tiny = OHLCMarkdownExporter.formatChangePercent(open: 100, close: Decimal(string: "100.001")!)
        #expect(tiny.starts(with: "+0.00"))
        // 跌停（-10%）
        let limitDown = OHLCMarkdownExporter.formatChangePercent(open: 100, close: 90)
        #expect(limitDown == "-10.00%")
        // 涨停（+10%）
        let limitUp = OHLCMarkdownExporter.formatChangePercent(open: 100, close: 110)
        #expect(limitUp == "+10.00%")
    }

    @Test("v15.21 batch124 · 自定义 dateFormat 参数生效")
    func customDateFormat() {
        let bar = makeBar(open: 100, high: 110, low: 95, close: 105)
        let mdDefault = OHLCMarkdownExporter.render([bar])
        let mdShort = OHLCMarkdownExporter.render([bar], dateFormat: "HH:mm")
        // 默认 "yyyy-MM-dd HH:mm" 数据行含 "20" 前缀（年份开头）
        let defaultDataRow = mdDefault.split(separator: "\n").last.map(String.init) ?? ""
        let shortDataRow = mdShort.split(separator: "\n").last.map(String.init) ?? ""
        #expect(defaultDataRow.contains("20"))           // yyyy-MM-dd 年份起首
        #expect(!shortDataRow.contains("20"))            // HH:mm 仅时分（24h 不会有 20: · 测试用 makeBar 时间不在 20 点）
        #expect(shortDataRow.contains(":"))              // 时分冒号
    }

    @Test("v17.185 · renderWithAnnotations · 空 annotations · 形态列为空")
    func annotationsEmpty() {
        let bar = makeBar(open: 100, high: 110, low: 95, close: 105)
        let md = OHLCMarkdownExporter.renderWithAnnotations([bar], annotations: [:])
        let lines = md.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].contains("形态"))
        // 数据行末尾 "| |"（空形态列）
        #expect(lines[2].hasSuffix("|  |"))
    }

    @Test("v17.185 · renderWithAnnotations · 命中形态写入对应 # 行")
    func annotationsPopulated() {
        let bars = [
            makeBar(open: 100, high: 110, low: 95, close: 105),
            makeBar(open: 105, high: 112, low: 103, close: 108),
            makeBar(open: 108, high: 115, low: 106, close: 110)
        ]
        let md = OHLCMarkdownExporter.renderWithAnnotations(
            bars,
            annotations: [1: "双顶", 2: "头肩顶;矩形"]
        )
        let lines = md.split(separator: "\n").map(String.init)
        #expect(lines[2].contains("| 0 |"))
        #expect(lines[2].hasSuffix("|  |"))         // 第 0 行无形态
        #expect(lines[3].contains("| 1 |"))
        #expect(lines[3].contains("双顶"))
        #expect(lines[4].contains("头肩顶;矩形"))
    }

    @Test("v17.185 · renderWithAnnotations · 空 bars · 空字符串")
    func annotationsEmptyBars() {
        #expect(OHLCMarkdownExporter.renderWithAnnotations([], annotations: [:]).isEmpty)
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
