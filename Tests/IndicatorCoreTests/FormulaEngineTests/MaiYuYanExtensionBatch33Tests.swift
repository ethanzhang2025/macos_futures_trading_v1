// 麦语言扩展函数测试（第 33 批 · 综合信号 + 背离 + 评分）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 33 批 · 综合信号 + 背离 + 评分）")
struct MaiYuYanExtensionBatch33Tests {

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

    // MARK: - DIVERGENCE

    @Test("DIVERGENCE(X, X, N) = 0（自身无背离）")
    func testDIVERGENCE_selfIsZero() throws {
        let v = try run("R:DIVERGENCE(CLOSE, CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 0)
        }
    }

    @Test("DIVERGENCE: 全程值 ∈ {-1, 0, 1}")
    func testDIVERGENCE_validRange() throws {
        let v = try run("R:DIVERGENCE(CLOSE, OPEN, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == -1 || val == 0 || val == 1)
        }
    }

    // MARK: - TRENDSCORE

    @Test("TRENDSCORE(8): 上涨段 > 0 · 下跌段 < 0")
    func testTRENDSCORE_signMatchesTrend() throws {
        let v = try run("R:TRENDSCORE(8);", bars: trendBars)[0].values
        guard let tUp = v[4], let tDown = v[12] else {
            Issue.record("TRENDSCORE 在 i=4 / i=12 应有值"); return
        }
        #expect(tUp > 0)
        #expect(tDown < 0)
    }

    @Test("TRENDSCORE: 范围 ∈ [-2, 2]")
    func testTRENDSCORE_validRange() throws {
        let v = try run("R:TRENDSCORE(6);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -2 && val <= 2)
        }
    }

    // MARK: - MOMENTUMSCORE

    @Test("MOMENTUMSCORE(5): 上涨段 > 0 · 下跌段 < 0")
    func testMOMENTUMSCORE_signMatchesTrend() throws {
        let v = try run("R:MOMENTUMSCORE(5);", bars: trendBars)[0].values
        // 上涨段 i=5 close=15.9 vs i=0 close=10.8 + close > MA → 2
        // 下跌段 i=12 close=9.2 vs i=7 close=15.7 + close < MA → -2
        guard let mUp = v[5], let mDown = v[12] else {
            Issue.record("MOMENTUMSCORE 在 i=5 / i=12 应有值"); return
        }
        #expect(mUp > 0)
        #expect(mDown < 0)
    }

    // MARK: - VOLATILITYRANK

    @Test("VOLATILITYRANK(8): 范围 [0, 1]")
    func testVOLATILITYRANK_inRange() throws {
        let v = try run("R:VOLATILITYRANK(8);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1)
        }
    }

    // MARK: - PRICELEVEL

    @Test("PRICELEVEL(5): 范围 [0, 1] · 创新高 = 1 · 创新低 = 0")
    func testPRICELEVEL_extremes() throws {
        let v = try run("R:PRICELEVEL(5);", bars: trendBars)[0].values
        guard let high = v[4], let low = v[12] else {
            Issue.record("PRICELEVEL 在 i=4 / i=12 应有值"); return
        }
        #expect(high > Decimal(string: "0.9")!)  // 创新高接近 1
        #expect(low < Decimal(string: "0.1")!)   // 创新低接近 0
    }

    // MARK: - CROSSCOUNT

    @Test("CROSSCOUNT(X, X, N) = 0（自身无穿越）")
    func testCROSSCOUNT_selfIsZero() throws {
        let v = try run("R:CROSSCOUNT(CLOSE, CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 0)
        }
    }

    @Test("CROSSCOUNT: MA short vs long 至少有交叉")
    func testCROSSCOUNT_atLeastOne() throws {
        let v = try run("R:CROSSCOUNT(MA(CLOSE, 3), MA(CLOSE, 8), 16);", bars: trendBars)[0].values
        guard let last = v.last ?? nil else {
            Issue.record("CROSSCOUNT 末根应有值"); return
        }
        #expect(last >= 1)
    }

    // MARK: - SIGNALSTRENGTH

    @Test("SIGNALSTRENGTH: 全程 >= 0")
    func testSIGNALSTRENGTH_nonNegative() throws {
        let v = try run("R:SIGNALSTRENGTH(CLOSE, 8);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }
}
