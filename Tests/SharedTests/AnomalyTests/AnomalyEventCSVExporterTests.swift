// AnomalyEventCSVExporter 测试（v15.64）
//
// 覆盖：
// - header 7 列
// - UTF-8 BOM + CRLF 行终止
// - 含逗号/换行/引号的字段正确转义（RFC 4180）
// - 严重度格式 (0 整数 / 100 上限)
// - 时区注入

import XCTest
@testable import Shared

final class AnomalyEventCSVExporterTests: XCTestCase {

    func testHeader_sevenColumns() {
        XCTAssertEqual(AnomalyEventCSVExporter.header.count, 7)
        XCTAssertEqual(AnomalyEventCSVExporter.header.first, "检测时间")
    }

    func testExport_emptyHasOnlyHeader() {
        let csv = AnomalyEventCSVExporter.export([])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))  // BOM
        XCTAssertTrue(csv.contains("检测时间,类型,严重度,品种ID,品种名,板块,说明"))
        // 仅 header + 终止 \r\n
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\r\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)
    }

    func testExport_singleEventRowOK() {
        let date = Date(timeIntervalSince1970: 1746694800)  // 2025-05-08 09:00 UTC
        let evt = AnomalyEvent(
            instrumentID: "RB0",
            instrumentName: "螺纹钢",
            sector: .黑色,
            kind: .priceSpike,
            severity: 75.4,
            description: "螺纹钢 上涨 +2.50%（阈值 2.0%）",
            detectedAt: date
        )
        let csv = AnomalyEventCSVExporter.export([evt],
            timeZone: TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertTrue(csv.contains("RB0"))
        XCTAssertTrue(csv.contains("螺纹钢"))
        XCTAssertTrue(csv.contains("黑色系"))
        XCTAssertTrue(csv.contains("价格异动"))
        XCTAssertTrue(csv.contains("75"))   // severity rounded
        // 时间 +08:00 = 17:00
        XCTAssertTrue(csv.contains("2025-05-08 17:00:00"))
    }

    func testExport_specialCharsEscaped() {
        let evt = AnomalyEvent(
            instrumentID: "X",
            instrumentName: "测试",
            sector: .黑色,
            kind: .priceSpike,
            severity: 50,
            description: "含逗号,引号\"和换行\n的描述"
        )
        let csv = AnomalyEventCSVExporter.export([evt])
        // 含逗号 → 整字段加双引号
        XCTAssertTrue(csv.contains("\"含逗号,引号\"\"和换行\n的描述\""))
    }

    func testExport_severityFormat() {
        let evt = AnomalyEvent(
            instrumentID: "X", instrumentName: "测试",
            sector: .黑色, kind: .priceSpike,
            severity: 100, description: "极值"
        )
        let csv = AnomalyEventCSVExporter.export([evt])
        XCTAssertTrue(csv.contains(",100,"))
    }

    func testExportData_returnsUtf8Bytes() {
        let evt = AnomalyEvent(
            instrumentID: "RB0", instrumentName: "螺纹钢",
            sector: .黑色, kind: .priceSpike,
            severity: 50, description: "test"
        )
        let data = AnomalyEventCSVExporter.exportData([evt])
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("RB0"))
        XCTAssertTrue(str.contains("螺纹钢"))
    }
}
