// SpreadAlertDetector 测试（v15.55 · ⌘⌥W）
//
// 覆盖：
// - evaluate 跨品种 / 跨期变体：阈值边界 + 方向判定
// - minSamples 不足返回 nil
// - threshold 不达标返回 nil
// - scanAll 排序按 |z| 降序
// - includeCrossInstrument / includeCalendar 开关
// - mock 数据确定性（同 seed 多次扫描结果一致）

import XCTest
@testable import DataCore
@testable import Shared

final class SpreadAlertDetectorTests: XCTestCase {

    // MARK: - fixtures

    /// 构造一段固定 spread series · 确定 mean / stdDev / current
    /// 序列：[base, base+1, base+2, ..., base+n-1, current]
    private func makeSeries(_ values: [Decimal]) -> [SpreadValue] {
        let now = Date()
        return values.enumerated().map { (i, v) in
            SpreadValue(openTime: now.addingTimeInterval(TimeInterval(i) * 86400),
                        value: v, leg1Close: 1000, leg2Close: 1000)
        }
    }

    private let dummyPair = SpreadPair(
        id: "test", name: "测试对",
        category: .跨品种,
        leg1: SpreadLeg(instrumentID: "RB0", ratio: 1),
        leg2: SpreadLeg(instrumentID: "HC0", ratio: -1),
        unitLabel: "元/吨",
        description: "测试用"
    )

    private let dummyCalPair = CalendarSpreadPair(
        id: "test-cal", name: "测试跨期",
        underlyingID: "RB", underlyingName: "螺纹",
        nearMonthID: "RB2505", farMonthID: "RB2510",
        category: .黑色,
        description: "测试用"
    )

    // MARK: - evaluate 跨品种

    func testEvaluate_skipsBelowMinSamples() {
        // 30 默认 minSamples · 给 10 个样本应跳过
        let values = makeSeries((0..<10).map { Decimal($0) })
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyPair, thresholds: .default)
        XCTAssertNil(evt)
    }

    func testEvaluate_skipsBelowZThreshold() {
        // 100 个样本均匀分布 0...99 · current=99 · 偏离均值约 √3 σ ≈ 1.71 < 2
        let values = makeSeries((0..<100).map { Decimal($0) })
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyPair, thresholds: .default)
        XCTAssertNil(evt)
    }

    func testEvaluate_triggersUpperBreached() {
        // 99 个 0 + 1 个 +1000 · 强偏离 → |z| 远 > 2
        var arr: [Decimal] = Array(repeating: 0, count: 99)
        arr.append(1000)
        let values = makeSeries(arr)
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyPair, thresholds: .default)
        XCTAssertNotNil(evt)
        XCTAssertEqual(evt?.direction, .upperBreached)
        XCTAssertEqual(evt?.kind, .crossInstrument)
        XCTAssertEqual(evt?.spreadID, "test")
        XCTAssertGreaterThan(evt?.absZ ?? 0, 2.0)
    }

    func testEvaluate_triggersLowerBreached() {
        var arr: [Decimal] = Array(repeating: 0, count: 99)
        arr.append(-1000)
        let values = makeSeries(arr)
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyPair, thresholds: .default)
        XCTAssertNotNil(evt)
        XCTAssertEqual(evt?.direction, .lowerBreached)
        XCTAssertLessThan(evt?.zScore ?? 0, -2.0)
    }

    func testEvaluate_strategyMessageForCrossInstrument() {
        var arr: [Decimal] = Array(repeating: 0, count: 99)
        arr.append(1000)
        let values = makeSeries(arr)
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyPair, thresholds: .default)
        XCTAssertNotNil(evt)
        // 上轨突破 → "卖 RB0 + 买 HC0"
        XCTAssertTrue(evt?.strategy.contains("卖 RB0") ?? false)
        XCTAssertTrue(evt?.strategy.contains("买 HC0") ?? false)
    }

    // MARK: - evaluate 跨期

    func testEvaluate_calendarVariantTriggers() {
        var arr: [Decimal] = Array(repeating: 0, count: 99)
        arr.append(500)
        let values = makeSeries(arr)
        let evt = SpreadAlertDetector.evaluate(values: values, pair: dummyCalPair, thresholds: .default)
        XCTAssertNotNil(evt)
        XCTAssertEqual(evt?.kind, .calendar)
        XCTAssertEqual(evt?.spreadID, "test-cal")
        // 跨期上轨 → "卖 RB2510 + 买 RB2505"（contango 极值）
        XCTAssertTrue(evt?.strategy.contains("卖 RB2510") ?? false)
        XCTAssertTrue(evt?.strategy.contains("买 RB2505") ?? false)
    }

    // MARK: - scanAll

    func testScanAll_returnsEventsSortedByAbsZDesc() {
        // 低阈值确保至少 1 事件（mock 数据随 Swift 进程 hash seed 浮动）
        var th = SpreadAlertThresholds.default
        th.zThreshold = 0.1
        let events = SpreadAlertDetector.scanAll(thresholds: th)
        XCTAssertGreaterThan(events.count, 0)
        guard events.count >= 2 else { return }
        for i in 1..<events.count {
            XCTAssertGreaterThanOrEqual(events[i - 1].absZ, events[i].absZ)
        }
    }

    func testScanAll_includeCrossInstrumentFalseSkipsCross() {
        var th = SpreadAlertThresholds.default
        th.includeCrossInstrument = false
        let events = SpreadAlertDetector.scanAll(thresholds: th)
        XCTAssertTrue(events.allSatisfy { $0.kind == .calendar })
    }

    func testScanAll_includeCalendarFalseSkipsCalendar() {
        var th = SpreadAlertThresholds.default
        th.includeCalendar = false
        let events = SpreadAlertDetector.scanAll(thresholds: th)
        XCTAssertTrue(events.allSatisfy { $0.kind == .crossInstrument })
    }

    func testScanAll_isDeterministic() {
        // 同一 thresholds 多次扫描 · 同 spread ID 集合
        let r1 = SpreadAlertDetector.scanAll()
        let r2 = SpreadAlertDetector.scanAll()
        XCTAssertEqual(r1.map(\.spreadID).sorted(), r2.map(\.spreadID).sorted())
    }

    func testScanAll_lowThresholdYieldsMoreEvents() {
        // 阈值降到 0.5 应至少产生与 2.0 阈值同样多的 events
        var th_high = SpreadAlertThresholds.default
        th_high.zThreshold = 2.0
        var th_low = SpreadAlertThresholds.default
        th_low.zThreshold = 0.5
        let high = SpreadAlertDetector.scanAll(thresholds: th_high)
        let low = SpreadAlertDetector.scanAll(thresholds: th_low)
        XCTAssertGreaterThanOrEqual(low.count, high.count)
    }
}
