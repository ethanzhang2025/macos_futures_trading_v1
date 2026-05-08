// 麦语言扩展函数测试（第 23 批 · 趋势信号 · 金死叉/支撑阻力/新高新低/回调）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 23 批 · 趋势信号）")
struct MaiYuYanExtensionBatch23Tests {

    // 趋势序列（与之前批次共用模式）
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

    // MARK: - GOLDENCROSS / DEADCROSS

    @Test("GOLDENCROSS(3, 7): 全程值 ∈ {0, 1}")
    func testGOLDENCROSS_validRange() throws {
        let v = try run("R:GOLDENCROSS(3, 7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 0 || val == 1, "GOLDENCROSS 应 ∈ {0,1} · 实际 \(val)")
        }
    }

    @Test("DEADCROSS(3, 7): 上涨转下跌过程至少有一次死叉")
    func testDEADCROSS_atLeastOne() throws {
        let v = try run("R:DEADCROSS(3, 7);", bars: trendBars)[0].values
        let crosses = v.compactMap { $0 }.filter { $0 == 1 }.count
        #expect(crosses >= 1)
    }

    @Test("DEADCROSS 反向 = GOLDENCROSS 翻转参数")
    func testCROSS_swappedSymmetry() throws {
        // GOLDENCROSS(N1, N2) = DEADCROSS(N2, N1)（参数互换）
        let g = try run("R:GOLDENCROSS(5, 3);", bars: trendBars)[0].values
        let d = try run("R:DEADCROSS(3, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let gv = g[i], let dv = d[i] else { continue }
            #expect(gv == dv, "GOLDENCROSS(N1,N2) 应 = DEADCROSS(N2,N1) at i=\(i)")
        }
    }

    // MARK: - SUPPORT / RESISTANCE

    @Test("SUPPORT(N) = LLV(LOW, N)")
    func testSUPPORT_equivalence() throws {
        let s = try run("R:SUPPORT(5);", bars: trendBars)[0].values
        let llv = try run("R:LLV(LOW, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(s[i] == llv[i])
        }
    }

    @Test("RESISTANCE(N) = HHV(HIGH, N)")
    func testRESISTANCE_equivalence() throws {
        let r = try run("R:RESISTANCE(5);", bars: trendBars)[0].values
        let hhv = try run("R:HHV(HIGH, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(r[i] == hhv[i])
        }
    }

    // MARK: - NEWHIGH / NEWLOW

    @Test("NEWHIGH(5): 上涨段创新高")
    func testNEWHIGH_inUptrend() throws {
        let v = try run("R:NEWHIGH(5);", bars: trendBars)[0].values
        // i=4 close=15.8 > 历史 close（i=0..3 max=14.5）→ 1
        guard let val = v[4] else {
            Issue.record("NEWHIGH 在 i=4 应有值"); return
        }
        #expect(val == 1)
    }

    @Test("NEWLOW(5): 下跌段创新低")
    func testNEWLOW_inDowntrend() throws {
        let v = try run("R:NEWLOW(5);", bars: trendBars)[0].values
        // i=12 close=9.2 是窗口最低（远低于 i=8..11 的 close）
        guard let val = v[12] else {
            Issue.record("NEWLOW 在 i=12 应有值"); return
        }
        #expect(val == 1)
    }

    // MARK: - PULLBACK

    @Test("PULLBACK(5, 30): 下跌段触发 30% 回调")
    func testPULLBACK_inDowntrend() throws {
        let v = try run("R:PULLBACK(5, 30);", bars: trendBars)[0].values
        // i=12 HHV(H,5) = max(15.7,15.7,14.5,12,10.8) = 15.7 · close=9.2 → drop=(15.7-9.2)/15.7=41% > 30%
        guard let val = v[12] else {
            Issue.record("PULLBACK 在 i=12 应有值"); return
        }
        #expect(val == 1)
    }

    @Test("PULLBACK(5, 30): 上涨段无回调")
    func testPULLBACK_inUptrend() throws {
        let v = try run("R:PULLBACK(5, 30);", bars: trendBars)[0].values
        // i=4 创新高 · drop=0 → 0
        guard let val = v[4] else {
            Issue.record("PULLBACK 在 i=4 应有值"); return
        }
        #expect(val == 0)
    }
}
