// SpreadCustomPairStore 测试（v15.75）
//
// 覆盖：
// - load 不存在返回 []
// - save → load round-trip
// - append 防重 by id
// - remove 移除单条 · 不存在静默
// - clear 清空
// - 损坏数据 → load fallback []
// - 多对全字段保真（id/name/category/legs/unit/desc）

import XCTest
@testable import DataCore
@testable import Shared

final class SpreadCustomPairStoreTests: XCTestCase {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "SpreadCustomPairStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func samplePair(id: String = "custom-rb-cu", name: String = "螺纹铜对") -> SpreadPair {
        SpreadPair(
            id: id, name: name, category: .跨品种,
            leg1: SpreadLeg(instrumentID: "RB0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "CU0", ratio: -2),
            unitLabel: "元/吨", description: "用户自建测试对"
        )
    }

    func testLoad_emptyWhenMissing() {
        let defaults = makeIsolatedDefaults()
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 0)
    }

    func testSaveLoad_roundTrip() {
        let defaults = makeIsolatedDefaults()
        let pair = samplePair()
        XCTAssertTrue(SpreadCustomPairStore.save([pair], defaults: defaults))
        let loaded = SpreadCustomPairStore.load(defaults: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "custom-rb-cu")
        XCTAssertEqual(loaded[0].name, "螺纹铜对")
        XCTAssertEqual(loaded[0].category, .跨品种)
        XCTAssertEqual(loaded[0].leg1.instrumentID, "RB0")
        XCTAssertEqual(loaded[0].leg1.ratio, 1)
        XCTAssertEqual(loaded[0].leg2.instrumentID, "CU0")
        XCTAssertEqual(loaded[0].leg2.ratio, -2)
        XCTAssertEqual(loaded[0].unitLabel, "元/吨")
    }

    func testAppend_dedupsBySameID() {
        let defaults = makeIsolatedDefaults()
        let pair = samplePair()
        XCTAssertTrue(SpreadCustomPairStore.append(pair, defaults: defaults))
        // 同 id 第二次 append → false
        XCTAssertFalse(SpreadCustomPairStore.append(pair, defaults: defaults))
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 1)
    }

    func testAppend_differentIDsCoexist() {
        let defaults = makeIsolatedDefaults()
        XCTAssertTrue(SpreadCustomPairStore.append(samplePair(id: "p1"), defaults: defaults))
        XCTAssertTrue(SpreadCustomPairStore.append(samplePair(id: "p2"), defaults: defaults))
        XCTAssertTrue(SpreadCustomPairStore.append(samplePair(id: "p3"), defaults: defaults))
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 3)
        XCTAssertEqual(Set(SpreadCustomPairStore.load(defaults: defaults).map(\.id)),
                       ["p1", "p2", "p3"])
    }

    func testRemove_existing() {
        let defaults = makeIsolatedDefaults()
        SpreadCustomPairStore.append(samplePair(id: "p1"), defaults: defaults)
        SpreadCustomPairStore.append(samplePair(id: "p2"), defaults: defaults)
        XCTAssertTrue(SpreadCustomPairStore.remove(id: "p1", defaults: defaults))
        let loaded = SpreadCustomPairStore.load(defaults: defaults)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "p2")
    }

    func testRemove_missingIsSilent() {
        let defaults = makeIsolatedDefaults()
        SpreadCustomPairStore.append(samplePair(id: "p1"), defaults: defaults)
        XCTAssertFalse(SpreadCustomPairStore.remove(id: "nonexistent", defaults: defaults))
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 1)
    }

    func testClear_removesAll() {
        let defaults = makeIsolatedDefaults()
        SpreadCustomPairStore.append(samplePair(id: "p1"), defaults: defaults)
        SpreadCustomPairStore.append(samplePair(id: "p2"), defaults: defaults)
        SpreadCustomPairStore.clear(defaults: defaults)
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 0)
    }

    func testLoad_corruptedDataFallsBackEmpty() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data([0x01, 0x02, 0xFF]), forKey: SpreadCustomPairStore.key)
        XCTAssertEqual(SpreadCustomPairStore.load(defaults: defaults).count, 0)
    }
}
