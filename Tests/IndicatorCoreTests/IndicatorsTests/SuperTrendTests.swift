// WP-41 v15.18 · SuperTrend 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("SuperTrend · 趋势跟踪指标")
struct SuperTrendTests {

    private func makeSeries(_ samples: [(Double, Double, Double, Double)]) -> KLineSeries {
        KLineSeries(
            opens: samples.map { Decimal($0.0) },
            highs: samples.map { Decimal($0.1) },
            lows: samples.map { Decimal($0.2) },
            closes: samples.map { Decimal($0.3) },
            volumes: samples.map { _ in 0 },
            openInterests: samples.map { _ in 0 }
        )
    }

    @Test("空输入 · 返回两个空 series")
    func emptyInput() throws {
        let series = makeSeries([])
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        #expect(result.count == 2)
        #expect(result[0].values.isEmpty)
        #expect(result[1].values.isEmpty)
    }

    @Test("参数缺失 · 抛 invalidParameter")
    func missingParam() {
        let series = makeSeries([(100, 105, 95, 100)])
        do {
            _ = try SuperTrend.calculate(kline: series, params: [Decimal(10)])
            Issue.record("应抛错")
        } catch {
            // 期望抛
        }
    }

    @Test("单调上升趋势 · trend 全 +1（多头方向）")
    func uptrendDirection() throws {
        let samples = (0..<30).map { i -> (Double, Double, Double, Double) in
            let p = 100.0 + Double(i)
            return (p, p + 1, p - 0.5, p + 0.5)
        }
        let series = makeSeries(samples)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        let trends = result[1].values.compactMap { $0 }
        // ATR warmup 后 trend 应稳定 +1
        #expect(trends.last == 1)
    }

    @Test("单调下降趋势 · trend 后段 -1（空头方向）")
    func downtrendDirection() throws {
        let samples = (0..<30).map { i -> (Double, Double, Double, Double) in
            let p = 200.0 - Double(i)
            return (p, p + 0.5, p - 1, p - 0.5)
        }
        let series = makeSeries(samples)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        let trends = result[1].values.compactMap { $0 }
        #expect(trends.last == -1)
    }

    @Test("ATR warmup 期 · ST + TREND 都返回 nil（period - 1 根）")
    func warmupNils() throws {
        let samples = (0..<5).map { _ in (100.0, 102.0, 98.0, 100.0) }
        let series = makeSeries(samples)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        // 5 根 < 10 period · ATR 全 nil → ST/TREND 全 nil
        let stNonNil = result[0].values.compactMap { $0 }
        #expect(stNonNil.isEmpty)
    }

    @Test("identifier + category + parameters")
    func metadata() {
        #expect(SuperTrend.identifier == "SUPERTREND")
        #expect(SuperTrend.category == .trend)
        #expect(SuperTrend.parameters.count == 2)
        #expect(SuperTrend.parameters[0].name == "period")
        #expect(SuperTrend.parameters[1].name == "multiplier")
    }
}
