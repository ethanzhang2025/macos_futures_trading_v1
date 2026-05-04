// WP-41 v15.18 · STC 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("STC · Schaff Trend Cycle 复合指标")
struct SchaffTrendCycleTests {

    private func makeSeries(closes: [Double]) -> KLineSeries {
        let count = closes.count
        return KLineSeries(
            opens: closes.map { Decimal($0) },
            highs: closes.map { Decimal($0 + 1) },
            lows: closes.map { Decimal($0 - 1) },
            closes: closes.map { Decimal($0) },
            volumes: Array(repeating: 0, count: count),
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("空 / 短输入 · 全 nil（warmup 跨多层 EMA）")
    func emptyOrShortInput() throws {
        let series = makeSeries(closes: [100, 101, 102])
        let result = try STC.calculate(kline: series, params: [Decimal(23), Decimal(50), Decimal(10), Decimal(10)])
        for v in result[0].values { #expect(v == nil) }
    }

    @Test("STC 输出值域 0-100（充分长趋势 · 500 根 · 跨多层 EMA warmup 后应有输出）")
    func stcOutputsInRange() throws {
        // STC 需要：EMA(50) seed 50 + period 10 + EMA(10) seed 10 + period 10 + EMA(10) seed 10 ≈ 100 根 warmup
        // 用震荡序列让 hh != ll · 确保 K1/K2 分母非零
        let closes = (0..<500).map { i -> Double in
            100.0 + 20.0 * Foundation.sin(Double(i) * 0.05)
        }
        let series = makeSeries(closes: closes)
        let result = try STC.calculate(kline: series, params: [Decimal(23), Decimal(50), Decimal(10), Decimal(10)])
        let values = result[0].values.compactMap { $0 }
        #expect(!values.isEmpty)
        for v in values {
            let d = NSDecimalNumber(decimal: v).doubleValue
            #expect(d >= 0 && d <= 100)
        }
    }

    @Test("参数缺失 · 抛 invalidParameter")
    func missingParam() {
        let series = makeSeries(closes: [100])
        do {
            _ = try STC.calculate(kline: series, params: [Decimal(23), Decimal(50)])
            Issue.record("应抛错")
        } catch {}
    }

    @Test("slow <= fast · 抛 invalidParameter")
    func invalidFastSlow() {
        let series = makeSeries(closes: [100])
        do {
            _ = try STC.calculate(kline: series, params: [Decimal(50), Decimal(23), Decimal(10), Decimal(10)])
            Issue.record("应抛错")
        } catch {}
    }

    @Test("identifier + category + 4 parameters")
    func metadata() {
        #expect(STC.identifier == "STC")
        #expect(STC.category == .trend)
        #expect(STC.parameters.count == 4)
        #expect(STC.parameters.map(\.name) == ["fast", "slow", "period", "smooth"])
    }
}
