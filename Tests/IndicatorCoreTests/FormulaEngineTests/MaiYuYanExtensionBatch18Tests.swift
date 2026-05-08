// 麦语言扩展函数测试（第 18 批 · KELCH/STARC + MAR/CYCLE）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 18 批 · Keltner/Starc/MAR/CYCLE）")
struct MaiYuYanExtensionBatch18Tests {

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

    // MARK: - KELCH

    @Test("KELCHU > KELCHM > KELCHL")
    func testKELCH_inOrder() throws {
        let u = try run("R:KELCHU(5, 1.5);", bars: trendBars)[0].values
        let m = try run("R:KELCHM(5);", bars: trendBars)[0].values
        let l = try run("R:KELCHL(5, 1.5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let uv = u[i], let mv = m[i], let lv = l[i] else { continue }
            #expect(uv > mv, "KELCHU \(uv) 应 > KELCHM \(mv)")
            #expect(mv > lv, "KELCHM \(mv) 应 > KELCHL \(lv)")
        }
    }

    @Test("KELCHM(N) = EMA(CLOSE, N)")
    func testKELCHM_equivalence() throws {
        let km = try run("R:KELCHM(5);", bars: trendBars)[0].values
        let em = try run("R:EMA(CLOSE, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(km[i] == em[i])
        }
    }

    // MARK: - STARC

    @Test("STARCU > STARCL")
    func testSTARC_inOrder() throws {
        let u = try run("R:STARCU(5, 1.5);", bars: trendBars)[0].values
        let l = try run("R:STARCL(5, 1.5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let uv = u[i], let lv = l[i] else { continue }
            #expect(uv > lv)
        }
    }

    @Test("STARCU(N, 0) = MA(CLOSE, N) · K=0 退化为中线")
    func testSTARCU_zeroKEqualsMA() throws {
        let u = try run("R:STARCU(5, 0);", bars: trendBars)[0].values
        // STARC 中线是 MA · 与第 N 根起 MA 一致
        for i in 4..<trendBars.count {
            let manual = try run("R:MA(CLOSE, 5);", bars: trendBars)[0].values
            #expect(u[i] == manual[i])
        }
    }

    // MARK: - MAR

    @Test("MAR(CLOSE, N): 上涨段 > 1 · 下跌段 < 1")
    func testMAR_signMatchesTrend() throws {
        let v = try run("R:MAR(CLOSE, 5);", bars: trendBars)[0].values
        guard let mUp = v[4], let mDown = v[12] else {
            Issue.record("MAR 在 i=4 / i=12 应有值"); return
        }
        #expect(mUp > 1)
        #expect(mDown < 1)
    }

    // MARK: - CYCLE

    @Test("CYCLE(5): 范围 [0, 1]")
    func testCYCLE_inRange() throws {
        let v = try run("R:CYCLE(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1, "CYCLE 应在 [0, 1] · 实际 \(val)")
        }
    }

    @Test("CYCLE * 100 = STOCH（关系验证）")
    func testCYCLE_relatedToSTOCH() throws {
        let cycle = try run("R:CYCLE(5);", bars: trendBars)[0].values
        let stoch = try run("R:STOCH(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let c = cycle[i], let s = stoch[i] else { continue }
            let diff = abs(c * 100 - s)
            #expect(diff < Decimal(0.001), "CYCLE*100 \(c*100) ≠ STOCH \(s) at i=\(i)")
        }
    }
}
