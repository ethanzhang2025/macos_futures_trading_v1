// 麦语言扩展函数测试（第 34 批 · Heiken-Ashi + SAR 方向 + 价格行为）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 34 批 · Heiken-Ashi + SAR 方向）")
struct MaiYuYanExtensionBatch34Tests {

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

    // MARK: - HA series

    @Test("HACLOSE() = (O+H+L+C)/4 · 与 AVGPRICE 等价")
    func testHACLOSE_equalsAVGPRICE() throws {
        let hac = try run("R:HACLOSE();", bars: trendBars)[0].values
        let avg = try run("R:AVGPRICE();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(hac[i] == avg[i])
        }
    }

    @Test("HAHIGH >= HACLOSE >= HALOW（K 线一致性）")
    func testHA_inOrder() throws {
        let h = try run("R:HAHIGH();", bars: trendBars)[0].values
        let c = try run("R:HACLOSE();", bars: trendBars)[0].values
        let l = try run("R:HALOW();", bars: trendBars)[0].values
        let o = try run("R:HAOPEN();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let hv = h[i], let cv = c[i], let lv = l[i], let ov = o[i] else { continue }
            #expect(hv >= cv && hv >= ov)
            #expect(lv <= cv && lv <= ov)
        }
    }

    @Test("HAOPEN[i] = (HAOPEN[i-1] + HACLOSE[i-1]) / 2 from i=1")
    func testHAOPEN_recurrence() throws {
        let o = try run("R:HAOPEN();", bars: trendBars)[0].values
        let c = try run("R:HACLOSE();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            guard let oi = o[i], let oPrev = o[i - 1], let cPrev = c[i - 1] else { continue }
            let expected = (oPrev + cPrev) / 2
            let diff = abs(oi - expected)
            #expect(diff < Decimal(0.001))
        }
    }

    @Test("HADIR() ∈ {-1, 0, 1}")
    func testHADIR_validRange() throws {
        let v = try run("R:HADIR();", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == -1 || val == 0 || val == 1)
        }
    }

    @Test("HADIR(): 上涨段 ≈ 1（HA 阳线占多数）")
    func testHADIR_uptrend() throws {
        let v = try run("R:HADIR();", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("HADIR 在 i=4 应有值"); return
        }
        #expect(val == 1)
    }

    // MARK: - SARDIR

    @Test("SARDIR() ∈ {-1, 1}")
    func testSARDIR_validRange() throws {
        let v = try run("R:SARDIR();", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 1 || val == -1)
        }
    }

    @Test("SARDIR(): 上涨段 = 1 · 下跌段 = -1")
    func testSARDIR_signMatchesTrend() throws {
        let v = try run("R:SARDIR();", bars: trendBars)[0].values
        guard let up = v[4], let down = v[12] else {
            Issue.record("SARDIR 在 i=4 / i=12 应有值"); return
        }
        #expect(up == 1)
        #expect(down == -1)
    }

    // MARK: - PRICEACTION

    @Test("PRICEACTION(8): 范围 ∈ [-3, 3]")
    func testPRICEACTION_validRange() throws {
        let v = try run("R:PRICEACTION(8);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -3 && val <= 3)
        }
    }

    @Test("PRICEACTION(8): 上涨段 > 0 · 下跌段 < 0")
    func testPRICEACTION_signMatchesTrend() throws {
        let v = try run("R:PRICEACTION(8);", bars: trendBars)[0].values
        guard let up = v[4], let down = v[12] else {
            Issue.record("PRICEACTION 在 i=4 / i=12 应有值"); return
        }
        #expect(up > 0)
        #expect(down < 0)
    }
}
