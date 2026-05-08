// 麦语言扩展函数测试（第 8 批 · CMO / AROONOSC / VWMA / NVI / AVGPRICE / MEDPRICE / WC）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 8 批 · 兼容度 ~99.95% → ~99.97%）")
struct MaiYuYanExtensionBatch8Tests {

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

    // MARK: - CMO

    @Test("CMO(5): 范围 [-100, 100]")
    func testCMO_inRange() throws {
        let v = try run("R:CMO(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -100 && val <= 100, "CMO 应在 [-100, 100] · 实际 \(val)")
        }
    }

    @Test("CMO(5): 上涨段 > 0 · 下跌段 < 0")
    func testCMO_signMatchesTrend() throws {
        let v = try run("R:CMO(5);", bars: trendBars)[0].values
        guard let cmoUp = v[4], let cmoDown = v[12] else {
            Issue.record("CMO 在 i=4 / i=12 应有值"); return
        }
        #expect(cmoUp > 0)
        #expect(cmoDown < 0)
    }

    // MARK: - AROONOSC

    @Test("AROONOSC(5): 上涨段 > 0 · 下跌段 < 0")
    func testAROONOSC_signMatchesTrend() throws {
        let v = try run("R:AROONOSC(5);", bars: trendBars)[0].values
        guard let aoUp = v[4], let aoDown = v[12] else {
            Issue.record("AROONOSC 在 i=4 / i=12 应有值"); return
        }
        #expect(aoUp > 0)
        #expect(aoDown < 0)
    }

    @Test("AROONOSC(5): 范围 [-100, 100]")
    func testAROONOSC_inRange() throws {
        let v = try run("R:AROONOSC(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -100 && val <= 100, "AROONOSC 应在 [-100, 100] · 实际 \(val)")
        }
    }

    // MARK: - VWMA

    @Test("VWMA(CLOSE, 5): 跟随趋势")
    func testVWMA_tracksTrend() throws {
        let v = try run("R:VWMA(CLOSE, 5);", bars: trendBars)[0].values
        guard let vw2 = v[2], let vw4 = v[4] else {
            Issue.record("VWMA 在 i=2 / i=4 应有值"); return
        }
        #expect(vw4 > vw2)
    }

    // MARK: - NVI

    @Test("NVI(): 第一根 = 1000")
    func testNVI_firstIs1000() throws {
        let v = try run("R:NVI();", bars: trendBars)[0].values
        #expect(v[0] == 1000)
    }

    @Test("NVI(): 全程有值")
    func testNVI_allHasValues() throws {
        let v = try run("R:NVI();", bars: trendBars)[0].values
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - AVGPRICE

    @Test("AVGPRICE() = (O+H+L+C)/4")
    func testAVGPRICE_formula() throws {
        let v = try run("R:AVGPRICE();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            let bar = trendBars[i]
            let expected = (bar.open + bar.high + bar.low + bar.close) / 4
            #expect(v[i] == expected, "AVGPRICE at i=\(i) 应 = \(expected)")
        }
    }

    // MARK: - MEDPRICE

    @Test("MEDPRICE() = (H+L)/2")
    func testMEDPRICE_formula() throws {
        let v = try run("R:MEDPRICE();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            let bar = trendBars[i]
            let expected = (bar.high + bar.low) / 2
            #expect(v[i] == expected)
        }
    }

    // MARK: - WC

    @Test("WC() = (H+L+2C)/4")
    func testWC_formula() throws {
        let v = try run("R:WC();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            let bar = trendBars[i]
            let expected = (bar.high + bar.low + 2 * bar.close) / 4
            #expect(v[i] == expected)
        }
    }
}
