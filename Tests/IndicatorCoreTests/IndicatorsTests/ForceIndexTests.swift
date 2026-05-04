// WP-41 v15.18 · Force Index 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("ForceIndex · 价量复合力量指标")
struct ForceIndexTests {

    private func makeSeries(closes: [Double], volumes: [Int]) -> KLineSeries {
        let count = closes.count
        return KLineSeries(
            opens: closes.map { Decimal($0) },
            highs: closes.map { Decimal($0 + 1) },
            lows: closes.map { Decimal($0 - 1) },
            closes: closes.map { Decimal($0) },
            volumes: volumes,
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("空输入 · 返回空 series")
    func emptyInput() throws {
        let series = makeSeries(closes: [], volumes: [])
        let result = try ForceIndex.calculate(kline: series, params: [Decimal(13)])
        #expect(result[0].values.isEmpty)
    }

    @Test("第 0 根 · 必为 nil（无前值差）")
    func firstBarIsNil() throws {
        let series = makeSeries(closes: [100, 101, 102, 103], volumes: [10, 20, 30, 40])
        let result = try ForceIndex.calculate(kline: series, params: [Decimal(2)])
        #expect(result[0].values[0] == nil)
    }

    @Test("上升趋势 + 持续放量 · FI > 0（多头力量）")
    func uptrendPositive() throws {
        let closes = (0..<20).map { 100.0 + Double($0) }
        let volumes = (0..<20).map { _ in 100 }
        let series = makeSeries(closes: closes, volumes: volumes)
        let result = try ForceIndex.calculate(kline: series, params: [Decimal(13)])
        // 后段 FI 应该 > 0（每根 +100 涨幅 × 100 量）
        let last = result[0].values.last!!
        let d = NSDecimalNumber(decimal: last).doubleValue
        #expect(d > 0)
    }

    @Test("下降趋势 + 持续放量 · FI < 0（空头力量）")
    func downtrendNegative() throws {
        let closes = (0..<20).map { 200.0 - Double($0) }
        let volumes = (0..<20).map { _ in 100 }
        let series = makeSeries(closes: closes, volumes: volumes)
        let result = try ForceIndex.calculate(kline: series, params: [Decimal(13)])
        let last = result[0].values.last!!
        let d = NSDecimalNumber(decimal: last).doubleValue
        #expect(d < 0)
    }

    @Test("成交量为 0 · FI 为 0（无力量传递）")
    func zeroVolumeZeroFI() throws {
        let closes = (0..<20).map { 100.0 + Double($0) }
        let volumes = Array(repeating: 0, count: 20)
        let series = makeSeries(closes: closes, volumes: volumes)
        let result = try ForceIndex.calculate(kline: series, params: [Decimal(13)])
        #expect(result[0].values.last == 0 as Decimal?)   // 全 0 平均仍 0
    }

    @Test("identifier + category=volume")
    func metadata() {
        #expect(ForceIndex.identifier == "FI")
        #expect(ForceIndex.category == .volume)
    }
}
