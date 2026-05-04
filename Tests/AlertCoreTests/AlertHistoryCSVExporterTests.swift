// v15.19 batch19 · AlertHistory CSV 导出测试
// 覆盖空 / 单条 / 多条 / RFC 4180 转义 / 各类 condition / BOM + CRLF

import Testing
import Foundation
import Shared
@testable import AlertCore

@Suite("AlertHistoryCSVExporter · v15.19 batch19")
struct AlertHistoryCSVExporterTests {

    private func entry(name: String = "测试预警",
                       instrumentID: String = "RB0",
                       condition: AlertCondition = .priceAbove(3500),
                       triggerPrice: Decimal = 3501,
                       message: String = "价格 3501 高于 3500",
                       at: Date = Date(timeIntervalSince1970: 1_730_000_000)) -> AlertHistoryEntry {
        AlertHistoryEntry(
            alertID: UUID(),
            alertName: name,
            instrumentID: instrumentID,
            conditionSnapshot: condition,
            triggeredAt: at,
            triggerPrice: triggerPrice,
            message: message
        )
    }

    @Test("空输入 · 仅表头 + BOM + CRLF")
    func empty() {
        let csv = AlertHistoryCSVExporter.export([])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.contains("触发时间,合约,预警名,条件,触发价,说明"))
        #expect(csv.hasSuffix("\r\n"))
    }

    @Test("单条 · 6 字段对齐 + 时间格式 yyyy-MM-dd HH:mm:ss Asia/Shanghai")
    func singleRow() {
        let e = entry(at: Date(timeIntervalSince1970: 1_730_000_000))
        let csv = AlertHistoryCSVExporter.export([e])
        // BOM + 表头 + CRLF + 数据行 + CRLF
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: "\r\n")
        #expect(lines.count == 3)   // header + 1 row + trailing empty
        #expect(lines[1].contains("RB0"))
        #expect(lines[1].contains("测试预警"))
        #expect(lines[1].contains("3501"))
        #expect(lines[1].contains("价格 ≥ 3500"))
        // Asia/Shanghai · 1730000000 = 2024-10-27 03:33:20 UTC = 11:33:20 +0800
        #expect(lines[1].contains("2024-10-27 11:33:20"))
    }

    @Test("含逗号 / 引号 / 换行 · RFC 4180 转义")
    func rfc4180Escape() {
        let e = entry(name: "包含,逗号", message: "含\"引号\"和\n换行")
        let csv = AlertHistoryCSVExporter.export([e])
        #expect(csv.contains("\"包含,逗号\""))
        #expect(csv.contains("\"含\"\"引号\"\"和\n换行\""))
    }

    @Test("多条按输入顺序输出（不再排序）")
    func multipleRows() {
        let e1 = entry(name: "预警 A", at: Date(timeIntervalSince1970: 1_730_000_000))
        let e2 = entry(name: "预警 B", at: Date(timeIntervalSince1970: 1_730_001_000))
        let csv = AlertHistoryCSVExporter.export([e1, e2])
        let aIdx = csv.range(of: "预警 A")!.lowerBound
        let bIdx = csv.range(of: "预警 B")!.lowerBound
        #expect(aIdx < bIdx)
    }

    @Test("各类 AlertCondition 都有简短 label · 不抛错")
    func allConditionLabels() {
        let conditions: [AlertCondition] = [
            .priceAbove(100),
            .priceBelow(100),
            .priceCrossAbove(100),
            .priceCrossBelow(100),
            .priceBreakoutHigh(period: .minute15, lookback: 20),
            .priceBreakoutLow(period: .daily, lookback: 5),
            .horizontalLineTouched(drawingID: UUID(), price: 100),
            .volumeSpike(multiple: 3, windowBars: 20),
            .openInterestSpike(multiple: 1.5, windowBars: 20),
            .priceMoveSpike(percentThreshold: 1, windowSeconds: 60)
        ]
        let entries = conditions.map { entry(condition: $0) }
        let csv = AlertHistoryCSVExporter.export(entries)
        // 每条都有数据行
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 1 + conditions.count)
        // 关键 label 关键字
        #expect(csv.contains("突破 15m 前 20 根高"))
        #expect(csv.contains("跌破 D 前 5 根低"))
        #expect(csv.contains("触线"))
        #expect(csv.contains("成交量"))
        #expect(csv.contains("持仓量"))
        #expect(csv.contains("急动"))
    }

    @Test("exportData 返回 UTF-8 BOM Data")
    func exportDataBOM() {
        let data = AlertHistoryCSVExporter.exportData([entry()])
        // UTF-8 BOM = EF BB BF
        #expect(data.count >= 3)
        #expect(data[0] == 0xEF)
        #expect(data[1] == 0xBB)
        #expect(data[2] == 0xBF)
    }

    @Test("自定义 timeZone · UTC 显示")
    func customTimeZone() {
        let e = entry(at: Date(timeIntervalSince1970: 1_730_000_000))
        let csv = AlertHistoryCSVExporter.export([e], timeZone: TimeZone(identifier: "UTC")!)
        #expect(csv.contains("2024-10-27 03:33:20"))
    }
}
