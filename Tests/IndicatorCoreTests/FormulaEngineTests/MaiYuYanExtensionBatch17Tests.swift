// 麦语言扩展函数测试（第 17 批 · ICHIMOKU 一目均衡 + DONCHIAN 通道）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 17 批 · ICHIMOKU + DONCHIAN）")
struct MaiYuYanExtensionBatch17Tests {

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

    // MARK: - ICHIMOKU

    @Test("ICHITENKAN(9) = (HHV(H,9)+LLV(L,9))/2 · 跟随趋势")
    func testICHITENKAN_tracksTrend() throws {
        let v = try run("R:ICHITENKAN(9);", bars: trendBars)[0].values
        guard let t2 = v[2], let t4 = v[4] else {
            Issue.record("ICHITENKAN 在 i=2 / i=4 应有值"); return
        }
        #expect(t4 > t2)
    }

    @Test("ICHIKIJUN(N1) = ICHITENKAN(N1) · 公式相同（仅周期不同）")
    func testICHIKIJUN_sameFormulaAsTenkan() throws {
        let t = try run("R:ICHITENKAN(5);", bars: trendBars)[0].values
        let k = try run("R:ICHIKIJUN(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(t[i] == k[i])
        }
    }

    @Test("ICHISPANA(9, 26) = (Tenkan + Kijun) / 2")
    func testICHISPANA_average() throws {
        let a = try run("R:ICHISPANA(5, 8);", bars: trendBars)[0].values
        let t = try run("R:ICHITENKAN(5);", bars: trendBars)[0].values
        let k = try run("R:ICHIKIJUN(8);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let av = a[i], let tv = t[i], let kv = k[i] else { continue }
            let expected = (tv + kv) / 2
            let diff = abs(av - expected)
            #expect(diff < Decimal(0.001))
        }
    }

    @Test("ICHISPANB(N) = ICHITENKAN(N) · 公式相同")
    func testICHISPANB_sameFormula() throws {
        let a = try run("R:ICHISPANB(7);", bars: trendBars)[0].values
        let t = try run("R:ICHITENKAN(7);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(a[i] == t[i])
        }
    }

    // MARK: - DONCHIAN

    @Test("DONCHIANU(5) = HHV(HIGH, 5)")
    func testDONCHIANU_equivalence() throws {
        let dc = try run("R:DONCHIANU(5);", bars: trendBars)[0].values
        let hhv = try run("R:HHV(HIGH, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let d = dc[i], let h = hhv[i] else { continue }
            #expect(d == h)
        }
    }

    @Test("DONCHIANL(5) = LLV(LOW, 5)")
    func testDONCHIANL_equivalence() throws {
        let dc = try run("R:DONCHIANL(5);", bars: trendBars)[0].values
        let llv = try run("R:LLV(LOW, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let d = dc[i], let l = llv[i] else { continue }
            #expect(d == l)
        }
    }

    @Test("DONCHIANM = (DONCHIANU + DONCHIANL) / 2")
    func testDONCHIANM_average() throws {
        let m = try run("R:DONCHIANM(5);", bars: trendBars)[0].values
        let u = try run("R:DONCHIANU(5);", bars: trendBars)[0].values
        let l = try run("R:DONCHIANL(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let mv = m[i], let uv = u[i], let lv = l[i] else { continue }
            let expected = (uv + lv) / 2
            let diff = abs(mv - expected)
            #expect(diff < Decimal(0.001))
        }
    }

    @Test("DONCHIANU > DONCHIANM > DONCHIANL（趋势中真实排序）")
    func testDONCHIAN_inOrder() throws {
        let u = try run("R:DONCHIANU(5);", bars: trendBars)[0].values
        let m = try run("R:DONCHIANM(5);", bars: trendBars)[0].values
        let l = try run("R:DONCHIANL(5);", bars: trendBars)[0].values
        for i in 4..<trendBars.count {
            guard let uv = u[i], let mv = m[i], let lv = l[i] else { continue }
            #expect(uv >= mv)
            #expect(mv >= lv)
        }
    }
}
