// ComboAnomaly 聚合器测试（v15.70 · ⌘⌥A 组合异常发现）
//
// 覆盖：
// - 0/1/2 类命中：不出 combo（< minKinds=3）
// - 3/4/5 类命中：1 combo · severity 数量加权
// - 多品种排序：totalSeverity desc → kindCount desc → instrumentID
// - minKinds 边界（1 / 2 / 5 / 6）
// - kinds Set 去重（同 instrument 同 kind 多事件）
// - 便利方法 aggregate(from:) 与 aggregate(events:) 一致

import XCTest
@testable import Shared

final class ComboAnomalyAggregatorTests: XCTestCase {

    // MARK: - 数据 fixture

    private func event(
        id: String,
        name: String = "测试品种",
        sector: Sector = .黑色,
        kind: AnomalyKind,
        severity: Double = 60.0
    ) -> AnomalyEvent {
        AnomalyEvent(
            instrumentID: id, instrumentName: name, sector: sector,
            kind: kind, severity: severity, description: "test"
        )
    }

    // MARK: - 触发边界（< minKinds 不产生 combo）

    func test_zeroEvents_noCombo() {
        let combos = ComboAnomalyAggregator.aggregate(events: [])
        XCTAssertTrue(combos.isEmpty)
    }

    func test_oneKindHit_noCombo() {
        let evts = [event(id: "rb2510", kind: .priceSpike)]
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertTrue(combos.isEmpty)
    }

    func test_twoKindHit_noCombo() {
        let evts = [
            event(id: "rb2510", kind: .priceSpike),
            event(id: "rb2510", kind: .oiSpike)
        ]
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertTrue(combos.isEmpty)
    }

    // MARK: - 命中产生 combo

    func test_threeKindHit_oneCombo_avgWeighted() {
        // 3 类 · severity 50/60/70 → avg 60 · totalSeverity = 60 × 1.0 = 60
        let evts = [
            event(id: "rb2510", name: "螺纹", kind: .priceSpike, severity: 50),
            event(id: "rb2510", name: "螺纹", kind: .oiSpike, severity: 60),
            event(id: "rb2510", name: "螺纹", kind: .fundSurge, severity: 70)
        ]
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertEqual(combos.count, 1)
        let combo = combos[0]
        XCTAssertEqual(combo.instrumentID, "rb2510")
        XCTAssertEqual(combo.kindCount, 3)
        XCTAssertEqual(combo.kinds, [.priceSpike, .oiSpike, .fundSurge])
        XCTAssertEqual(combo.avgSeverity, 60.0, accuracy: 0.001)
        XCTAssertEqual(combo.totalSeverity, 60.0, accuracy: 0.001)  // ×1.0
        // events 应按 severity desc 排
        XCTAssertEqual(combo.events.map(\.kind), [.fundSurge, .oiSpike, .priceSpike])
    }

    func test_fourKindHit_severityX1_2() {
        // 4 类 · 全 50 · totalSeverity = 50 × 1.2 = 60
        let kinds: [AnomalyKind] = [.priceSpike, .oiSpike, .fundSurge, .priceOIDivergence]
        let evts = kinds.map { event(id: "cu2510", name: "铜", sector: .有色, kind: $0, severity: 50) }
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertEqual(combos.count, 1)
        XCTAssertEqual(combos[0].kindCount, 4)
        XCTAssertEqual(combos[0].avgSeverity, 50.0, accuracy: 0.001)
        XCTAssertEqual(combos[0].totalSeverity, 60.0, accuracy: 0.001)
    }

    func test_fiveKindHit_severityX1_4_clamped100() {
        // 5 类 · 全 80 → avg 80 · 80 × 1.4 = 112 → clamp 100
        let evts = AnomalyKind.allCases.map {
            event(id: "ag2510", name: "白银", sector: .贵金属, kind: $0, severity: 80)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertEqual(combos.count, 1)
        XCTAssertEqual(combos[0].kindCount, 5)
        XCTAssertEqual(combos[0].avgSeverity, 80.0, accuracy: 0.001)
        XCTAssertEqual(combos[0].totalSeverity, 100.0, accuracy: 0.001)  // clamp
    }

    // MARK: - 多品种排序

    func test_multiInstruments_sortedByTotalSeverityDesc() {
        // A: 3 类 avg 90 → 90 / B: 4 类 avg 60 → 72 / C: 5 类 avg 50 → 70
        // 排序：A(90) > B(72) > C(70)
        let aEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "A", kind: $0, severity: 90)
        }
        let bEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge, .priceOIDivergence].map {
            event(id: "B", kind: $0, severity: 60)
        }
        let cEvts: [AnomalyEvent] = AnomalyKind.allCases.map {
            event(id: "C", kind: $0, severity: 50)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: aEvts + bEvts + cEvts)
        XCTAssertEqual(combos.count, 3)
        XCTAssertEqual(combos.map(\.instrumentID), ["A", "B", "C"])
        XCTAssertEqual(combos[0].totalSeverity, 90.0, accuracy: 0.001)
        XCTAssertEqual(combos[1].totalSeverity, 72.0, accuracy: 0.001)
        XCTAssertEqual(combos[2].totalSeverity, 70.0, accuracy: 0.001)
    }

    func test_tieSeverity_kindCountDescThenIDAsc() {
        // A 与 B 都 avg 60 / 3 类 → tie → 按 instrumentID asc
        let aEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "B", kind: $0, severity: 60)
        }
        let bEvts: [AnomalyEvent] = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "A", kind: $0, severity: 60)
        }
        let combos = ComboAnomalyAggregator.aggregate(events: aEvts + bEvts)
        XCTAssertEqual(combos.count, 2)
        XCTAssertEqual(combos.map(\.instrumentID), ["A", "B"])
    }

    // MARK: - minKinds 边界

    func test_minKinds_2_twoKindHit_produces() {
        let evts = [
            event(id: "rb", kind: .priceSpike, severity: 50),
            event(id: "rb", kind: .oiSpike, severity: 70)
        ]
        let combos = ComboAnomalyAggregator.aggregate(events: evts, minKinds: 2)
        XCTAssertEqual(combos.count, 1)
        XCTAssertEqual(combos[0].kindCount, 2)
        // 2 类不触发数量加权（kindCount - 3 = -1 → max(0, -1) = 0）
        XCTAssertEqual(combos[0].totalSeverity, 60.0, accuracy: 0.001)
    }

    func test_minKinds_6_neverProduces() {
        // 总共 5 类 enum · 阈值 6 永远不触发
        let evts = AnomalyKind.allCases.map { event(id: "rb", kind: $0) }
        let combos = ComboAnomalyAggregator.aggregate(events: evts, minKinds: 6)
        XCTAssertTrue(combos.isEmpty)
    }

    func test_minKinds_zero_returnsEmpty() {
        // 防御：minKinds <= 0 视为非法 · 返回空
        let evts = [event(id: "rb", kind: .priceSpike)]
        let combos = ComboAnomalyAggregator.aggregate(events: evts, minKinds: 0)
        XCTAssertTrue(combos.isEmpty)
    }

    // MARK: - kinds Set 去重

    func test_sameInstrumentSameKind_dedup() {
        // 同 instrument 同 kind 2 个事件（理论上 detector 不产生 · 防御性测试）
        // 应当只算 1 个 kind · 不达 minKinds=3
        let evts = [
            event(id: "rb", kind: .priceSpike, severity: 50),
            event(id: "rb", kind: .priceSpike, severity: 60),
            event(id: "rb", kind: .oiSpike, severity: 70)
        ]
        let combos = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertTrue(combos.isEmpty)  // kindCount = 2 < 3
    }

    // MARK: - 便利方法

    func test_aggregate_fromResult_matchesEvents() {
        let evts = [.priceSpike, .oiSpike, .fundSurge].map {
            event(id: "rb", kind: $0, severity: 60)
        }
        let result = AnomalyDetectionResult(
            events: evts,
            countByKind: [.priceSpike: 1, .oiSpike: 1, .fundSurge: 1],
            countBySector: [.黑色: 3]
        )
        let combosFromResult = ComboAnomalyAggregator.aggregate(from: result)
        let combosFromEvents = ComboAnomalyAggregator.aggregate(events: evts)
        XCTAssertEqual(combosFromResult.count, combosFromEvents.count)
        XCTAssertEqual(combosFromResult.first?.totalSeverity ?? -1,
                       combosFromEvents.first?.totalSeverity ?? -2,
                       accuracy: 0.001)
    }
}
