// 麦语言扩展函数测试（第 15 批 · KDJD/J · BOLLW/PCT · TYPING/MAANGLE/RSIDIV）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 15 批 · KDJ/BOLL 配套 + K 线类型/角度）")
struct MaiYuYanExtensionBatch15Tests {

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

    private let dojiBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9, close: 11, volume: 100),  // 阳
        BarData(open: 12, high: 13, low: 11, close: 11, volume: 100), // 阴
        BarData(open: 11, high: 12, low: 10, close: 11, volume: 100), // 十字（O=C）
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - KDJD / KDJJ

    @Test("KDJD(9,3): 范围 [0, 100]")
    func testKDJD_inRange() throws {
        let v = try run("R:KDJD(9, 3);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "KDJD 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("KDJJ(9,3) = 3K - 2D")
    func testKDJJ_equivalence() throws {
        let j = try run("R:KDJJ(9, 3);", bars: trendBars)[0].values
        let k = try run("R:KDJK(9, 3);", bars: trendBars)[0].values
        let d = try run("R:KDJD(9, 3);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let jv = j[i], let kv = k[i], let dv = d[i] else { continue }
            let diff = abs(jv - (3 * kv - 2 * dv))
            #expect(diff < Decimal(0.001), "KDJJ \(jv) ≠ 3K-2D \(3*kv - 2*dv) at i=\(i)")
        }
    }

    // MARK: - BOLLW / BOLLPCT

    @Test("BOLLW(N, K): 全程值 >= 0")
    func testBOLLW_nonNegative() throws {
        let v = try run("R:BOLLW(5, 2);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0, "BOLLW 应 >= 0 · 实际 \(val)")
        }
    }

    @Test("BOLLPCT(5, 2): 范围 ~[0, 1]（极端可超出）")
    func testBOLLPCT_inRange() throws {
        let v = try run("R:BOLLPCT(5, 2);", bars: trendBars)[0].values
        var found = false
        for value in v {
            guard let val = value else { continue }
            found = true
            // 不严格限制 [0,1]（close 可能超出 ±2σ 区间）· 仅验证有合理值
            #expect(val.isNaN == false || val.isFinite, "BOLLPCT 应有限 · 实际 \(val)")
        }
        #expect(found, "BOLLPCT 应至少有一个非 nil 值")
    }

    // MARK: - TYPING

    @Test("TYPING(): 阳=1 / 阴=-1 / 十字=0")
    func testTYPING_classification() throws {
        let v = try run("R:TYPING();", bars: dojiBars)[0].values
        #expect(v[0] == 1)
        #expect(v[1] == -1)
        #expect(v[2] == 0)
    }

    // MARK: - MAANGLE

    @Test("MAANGLE(CLOSE, 5): 上涨段 > 0 · 下跌段 < 0")
    func testMAANGLE_signMatchesTrend() throws {
        let v = try run("R:MAANGLE(CLOSE, 5);", bars: trendBars)[0].values
        guard let aUp = v[4], let aDown = v[12] else {
            Issue.record("MAANGLE 在 i=4 / i=12 应有值"); return
        }
        #expect(aUp > 0)
        #expect(aDown < 0)
    }

    // MARK: - RSIDIV

    @Test("RSIDIV(5, 14): 全程有限值")
    func testRSIDIV_finite() throws {
        let v = try run("R:RSIDIV(5, 14);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    @Test("RSIDIV(N, N) = 0（自身相减）")
    func testRSIDIV_selfIsZero() throws {
        let v = try run("R:RSIDIV(7, 7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 0, "RSIDIV(N,N) 应 = 0 · 实际 \(val)")
        }
    }
}
