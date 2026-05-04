// WP-41 v15.18 · ATR% 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("ATRPercent · 标准化波动率")
struct ATRPercentTests {

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

    @Test("warmup 期 nil（依赖 ATR 14 周期）")
    func warmupNils() throws {
        let highs = Array(repeating: 102.0, count: 5)
        let lows = Array(repeating: 98.0, count: 5)
        let closes = Array(repeating: 100.0, count: 5)
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try ATRPercent.calculate(kline: series, params: [Decimal(14)])
        for v in result[0].values { #expect(v == nil) }
    }

    @Test("常数振幅 · ATR% = ATR / close × 100")
    func constantAmplitude() throws {
        // 每根 high - low = 4 · close = 100 · 期望 ATR ≈ 4 · ATR% ≈ 4
        let highs = Array(repeating: 102.0, count: 30)
        let lows = Array(repeating: 98.0, count: 30)
        let closes = Array(repeating: 100.0, count: 30)
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try ATRPercent.calculate(kline: series, params: [Decimal(14)])
        let last = result[0].values.last!!
        let d = NSDecimalNumber(decimal: last).doubleValue
        #expect(d > 3.5 && d < 4.5)   // ~4%
    }

    @Test("close = 0 防 0 除（return nil）")
    func zeroCloseGuarded() throws {
        let highs = Array(repeating: 1.0, count: 30)
        let lows = Array(repeating: 0.0, count: 30)
        let closes = Array(repeating: 0.0, count: 30)
        let series = makeSeries(highs: highs, lows: lows, closes: closes)
        let result = try ATRPercent.calculate(kline: series, params: [Decimal(14)])
        // close=0 时全 nil（防 0 除）
        for v in result[0].values { #expect(v == nil) }
    }

    @Test("identifier=ATRP + category=volatility")
    func metadata() {
        #expect(ATRPercent.identifier == "ATRP")
        #expect(ATRPercent.category == .volatility)
    }
}
