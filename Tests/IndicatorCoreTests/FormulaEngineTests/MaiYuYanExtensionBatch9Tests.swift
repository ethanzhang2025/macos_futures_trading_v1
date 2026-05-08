// 麦语言扩展函数测试（第 9 批 · PSAR / PVI / ULTOSC / STOCHRSI / WAD / HD / LD）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 9 批 · 兼容度 ~99.97% → ~99.98%）")
struct MaiYuYanExtensionBatch9Tests {

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

    // MARK: - PSAR

    @Test("PSAR(): 上涨段 SAR 在 close 之下 · 下跌段 SAR 在 close 之上")
    func testPSAR_basicBehavior() throws {
        let v = try run("R:PSAR();", bars: trendBars)[0].values
        // 上涨段（i=4）SAR 应低于 close
        guard let sarUp = v[4] else {
            Issue.record("PSAR 在 i=4 应有值"); return
        }
        #expect(sarUp < trendBars[4].close)
        // 下跌段（i=12）SAR 应高于 close
        guard let sarDown = v[12] else {
            Issue.record("PSAR 在 i=12 应有值"); return
        }
        #expect(sarDown > trendBars[12].close)
    }

    @Test("PSAR(): 全程有值")
    func testPSAR_allHasValues() throws {
        let v = try run("R:PSAR();", bars: trendBars)[0].values
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - PVI

    @Test("PVI(): 第一根 = 1000")
    func testPVI_firstIs1000() throws {
        let v = try run("R:PVI();", bars: trendBars)[0].values
        #expect(v[0] == 1000)
    }

    // MARK: - ULTOSC

    @Test("ULTOSC(7, 14, 28): 范围 [0, 100]")
    func testULTOSC_inRange() throws {
        let v = try run("R:ULTOSC(7, 14, 28);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "ULTOSC 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - STOCHRSI

    @Test("STOCHRSI(5): 范围 [0, 100]")
    func testSTOCHRSI_inRange() throws {
        let v = try run("R:STOCHRSI(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "STOCHRSI 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - WAD

    @Test("WAD(): 第一根 = 0 · 上涨段累加 · 下跌段回落")
    func testWAD_cumulative() throws {
        let v = try run("R:WAD();", bars: trendBars)[0].values
        #expect(v[0] == 0)
        guard let w4 = v[4], let w12 = v[12] else {
            Issue.record("WAD 在 i=4 / i=12 应有值"); return
        }
        #expect(w4 > 0)
        #expect(w12 < w4)
    }

    // MARK: - HD / LD

    @Test("HD() = HIGH - REF(HIGH, 1)")
    func testHD_formula() throws {
        let v = try run("R:HD();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            let expected = trendBars[i].high - trendBars[i - 1].high
            #expect(v[i] == expected, "HD at i=\(i) 应 = \(expected)")
        }
    }

    @Test("LD() = REF(LOW, 1) - LOW")
    func testLD_formula() throws {
        let v = try run("R:LD();", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            let expected = trendBars[i - 1].low - trendBars[i].low
            #expect(v[i] == expected, "LD at i=\(i) 应 = \(expected)")
        }
    }

    @Test("HD()/LD(): 第一根 nil")
    func testHDLD_firstNil() throws {
        let hd = try run("R:HD();", bars: trendBars)[0].values
        let ld = try run("R:LD();", bars: trendBars)[0].values
        #expect(hd[0] == nil)
        #expect(ld[0] == nil)
    }
}
