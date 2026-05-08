// SpreadCalculator 单测（v15.27 · WP-套利分析 V1）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("SpreadCalculator · 价差时序计算")
struct SpreadCalculatorTests {

    // 构造 K 线（指定 close · 其他字段填默认）
    private func makeBars(_ closes: [(Date, Decimal)], instrumentID: String = "TEST") -> [KLine] {
        closes.map { (time, close) in
            KLine(
                instrumentID: instrumentID, period: .minute1, openTime: time,
                open: close, high: close, low: close, close: close,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
    }

    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private func t(_ offset: TimeInterval) -> Date { baseDate.addingTimeInterval(offset) }

    @Test("基础 1:1 价差 · rb-hc · 时间戳全对齐")
    func basicSpread1to1() {
        let pair = SpreadPair(
            id: "rb-hc", name: "螺纹热卷", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "RB0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "HC0", ratio: -1),
            unitLabel: "元/吨", description: ""
        )
        let leg1 = makeBars([(t(0), 3500), (t(60), 3520), (t(120), 3550)])
        let leg2 = makeBars([(t(0), 3300), (t(60), 3340), (t(120), 3360)])

        let result = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
        #expect(result.count == 3)
        #expect(result[0].value == 200)   // 3500-3300
        #expect(result[1].value == 180)   // 3520-3340
        #expect(result[2].value == 190)   // 3550-3360
    }

    @Test("加权 1:80 价差 · au-80ag")
    func weightedSpread1to80() {
        let pair = SpreadPair(
            id: "au-80ag", name: "金银比", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "AU0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "AG0", ratio: -80),
            unitLabel: "元/克", description: ""
        )
        let leg1 = makeBars([(t(0), 600), (t(60), 620)])
        let leg2 = makeBars([(t(0), 7), (t(60), 7.5)])

        let result = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
        #expect(result.count == 2)
        // 600 - 80*7 = 40
        #expect(result[0].value == 40)
        // 620 - 80*7.5 = 20
        #expect(result[1].value == 20)
    }

    @Test("时间戳错位 · 仅吻合的 bar 输出")
    func mismatchedTimestamps() {
        let pair = SpreadPair(
            id: "test", name: "test", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "A", ratio: 1),
            leg2: SpreadLeg(instrumentID: "B", ratio: -1),
            unitLabel: "", description: ""
        )
        // leg1: t0/t1/t2/t3 · leg2: t1/t2/t4 → 应输出 t1/t2 (2 个对齐)
        let leg1 = makeBars([(t(0), 100), (t(60), 110), (t(120), 120), (t(180), 130)])
        let leg2 = makeBars([(t(60), 90), (t(120), 95), (t(240), 100)])

        let result = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
        #expect(result.count == 2)
        #expect(result[0].openTime == t(60))
        #expect(result[0].value == 20)   // 110-90
        #expect(result[1].openTime == t(120))
        #expect(result[1].value == 25)   // 120-95
    }

    @Test("空腿（leg1 空 / leg2 空）→ 空结果不崩")
    func emptyLegsReturnEmpty() {
        let pair = SpreadPair(
            id: "test", name: "test", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "A", ratio: 1),
            leg2: SpreadLeg(instrumentID: "B", ratio: -1),
            unitLabel: "", description: ""
        )
        let some = makeBars([(t(0), 100)])
        #expect(SpreadCalculator.calculate(pair: pair, leg1Bars: [], leg2Bars: some).isEmpty)
        #expect(SpreadCalculator.calculate(pair: pair, leg1Bars: some, leg2Bars: []).isEmpty)
        #expect(SpreadCalculator.calculate(pair: pair, leg1Bars: [], leg2Bars: []).isEmpty)
    }

    @Test("close <= 0 异常数据 · 跳过该 bar")
    func skipInvalidCloseValues() {
        let pair = SpreadPair(
            id: "test", name: "test", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "A", ratio: 1),
            leg2: SpreadLeg(instrumentID: "B", ratio: -1),
            unitLabel: "", description: ""
        )
        let leg1 = makeBars([(t(0), 100), (t(60), 0), (t(120), 110)])
        let leg2 = makeBars([(t(0), 90), (t(60), 80), (t(120), 95)])

        let result = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
        #expect(result.count == 2)
        #expect(result[0].openTime == t(0))
        #expect(result[1].openTime == t(120))
    }

    @Test("时间戳保留为 leg1 时间 · 输出按时间升序")
    func resultTimestampedByLeg1() {
        let pair = SpreadPair(
            id: "test", name: "test", category: .跨品种,
            leg1: SpreadLeg(instrumentID: "A", ratio: 1),
            leg2: SpreadLeg(instrumentID: "B", ratio: -1),
            unitLabel: "", description: ""
        )
        let leg1 = makeBars([(t(0), 100), (t(60), 110), (t(120), 120)])
        let leg2 = makeBars([(t(0), 90), (t(60), 95), (t(120), 100)])

        let result = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
        for i in 1..<result.count {
            #expect(result[i].openTime > result[i - 1].openTime)
        }
    }
}
