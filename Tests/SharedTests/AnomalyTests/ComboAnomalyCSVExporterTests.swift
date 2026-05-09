// ComboAnomalyCSVExporter 测试（v15.71）
//
// 覆盖：
// - header 9 列
// - UTF-8 BOM + CRLF
// - 单 combo 行渲染（rank / 类型数 / 命中类型拼接 / severity 1 位小数）
// - 命中类型按 AnomalyKind.allCases 顺序稳定排列
// - 多 combo 排名正确
// - RFC 4180 转义（含 ,/换行/引号 字段）

import XCTest
@testable import Shared

final class ComboAnomalyCSVExporterTests: XCTestCase {

    private func event(
        id: String, name: String = "螺纹钢",
        sector: Sector = .黑色, kind: AnomalyKind, severity: Double = 60
    ) -> AnomalyEvent {
        AnomalyEvent(
            instrumentID: id, instrumentName: name, sector: sector,
            kind: kind, severity: severity, description: "test"
        )
    }

    func testHeader_nineColumns() {
        XCTAssertEqual(ComboAnomalyCSVExporter.header.count, 9)
        XCTAssertEqual(ComboAnomalyCSVExporter.header.first, "排名")
        XCTAssertEqual(ComboAnomalyCSVExporter.header.last, "检测时间")
    }

    func testExport_emptyHasOnlyHeader() {
        let csv = ComboAnomalyCSVExporter.export([])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("排名,品种ID,品种名,板块,类型数,命中类型,avg严重度,combo严重度,检测时间"))
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\r\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)
    }

    func testExport_singleCombo_kindsOrderStable() {
        // 故意乱序传 kinds（fundSurge / priceSpike / oiSpike）→ CSV 应按 enum allCases 顺序
        let evts = [
            event(id: "RB0", kind: .fundSurge, severity: 80),
            event(id: "RB0", kind: .priceSpike, severity: 60),
            event(id: "RB0", kind: .oiSpike, severity: 70)
        ]
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        let csv = ComboAnomalyCSVExporter.export(combos)
        // AnomalyKind.allCases = priceSpike / oiSpike / fundSurge / priceOIDivergence / sectorOutlier
        // 命中类型应按此顺序：价格异动 · 持仓异动 · 资金异动
        XCTAssertTrue(csv.contains("价格异动 · 持仓异动 · 资金异动"))
        XCTAssertTrue(csv.contains("RB0"))
        XCTAssertTrue(csv.contains("螺纹钢"))
        XCTAssertTrue(csv.contains(",3,"))  // 类型数
        // severity: avg=70.0 / total=70.0（×1.0 因 3 类）
        XCTAssertTrue(csv.contains("70.0,70.0"))
    }

    func testExport_multipleCombos_rankCorrect() {
        // A: 3 类 severity 90 / B: 3 类 severity 60
        let aEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "A", name: "甲", kind: $0, severity: 90)
        }
        let bEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "B", name: "乙", kind: $0, severity: 60)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: aEvts + bEvts)
        let csv = ComboAnomalyCSVExporter.export(combos)
        // 用 split 取出非 header 行
        let body = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\r\n", omittingEmptySubsequences: true)
        XCTAssertEqual(body.count, 3)  // header + 2 combo
        // 第一条 rank=1 应为 A · 第二条 rank=2 应为 B
        XCTAssertTrue(body[1].hasPrefix("1,A,甲,"))
        XCTAssertTrue(body[2].hasPrefix("2,B,乙,"))
    }

    func testExport_specialCharsEscaped() {
        // 用一个含逗号的品种名（罕见但要稳）
        let evts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "X", name: "含,逗号", kind: $0, severity: 50)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        let csv = ComboAnomalyCSVExporter.export(combos)
        // 含逗号字段必须加双引号
        XCTAssertTrue(csv.contains("\"含,逗号\""))
    }

    func testExportData_returnsUtf8Bytes() {
        let evts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "RB0", kind: $0)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        let data = ComboAnomalyCSVExporter.exportData(combos)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("RB0"))
        XCTAssertTrue(str.contains("螺纹钢"))
        XCTAssertTrue(str.contains("黑色系"))
    }
}
