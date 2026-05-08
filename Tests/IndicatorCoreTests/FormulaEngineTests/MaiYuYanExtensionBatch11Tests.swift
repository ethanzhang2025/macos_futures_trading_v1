// 麦语言扩展函数测试（第 11 批 · TYP / OC / ENVUP / ENVDN / KAMA / ZLEMA / NEAREST）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 11 批 · 兼容度 ~99.99% → ~99.995%）")
struct MaiYuYanExtensionBatch11Tests {

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

    // MARK: - TYP / OC

    @Test("TYP() = (H+L+C)/3")
    func testTYP_formula() throws {
        let v = try run("R:TYP();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            let bar = trendBars[i]
            let expected = (bar.high + bar.low + bar.close) / 3
            #expect(v[i] == expected)
        }
    }

    @Test("OC() = (O+C)/2")
    func testOC_formula() throws {
        let v = try run("R:OC();", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            let bar = trendBars[i]
            let expected = (bar.open + bar.close) / 2
            #expect(v[i] == expected)
        }
    }

    // MARK: - ENVUP / ENVDN

    @Test("ENVUP / ENVDN: 上轨 > MA > 下轨")
    func testENV_inOrder() throws {
        let up = try run("R:ENVUP(CLOSE, 5, 3);", bars: trendBars)[0].values
        let dn = try run("R:ENVDN(CLOSE, 5, 3);", bars: trendBars)[0].values
        let ma = try run("R:MA(CLOSE, 5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let u = up[i], let d = dn[i], let m = ma[i] else { continue }
            #expect(u > m, "ENVUP \(u) 应 > MA \(m) at i=\(i)")
            #expect(d < m, "ENVDN \(d) 应 < MA \(m) at i=\(i)")
        }
    }

    @Test("ENVUP(X, N, 0) = MA(X, N) · 第 N-1 根起严格相等")
    func testENVUP_zeroPercentEqualsMA() throws {
        let env = try run("R:ENVUP(CLOSE, 5, 0);", bars: trendBars)[0].values
        let ma = try run("R:MA(CLOSE, 5);", bars: trendBars)[0].values
        // MA 在前 N-1 根 nil（warm-up 限制）· ENVUP 用渐进 SMA 不限 warm-up
        // 仅比 i >= 4 之后（第 5 根起 N=5 满）
        for i in 4..<trendBars.count {
            #expect(env[i] == ma[i], "i=\(i) env=\(String(describing: env[i])) ma=\(String(describing: ma[i]))")
        }
    }

    // MARK: - KAMA

    @Test("KAMA(CLOSE, 5): 跟随趋势")
    func testKAMA_tracksTrend() throws {
        let v = try run("R:KAMA(CLOSE, 5);", bars: trendBars)[0].values
        guard let k4 = v[4] else {
            Issue.record("KAMA 在 i=4 应有值"); return
        }
        guard let k0 = v[0] else {
            Issue.record("KAMA 在 i=0 应有值"); return
        }
        #expect(k4 > k0)
    }

    @Test("KAMA: 全程有值")
    func testKAMA_allHasValues() throws {
        let v = try run("R:KAMA(CLOSE, 5);", bars: trendBars)[0].values
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - ZLEMA

    @Test("ZLEMA(CLOSE, 5): 跟随趋势")
    func testZLEMA_tracksTrend() throws {
        let v = try run("R:ZLEMA(CLOSE, 5);", bars: trendBars)[0].values
        guard let z2 = v[2], let z4 = v[4] else {
            Issue.record("ZLEMA 在 i=2 / i=4 应有值"); return
        }
        #expect(z4 > z2)
    }

    // MARK: - NEAREST

    @Test("NEAREST(CLOSE, 13): 末端值是历史最接近 13 的 close")
    func testNEAREST_findsClosest() throws {
        // 序列含 close=13.0（i=10）· 距离 13 = 0
        // 但更早 close=13.2（i=2）距离 13 = 0.2 · 后续 close=13.0 距离 0
        let v = try run("R:NEAREST(CLOSE, 13);", bars: trendBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("NEAREST 末根应有值"); return
        }
        // 最接近 13 的应该是 close=13.0（i=10）
        let diff = abs(val - 13)
        #expect(diff < Decimal(0.1), "NEAREST 应找到 ~13 · 实际 \(val)")
    }

    @Test("NEAREST(CLOSE, 1000): 极远 target · 应 fallback 到现有最大或最小")
    func testNEAREST_extremeFallback() throws {
        let v = try run("R:NEAREST(CLOSE, 1000);", bars: trendBars)[0].values
        // 所有 close 距离 1000 都很大 · 但应该挑出最接近 1000 的
        guard let val = v.last ?? nil else {
            Issue.record("NEAREST 末根应有值"); return
        }
        // 最接近 1000 的 close 是 trendBars 里 max close = 15.9
        #expect(val == Decimal(string: "15.9")!)
    }
}
