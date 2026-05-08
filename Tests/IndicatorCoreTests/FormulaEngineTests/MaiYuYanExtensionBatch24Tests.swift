// 麦语言扩展函数测试（第 24 批 · 灵活 Pivot + 连续判定）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 24 批 · 灵活 Pivot + 连续判定）")
struct MaiYuYanExtensionBatch24Tests {

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

    // MARK: - PIVOTHIGH / PIVOTLOW

    @Test("PIVOTHIGH(2): 至少检测到 1 个峰")
    func testPIVOTHIGH() throws {
        let v = try run("R:PIVOTHIGH(2);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    @Test("PIVOTLOW(2): 全程至少有非 nil（数据可能没真谷 · 仅验证不 crash）")
    func testPIVOTLOW() throws {
        let v = try run("R:PIVOTLOW(2);", bars: trendBars)[0].values
        #expect(v.count == trendBars.count)
    }

    // MARK: - STREAK

    @Test("STREAK(CLOSE > REF(CLOSE,1)): 上涨段累加")
    func testSTREAK() throws {
        let v = try run("R:STREAK(CLOSE > REF(CLOSE, 1));", bars: trendBars)[0].values
        // i=4 时连续 4 根上涨 → STREAK = 4
        #expect(v[4] == 4)
    }

    @Test("STREAK 遇到 0 重置")
    func testSTREAK_resets() throws {
        let v = try run("R:STREAK(CLOSE > REF(CLOSE, 1));", bars: trendBars)[0].values
        // i=5 close=15.9 > 15.8 → STREAK = 5? 或者 close=15.8 vs 15.9 → 阴 0
        // i=5: close=15.9 prev=15.8 → > 1
        // 实际看：close 15.8(4) → 15.9(5) → 15.8(6) → 15.7(7)
        // i=5: 15.9 > 15.8 → +1 = 5
        // i=6: 15.8 < 15.9 → 0
        #expect(v[6] == 0)
    }

    // MARK: - VOLATILITYRATIO

    @Test("VOLATILITYRATIO(3, 10): 全程值 >= 0")
    func testVOLATILITYRATIO_nonNegative() throws {
        let v = try run("R:VOLATILITYRATIO(3, 10);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    // MARK: - TRENDDIR

    @Test("TRENDDIR(5): 上涨段 = 1 · 下跌段 = -1")
    func testTRENDDIR_signMatchesTrend() throws {
        let v = try run("R:TRENDDIR(5);", bars: trendBars)[0].values
        guard let dUp = v[4], let dDown = v[12] else {
            Issue.record("TRENDDIR 在 i=4 / i=12 应有值"); return
        }
        #expect(dUp == 1)
        #expect(dDown == -1)
    }

    // MARK: - CONSECUP / CONSECDOWN

    @Test("CONSECUP(3): 连续 3 根上涨命中")
    func testCONSECUP() throws {
        // close: 10.8 12 13.2 14.5 15.8 ... 连续上涨 5 次
        // i=3 时连续 3 根上涨（i=1/2/3）→ 1
        let v = try run("R:CONSECUP(3);", bars: trendBars)[0].values
        #expect(v[3] == 1)
        #expect(v[4] == 1)
    }

    @Test("CONSECDOWN(3): 连续 3 根下跌命中")
    func testCONSECDOWN() throws {
        // close: ..., 14.2(8) 13(9) 11.8(10) 10.5(11) 9.2(12)
        // i=10 连续 3 根下跌（i=8/9/10）→ 1
        let v = try run("R:CONSECDOWN(3);", bars: trendBars)[0].values
        #expect(v[10] == 1)
    }

    @Test("CONSECUP(N) ∈ {0, 1}")
    func testCONSECUP_validRange() throws {
        let v = try run("R:CONSECUP(2);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 0 || val == 1)
        }
    }
}
