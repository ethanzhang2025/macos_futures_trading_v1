// WP-41 v15.18 · BBW 单测

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("BollingerBandwidth · 波动率紧缩指标")
struct BollingerBandwidthTests {

    private func makeSeries(closes: [Double]) -> KLineSeries {
        let count = closes.count
        return KLineSeries(
            opens: closes.map { Decimal($0) },
            highs: closes.map { Decimal($0 + 0.5) },
            lows: closes.map { Decimal($0 - 0.5) },
            closes: closes.map { Decimal($0) },
            volumes: Array(repeating: 0, count: count),
            openInterests: Array(repeating: 0, count: count)
        )
    }

    @Test("warmup 期 (i < period - 1) 全 nil · period 后有值")
    func warmupNils() throws {
        let closes = Array(repeating: 100.0, count: 25)
        let series = makeSeries(closes: closes)
        let result = try BollingerBandwidth.calculate(kline: series, params: [Decimal(20), Decimal(2)])
        // i = 0..18 nil
        for i in 0..<19 { #expect(result[0].values[i] == nil) }
        #expect(result[0].values[19] != nil)   // i=19 有值
    }

    @Test("常数序列 · BBW = 0（StdDev=0 · upper=lower=middle）")
    func constantInputBBWZero() throws {
        let closes = Array(repeating: 100.0, count: 25)
        let series = makeSeries(closes: closes)
        let result = try BollingerBandwidth.calculate(kline: series, params: [Decimal(20), Decimal(2)])
        let last = result[0].values.last!!
        #expect(last == 0)
    }

    @Test("波动序列 · BBW > 0 · 范围合理（< 100% for 普通波动）")
    func volatileInputBBWPositive() throws {
        let closes = (0..<30).map { i -> Double in
            100.0 + Foundation.sin(Double(i) * 0.5) * 5
        }
        let series = makeSeries(closes: closes)
        let result = try BollingerBandwidth.calculate(kline: series, params: [Decimal(20), Decimal(2)])
        let values = result[0].values.compactMap { $0 }
        #expect(!values.isEmpty)
        for v in values {
            let d = NSDecimalNumber(decimal: v).doubleValue
            #expect(d > 0)
            #expect(d < 50)   // 5% 振幅波动 BBW 不应超过 50%
        }
    }

    @Test("参数缺失 · 抛 invalidParameter")
    func missingParam() {
        let series = makeSeries(closes: [100])
        do {
            _ = try BollingerBandwidth.calculate(kline: series, params: [Decimal(20)])
            Issue.record("应抛错")
        } catch {}
    }

    @Test("identifier + category=volatility")
    func metadata() {
        #expect(BollingerBandwidth.identifier == "BBW")
        #expect(BollingerBandwidth.category == .volatility)
    }
}
