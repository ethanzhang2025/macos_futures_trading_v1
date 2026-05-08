// 麦语言扩展函数测试（第 10 批 · PIVOT / R1 / S1 / CR / WVAD / AROONL / AROONS）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 10 批 · 兼容度 ~99.98% → ~99.99%）")
struct MaiYuYanExtensionBatch10Tests {

    private let trendBars: [BarData] = [
        BarData(open: 10.0, high: 11.0, low: 9.5,  close: 10.8, volume: 100),
        BarData(open: 10.8, high: 12.2, low: 10.5, close: 12.0, volume: 110),
        BarData(open: 12.0, high: 13.5, low: 11.8, close: 13.2, volume: 120),
        BarData(open: 13.2, high: 14.8, low: 13.0, close: 14.5, volume: 130),
        BarData(open: 14.5, high: 16.0, low: 14.3, close: 15.8, volume: 140),
        BarData(open: 15.8, high: 16.2, low: 15.5, close: 15.9, volume: 90),
        BarData(open: 15.9, high: 16.1, low: 15.6, close: 15.8, volume: 85),
        BarData(open: 15.8, high: 16.0, low: 15.5, close: 15.7, volume: 80),
        BarData(open: 15.7, high: 15.7, low: 14.0, close: 14.2, volume: 150),
        BarData(open: 14.2, high: 14.5, low: 12.8, close: 13.0, volume: 160),
        BarData(open: 13.0, high: 13.2, low: 11.5, close: 11.8, volume: 170),
        BarData(open: 11.8, high: 12.0, low: 10.3, close: 10.5, volume: 180),
        BarData(open: 10.5, high: 10.8, low: 9.0,  close: 9.2,  volume: 190),
        BarData(open: 9.2,  high: 9.5,  low: 9.0,  close: 9.3,  volume: 80),
        BarData(open: 9.3,  high: 9.6,  low: 9.1,  close: 9.4,  volume: 85),
        BarData(open: 9.4,  high: 9.5,  low: 9.0,  close: 9.2,  volume: 75),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - PIVOT / R1 / S1

    @Test("PIVOT() = (REF(H,1)+REF(L,1)+REF(C,1))/3")
    func testPIVOT_formula() throws {
        let v = try run("R:PIVOT();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            let prev = trendBars[i - 1]
            let expected = (prev.high + prev.low + prev.close) / 3
            #expect(v[i] == expected, "PIVOT at i=\(i) 应 = \(expected)")
        }
    }

    @Test("R1() = 2*PIVOT - REF(L,1) · 应 > PIVOT")
    func testR1_aboveBaseline() throws {
        let pivot = try run("R:PIVOT();", bars: trendBars)[0].values
        let r1 = try run("R:R1();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            guard let p = pivot[i], let r = r1[i] else { continue }
            #expect(r > p, "R1 \(r) 应 > PIVOT \(p) at i=\(i)")
        }
    }

    @Test("S1() = 2*PIVOT - REF(H,1) · 应 < PIVOT")
    func testS1_belowBaseline() throws {
        let pivot = try run("R:PIVOT();", bars: trendBars)[0].values
        let s1 = try run("R:S1();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            guard let p = pivot[i], let s = s1[i] else { continue }
            #expect(s < p, "S1 \(s) 应 < PIVOT \(p) at i=\(i)")
        }
    }

    // MARK: - CR

    @Test("CR(5): 上涨段 > 下跌段")
    func testCR_uptrendHigher() throws {
        let v = try run("R:CR(5);", bars: trendBars)[0].values
        guard let crUp = v[4], let crDown = v[12] else {
            Issue.record("CR 在 i=4 / i=12 应有值"); return
        }
        #expect(crUp > crDown)
    }

    @Test("CR(N): 全程值 >= 0")
    func testCR_nonNegative() throws {
        let v = try run("R:CR(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0, "CR 应 >= 0 · 实际 \(val)")
        }
    }

    // MARK: - WVAD

    @Test("WVAD(5): 上涨段 > 0 · 下跌段 < 0")
    func testWVAD_signMatchesTrend() throws {
        let v = try run("R:WVAD(5);", bars: trendBars)[0].values
        guard let wUp = v[4], let wDown = v[12] else {
            Issue.record("WVAD 在 i=4 / i=12 应有值"); return
        }
        #expect(wUp > 0)
        #expect(wDown < 0)
    }

    // MARK: - AROONL / AROONS

    @Test("AROONL(5): 范围 [0, 100]")
    func testAROONL_inRange() throws {
        let v = try run("R:AROONL(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "AROONL 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("AROONL(5): 上涨段 = 100（创新高根）")
    func testAROONL_atHighIs100() throws {
        // i=4 close=15.8 high=16.0 是窗口最高 → AROONL = 100
        let v = try run("R:AROONL(5);", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("AROONL 在 i=4 应有值"); return
        }
        #expect(val == 100)
    }

    @Test("AROONS(5): 下跌段 = 100（创新低根）")
    func testAROONS_atLowIs100() throws {
        // i=12 low=9.0 是窗口最低 → AROONS = 100
        let v = try run("R:AROONS(5);", bars: trendBars)[0].values
        guard let val = v[12] else {
            Issue.record("AROONS 在 i=12 应有值"); return
        }
        #expect(val == 100)
    }

    @Test("AROONL - AROONS 等价 AROONOSC")
    func testAROON_compositionEqualsOSC() throws {
        let l = try run("R:AROONL(5);", bars: trendBars)[0].values
        let s = try run("R:AROONS(5);", bars: trendBars)[0].values
        let osc = try run("R:AROONOSC(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let lv = l[i], let sv = s[i], let ov = osc[i] else { continue }
            let diff = abs((lv - sv) - ov)
            #expect(diff < Decimal(0.001), "AROONL-AROONS \(lv - sv) 应 = AROONOSC \(ov) at i=\(i)")
        }
    }
}
