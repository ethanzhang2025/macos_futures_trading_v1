// 麦语言扩展函数测试（第 14 批 · MACDDIF/DEA/BAR · BOLLM/U/L · KDJK）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 14 批 · MACD/BOLL/KDJ 三件套）")
struct MaiYuYanExtensionBatch14Tests {

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

    // MARK: - MACD

    @Test("MACDDIF(5,10): 上涨段 DIF > 下跌段 DIF（数据 16 根 · 用相对值）")
    func testMACDDIF_relativeTrend() throws {
        let v = try run("R:MACDDIF(5, 10);", bars: trendBars)[0].values
        guard let difUp = v[4], let difDown = v[12] else {
            Issue.record("MACDDIF 在 i=4 / i=12 应有值"); return
        }
        #expect(difUp > difDown)
    }

    @Test("MACDDIF(F,S) = EMA(C,F) - EMA(C,S)")
    func testMACDDIF_equivalence() throws {
        let dif = try run("R:MACDDIF(5, 10);", bars: trendBars)[0].values
        let manual = try run("R:EMA(CLOSE, 5) - EMA(CLOSE, 10);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(dif[i] == manual[i])
        }
    }

    @Test("MACDBAR(F,S,M) = 2*(DIF - DEA)")
    func testMACDBAR_equivalence() throws {
        let bar = try run("R:MACDBAR(5, 10, 3);", bars: trendBars)[0].values
        let manual = try run(
            "R:2*(MACDDIF(5,10) - MACDDEA(5,10,3));",
            bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let b = bar[i], let m = manual[i] else { continue }
            let diff = abs(b - m)
            #expect(diff < Decimal(0.001), "MACDBAR \(b) ≠ 2*(DIF-DEA) \(m) at i=\(i)")
        }
    }

    // MARK: - BOLL

    @Test("BOLLU > BOLLM > BOLLL")
    func testBOLL_inOrder() throws {
        let u = try run("R:BOLLU(5, 2);", bars: trendBars)[0].values
        let m = try run("R:BOLLM(5);", bars: trendBars)[0].values
        let l = try run("R:BOLLL(5, 2);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let uv = u[i], let mv = m[i], let lv = l[i] else { continue }
            #expect(uv >= mv, "BOLLU \(uv) 应 >= BOLLM \(mv) at i=\(i)")
            #expect(mv >= lv, "BOLLM \(mv) 应 >= BOLLL \(lv) at i=\(i)")
        }
    }

    @Test("BOLLM(N) = MA(CLOSE, N)")
    func testBOLLM_equivalence() throws {
        let bm = try run("R:BOLLM(5);", bars: trendBars)[0].values
        // MA 在 warm-up 阶段 nil · BOLLM 用渐进 MA · 第 N 根起一致
        for i in 4..<trendBars.count {
            let manual = try run("R:MA(CLOSE, 5);", bars: trendBars)[0].values
            #expect(bm[i] == manual[i])
        }
    }

    @Test("BOLLU(N, 0) = BOLLM(N)（K=0 退化为中线）")
    func testBOLLU_zeroKEqualsM() throws {
        let u = try run("R:BOLLU(5, 0);", bars: trendBars)[0].values
        let m = try run("R:BOLLM(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(u[i] == m[i])
        }
    }

    // MARK: - KDJK

    @Test("KDJK(9, 3): 范围 [0, 100]")
    func testKDJK_inRange() throws {
        let v = try run("R:KDJK(9, 3);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "KDJK 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("KDJK(9, 3): 跟随趋势")
    func testKDJK_tracksTrend() throws {
        let v = try run("R:KDJK(9, 3);", bars: trendBars)[0].values
        guard let kUp = v[4], let kDown = v[12] else {
            Issue.record("KDJK 在 i=4 / i=12 应有值"); return
        }
        #expect(kUp > kDown)
    }
}
