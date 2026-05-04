// WP-41 v15.18 · ElderRay + Choppiness 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("ElderRay · 多空力量指标")
struct ElderRayTests {

    private func makeSeries(_ samples: [(Double, Double, Double)]) -> KLineSeries {
        // (high, low, close)
        let count = samples.count
        return KLineSeries(
            opens: samples.map { Decimal($0.2) },
            highs: samples.map { Decimal($0.0) },
            lows: samples.map { Decimal($0.1) },
            closes: samples.map { Decimal($0.2) },
            volumes: Array(repeating: 0, count: count),
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("warmup 期 nil · period 后有值 · Bull = high - EMA / Bear = low - EMA")
    func basicCalculation() throws {
        let samples: [(Double, Double, Double)] = (0..<20).map { i in
            let p = 100.0 + Double(i)
            return (p + 1, p - 1, p)
        }
        let series = makeSeries(samples)
        let result = try ElderRay.calculate(kline: series, params: [Decimal(13)])
        #expect(result.count == 2)
        // i=0..11 nil（EMA 13 seed at i=12）
        for i in 0..<12 {
            #expect(result[0].values[i] == nil)
            #expect(result[1].values[i] == nil)
        }
        // i=12 起 valid
        #expect(result[0].values[12] != nil)
        #expect(result[1].values[12] != nil)
    }

    @Test("上升趋势 · Bull > 0（高于 EMA）· Bear 也可能 > 0")
    func uptrendBullPositive() throws {
        let samples: [(Double, Double, Double)] = (0..<30).map { i in
            let p = 100.0 + Double(i) * 2
            return (p + 0.5, p - 0.5, p)
        }
        let series = makeSeries(samples)
        let result = try ElderRay.calculate(kline: series, params: [Decimal(13)])
        let lastBull = result[0].values.last!
        let bullD = NSDecimalNumber(decimal: lastBull!).doubleValue
        #expect(bullD > 0)   // 上升趋势 high 远高于 EMA
    }

    @Test("identifier + category")
    func metadata() {
        #expect(ElderRay.identifier == "ELDER")
        #expect(ElderRay.category == .oscillator)
    }
}

@Suite("Choppiness · 震荡度指标")
struct ChoppinessTests {

    private func makeSeries(highs: [Double], lows: [Double], closes: [Double]) -> KLineSeries {
        let count = highs.count
        return KLineSeries(
            opens: closes.map { Decimal($0) },
            highs: highs.map { Decimal($0) },
            lows: lows.map { Decimal($0) },
            closes: closes.map { Decimal($0) },
            volumes: Array(repeating: 0, count: count),
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("warmup 期 nil（i < n-1）")
    func warmupNils() throws {
        let highs = Array(repeating: 102.0, count: 5)
        let lows = Array(repeating: 98.0, count: 5)
        let closes = Array(repeating: 100.0, count: 5)
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try Choppiness.calculate(kline: series, params: [Decimal(14)])
        for v in result[0].values { #expect(v == nil) }
    }

    @Test("强趋势数据（单调上升）· CI 应较低（< 50）")
    func strongTrendLowCI() throws {
        let highs = (0..<30).map { 100.0 + Double($0) + 0.5 }
        let lows = (0..<30).map { 100.0 + Double($0) - 0.5 }
        let closes = (0..<30).map { 100.0 + Double($0) }
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try Choppiness.calculate(kline: series, params: [Decimal(14)])
        let last = result[0].values.last!!
        let ci = NSDecimalNumber(decimal: last).doubleValue
        #expect(ci < 50)   // 强趋势 · 低 CI
    }

    @Test("CI 输出值域 0-100")
    func valueRangeBounded() throws {
        let highs = (0..<30).map { 100.0 + Foundation.sin(Double($0) * 0.3) * 5 + 1 }
        let lows = (0..<30).map { 100.0 + Foundation.sin(Double($0) * 0.3) * 5 - 1 }
        let closes = (0..<30).map { 100.0 + Foundation.sin(Double($0) * 0.3) * 5 }
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try Choppiness.calculate(kline: series, params: [Decimal(14)])
        for v in result[0].values.compactMap({ $0 }) {
            let d = NSDecimalNumber(decimal: v).doubleValue
            #expect(d >= 0 && d <= 100.5)   // 算法理论上限 100 · 浮点偏差容忍
        }
    }

    @Test("identifier + category")
    func metadata() {
        #expect(Choppiness.identifier == "CHOPPINESS")
        #expect(Choppiness.category == .oscillator)
    }
}
