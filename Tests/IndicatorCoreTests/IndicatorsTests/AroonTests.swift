// WP-41 v15.18 · Aroon 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("Aroon · 趋势强度指标")
struct AroonTests {

    private func makeSeries(highs: [Double], lows: [Double]) -> KLineSeries {
        let count = highs.count
        return KLineSeries(
            opens: highs.map { Decimal($0) },
            highs: highs.map { Decimal($0) },
            lows: lows.map { Decimal($0) },
            closes: highs.map { Decimal($0) },
            volumes: Array(repeating: 0, count: count),
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("warmup 期 (i < n - 1) · 全 nil")
    func warmupNils() throws {
        let series = makeSeries(highs: [1, 2, 3], lows: [1, 1, 1])
        let result = try Aroon.calculate(kline: series, params: [Decimal(14)])
        for v in result[0].values { #expect(v == nil) }
        for v in result[1].values { #expect(v == nil) }
        for v in result[2].values { #expect(v == nil) }
    }

    @Test("最高在窗口最末 · AroonUp = 100（强多头）")
    func upAt100WhenHighIsCurrent() throws {
        // 14 根 · 最末 highs[13] 最大（10 最高）
        let highs: [Double] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 10]
        let lows: [Double]  = highs.map { $0 - 0.5 }
        let series = makeSeries(highs: highs, lows: lows)
        let result = try Aroon.calculate(kline: series, params: [Decimal(14)])
        // i = 13 · 最高在 idx=13 · daysSinceHigh = 0 · up = 100
        #expect(result[0].values[13] == 100)
    }

    @Test("最低在窗口最末 · AroonDown = 100（强空头）")
    func downAt100WhenLowIsCurrent() throws {
        let highs: [Double] = Array(repeating: 100.0, count: 14)
        var lows: [Double] = Array(repeating: 99.0, count: 14)
        lows[13] = 50    // 最末 = 最低
        let series = makeSeries(highs: highs, lows: lows)
        let result = try Aroon.calculate(kline: series, params: [Decimal(14)])
        #expect(result[1].values[13] == 100)
    }

    @Test("AroonOsc = AroonUp - AroonDown · 强多头时 osc 接近 +100")
    func oscRange() throws {
        let highs: [Double] = (1...14).map { Double($0) }
        let lows: [Double] = (1...14).map { Double($0) - 0.5 }
        let series = makeSeries(highs: highs, lows: lows)
        let result = try Aroon.calculate(kline: series, params: [Decimal(14)])
        // 单调上升 · 当前 high 最大 · up=100 · low 最小在最初 · daysSinceLow=13 · down=(14-13)/14*100≈7.14
        // osc = 100 - 7.14 ≈ 92.86
        let osc = result[2].values[13]!
        let oscD = NSDecimalNumber(decimal: osc).doubleValue
        #expect(oscD > 90)
        #expect(oscD < 100)
    }

    @Test("period < 2 · 抛 invalidParameter")
    func invalidPeriod() {
        let series = makeSeries(highs: [1, 2], lows: [1, 1])
        do {
            _ = try Aroon.calculate(kline: series, params: [Decimal(1)])
            Issue.record("应抛错")
        } catch {
            // 期望抛
        }
    }

    @Test("identifier + category + parameters")
    func metadata() {
        #expect(Aroon.identifier == "AROON")
        #expect(Aroon.category == .trend)
        #expect(Aroon.parameters[0].name == "period")
        #expect(Aroon.parameters[0].defaultValue == 14)
    }
}
