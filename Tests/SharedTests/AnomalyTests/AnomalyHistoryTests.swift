// AnomalyHistory 测试（v15.59 · 30d 异常频次回溯）
//
// 覆盖：
// - generate 长度 / 排序（按 totalCount 降序）
// - days = 0 边界返回空数组
// - 单品种 entries.count == days
// - InstrumentAnomalyHistory.dailyCounts / avgPerDay / peakDayCount 派生属性
// - countByKind 与 entries 累加一致
// - mock 数据稳定性（同进程多次扫描结果一致）

import XCTest
@testable import Shared

final class AnomalyHistoryTests: XCTestCase {

    func testGenerate_lengthAndSorted() {
        let history = AnomalyHistoryGenerator.generate(days: 30)
        XCTAssertEqual(history.count, SectorPresets.all.count)
        for i in 1..<history.count {
            XCTAssertGreaterThanOrEqual(history[i - 1].totalCount, history[i].totalCount)
        }
    }

    func testGenerate_zeroDaysReturnsEmpty() {
        let history = AnomalyHistoryGenerator.generate(days: 0)
        XCTAssertTrue(history.isEmpty)
    }

    func testGenerate_perInstrumentDayCount() {
        let history = AnomalyHistoryGenerator.generate(days: 14)
        for h in history {
            XCTAssertEqual(h.entries.count, 14)
        }
    }

    func testGenerate_isStableAcrossInvocations() {
        // 同进程多次扫描 · 同 instrumentID 总数应一致
        let h1 = AnomalyHistoryGenerator.generate(days: 30)
        let h2 = AnomalyHistoryGenerator.generate(days: 30)
        let m1 = Dictionary(uniqueKeysWithValues: h1.map { ($0.instrumentID, $0.totalCount) })
        let m2 = Dictionary(uniqueKeysWithValues: h2.map { ($0.instrumentID, $0.totalCount) })
        XCTAssertEqual(m1, m2)
    }

    func testInstrumentAnomalyHistory_derivedProperties() {
        let history = AnomalyHistoryGenerator.generate(days: 30)
        guard let top = history.first else {
            XCTFail("no data")
            return
        }
        // dailyCounts.count == entries.count
        XCTAssertEqual(top.dailyCounts.count, top.entries.count)
        // 总数与 dailyCounts 累加一致
        XCTAssertEqual(top.dailyCounts.reduce(0, +), top.totalCount)
        // avgPerDay 与 totalCount / 30 一致
        XCTAssertEqual(top.avgPerDay, Double(top.totalCount) / 30.0, accuracy: 0.001)
        // peakDayCount ≥ avgPerDay
        XCTAssertGreaterThanOrEqual(Double(top.peakDayCount), top.avgPerDay)
    }

    func testGenerate_countByKindMatchesEntries() {
        let history = AnomalyHistoryGenerator.generate(days: 30)
        // 取一个有数据的品种验证 kind 累加一致
        guard let h = history.first(where: { $0.totalCount > 0 }) else {
            XCTFail("no anomaly hits in any instrument")
            return
        }
        var rebuilt: [AnomalyKind: Int] = [:]
        for entry in h.entries {
            for (kind, c) in entry.kindCounts {
                rebuilt[kind, default: 0] += c
            }
        }
        XCTAssertEqual(rebuilt, h.countByKind)
        // 总数 = 各类累加
        XCTAssertEqual(h.countByKind.values.reduce(0, +), h.totalCount)
    }

    func testGenerate_customInstruments() {
        // 仅传 3 个品种 → 仅生成 3 条
        let subset = Array(SectorPresets.all.prefix(3))
        let history = AnomalyHistoryGenerator.generate(days: 7, instruments: subset)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(Set(history.map(\.instrumentID)), Set(subset.map(\.id)))
    }
}
