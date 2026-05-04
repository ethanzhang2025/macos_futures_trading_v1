// v15.20 batch82 · SwingPointsDetector 单测

import Testing
import Foundation
@testable import Shared

@Suite("SwingPointsDetector · K 线 swing high/low 检测")
struct SwingPointsTests {

    private func bar(_ open: Decimal, _ high: Decimal, _ low: Decimal, _ close: Decimal, idx: Int) -> KLine {
        KLine(
            instrumentID: "RB0",
            period: .minute15,
            openTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(idx * 900)),
            open: open, high: high, low: low, close: close,
            volume: 100, openInterest: 1000, turnover: 100000
        )
    }

    @Test("空 / 数据不足 → 空数组")
    func emptyOrInsufficient() {
        #expect(SwingPointsDetector.detect([]) == [])
        #expect(SwingPointsDetector.detect([bar(100, 105, 95, 100, idx: 0)]) == [])
        // bars 数 ≤ 2*lookback → 空
        let bars = (0..<10).map { bar(100, 105, 95, 100, idx: $0) }
        #expect(SwingPointsDetector.detect(bars, lookback: 5) == [])  // 10 ≤ 2*5
    }

    @Test("简单单峰 · 第 5 根明显最高 → 1 swing high")
    func singlePeak() {
        // 11 根 · 第 5 根 high=120 · 前后递减
        let highs: [Decimal] = [100, 105, 110, 115, 119, 120, 119, 115, 110, 105, 100]
        let bars = (0..<11).map { i in bar(100, highs[i], 90, 100, idx: i) }
        let result = SwingPointsDetector.detect(bars, lookback: 5)
        #expect(result.count == 1)
        #expect(result[0].kind == .high)
        #expect(result[0].barIndex == 5)
        #expect(result[0].price == 120)
    }

    @Test("简单单谷 · 第 5 根明显最低 → 1 swing low")
    func singleTrough() {
        let lows: [Decimal] = [100, 95, 90, 85, 81, 80, 81, 85, 90, 95, 100]
        let bars = (0..<11).map { i in bar(105, 110, lows[i], 102, idx: i) }
        let result = SwingPointsDetector.detect(bars, lookback: 5)
        #expect(result.count == 1)
        #expect(result[0].kind == .low)
        #expect(result[0].barIndex == 5)
        #expect(result[0].price == 80)
    }

    @Test("严格大于 · 平顶不算 swing")
    func strictPlateauHigh() {
        // 11 根 · idx 5 与 idx 6 同 high=120 · 都不是严格大于 → 无 swing high
        let highs: [Decimal] = [100, 105, 110, 115, 119, 120, 120, 115, 110, 105, 100]
        let bars = (0..<11).map { i in bar(100, highs[i], 90, 100, idx: i) }
        let result = SwingPointsDetector.detect(bars, lookback: 5)
        #expect(result.isEmpty)
    }

    @Test("lookback 参数影响敏感度（小 N 多 swing · 大 N 少）")
    func lookbackSensitivity() {
        // 21 根 · 多个局部峰
        let highs: [Decimal] = [
            100, 105, 110, 108, 106, 109, 112, 115, 113, 110,
            120,  // idx 10 全局峰
            108, 105, 110, 113, 110, 107, 105, 103, 101, 99
        ]
        let bars = (0..<21).map { i in bar(100, highs[i], 90, 100, idx: i) }
        let result5 = SwingPointsDetector.detect(bars, lookback: 5)
        let result10 = SwingPointsDetector.detect(bars, lookback: 10)
        // lookback=10 仅识别全局峰
        #expect(result10.count == 1)
        #expect(result10[0].barIndex == 10)
        // lookback=5 识别更多局部峰（包含 idx 10）
        #expect(result5.count >= 1)
        #expect(result5.contains(where: { $0.barIndex == 10 }))
    }

    @Test("边界 N 根忽略（前 N + 后 N 不识别 swing）")
    func boundaryIgnored() {
        // 第 0 / 1 / 2 / 18 / 19 / 20 根 high 都很高 但因边界忽略
        let highs: [Decimal] = Array(repeating: Decimal(100), count: 21)
        var hs = highs
        hs[0] = 200; hs[1] = 200; hs[2] = 200; hs[18] = 200; hs[19] = 200; hs[20] = 200
        let bars = (0..<21).map { i in bar(100, hs[i], 90, 100, idx: i) }
        let result = SwingPointsDetector.detect(bars, lookback: 5)
        #expect(result.isEmpty)   // 边界 swing 全忽略
    }

    @Test("lookback 0 / 负数 → 空（防御）")
    func invalidLookback() {
        let bars = (0..<11).map { i in bar(100, 100 + Decimal(i), 90, 100, idx: i) }
        #expect(SwingPointsDetector.detect(bars, lookback: 0) == [])
        #expect(SwingPointsDetector.detect(bars, lookback: -5) == [])
    }

    @Test("v15.21 batch105 · filterDense · 同向密集合并取更极值（high 取大）")
    func filterDenseSameKindHigh() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [SwingPoint] = [
            SwingPoint(kind: .high, barIndex: 10, price: 100, time: now),
            SwingPoint(kind: .high, barIndex: 12, price: 110, time: now),  // 距离 2 < 5 · 取更高 110
            SwingPoint(kind: .high, barIndex: 13, price: 105, time: now),  // 距离 1 < 5 · 不替换
            SwingPoint(kind: .high, barIndex: 20, price: 90,  time: now),  // 距离 8 ≥ 5 · 保留
        ]
        let result = SwingPointsDetector.filterDense(points, minSpacing: 5)
        #expect(result.count == 2)
        #expect(result[0].barIndex == 12 && result[0].price == 110)
        #expect(result[1].barIndex == 20)
    }

    @Test("v15.21 batch105 · filterDense · 同向密集合并取更极值（low 取小）")
    func filterDenseSameKindLow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [SwingPoint] = [
            SwingPoint(kind: .low, barIndex: 10, price: 100, time: now),
            SwingPoint(kind: .low, barIndex: 12, price: 90,  time: now),  // 距离 2 < 5 · 取更低 90
            SwingPoint(kind: .low, barIndex: 13, price: 95,  time: now),  // 距离 1 < 5 · 不替换
        ]
        let result = SwingPointsDetector.filterDense(points, minSpacing: 5)
        #expect(result.count == 1)
        #expect(result[0].barIndex == 12 && result[0].price == 90)
    }

    @Test("v15.21 batch105 · filterDense · 不同 kind 相邻不过滤")
    func filterDenseDifferentKind() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [SwingPoint] = [
            SwingPoint(kind: .high, barIndex: 10, price: 100, time: now),
            SwingPoint(kind: .low,  barIndex: 11, price: 80,  time: now),  // 距离 1 但不同 kind · 保留
            SwingPoint(kind: .high, barIndex: 12, price: 105, time: now),
        ]
        let result = SwingPointsDetector.filterDense(points, minSpacing: 5)
        #expect(result.count == 3)
    }

    @Test("v15.21 batch105 · detect 接 minBarSpacing 默认 0 不过滤")
    func detectMinSpacingDefaultZero() {
        let bars = (0..<11).map { i in bar(100, 100 + Decimal(i % 3), 90, 100, idx: i) }
        // 默认 minBarSpacing=0 等价于不过滤
        let raw = SwingPointsDetector.detect(bars, lookback: 2)
        let same = SwingPointsDetector.detect(bars, lookback: 2, minBarSpacing: 0)
        #expect(raw == same)
    }
}
