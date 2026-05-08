// 麦语言扩展函数测试（第 7 批 · VWAP / EMV / MASS / CHO / VHF / BBI / PVT）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 7 批 · 兼容度 ~99.9% → ~99.95%）")
struct MaiYuYanExtensionBatch7Tests {

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

    // MARK: - VWAP

    @Test("VWAP(5): 跟随趋势")
    func testVWAP_tracksTrend() throws {
        let v = try run("R:VWAP(5);", bars: trendBars)[0].values
        guard let v2 = v[2], let v4 = v[4] else {
            Issue.record("VWAP 在 i=2 / i=4 应有值"); return
        }
        #expect(v4 > v2)
    }

    @Test("VWAP(N): 介于 LLV(L,N) 和 HHV(H,N) 之间")
    func testVWAP_inHLRange() throws {
        let v = try run("R:VWAP(5);", bars: trendBars)[0].values
        for i in 5..<trendBars.count {
            guard let val = v[i] else { continue }
            let start = max(0, i - 4)
            var hi: Decimal = trendBars[start].high
            var lo: Decimal = trendBars[start].low
            for j in start...i {
                if trendBars[j].high > hi { hi = trendBars[j].high }
                if trendBars[j].low < lo { lo = trendBars[j].low }
            }
            #expect(val >= lo && val <= hi, "VWAP \(val) 应在 [\(lo), \(hi)] at i=\(i)")
        }
    }

    // MARK: - EMV

    @Test("EMV(5): 上涨末段 > 0（量小价升）")
    func testEMV_signMatchesTrend() throws {
        let v = try run("R:EMV(5);", bars: trendBars)[0].values
        // 上涨段 close > prev close · MID > 0 · BR > 0 · EMV > 0
        guard let emvUp = v[4] else {
            Issue.record("EMV 在 i=4 应有值"); return
        }
        #expect(emvUp > 0)
    }

    // MARK: - MASS

    @Test("MASS(3, 5): 第一根足够 nil · 后续有值")
    func testMASS_hasValues() throws {
        let v = try run("R:MASS(3, 5);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - CHO

    @Test("CHO(3, 7): 上涨段 > 下跌段")
    func testCHO_uptrendHigher() throws {
        let v = try run("R:CHO(3, 7);", bars: trendBars)[0].values
        guard let choUp = v[4], let choDown = v[12] else {
            Issue.record("CHO 在 i=4 / i=12 应有值"); return
        }
        #expect(choUp > choDown)
    }

    // MARK: - VHF

    @Test("VHF(5): 取值 > 0（趋势越强越接近 1）")
    func testVHF_positive() throws {
        let v = try run("R:VHF(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val > 0 && val <= 1, "VHF 应在 (0, 1] · 实际 \(val)")
        }
    }

    // MARK: - BBI

    @Test("BBI(): 跟随趋势")
    func testBBI_tracksTrend() throws {
        let v = try run("R:BBI();", bars: trendBars)[0].values
        guard let b2 = v[2], let b4 = v[4] else {
            Issue.record("BBI 在 i=2 / i=4 应有值"); return
        }
        #expect(b4 > b2)
    }

    @Test("BBI(): 第一根有值（即使周期不足也按现有数据算）")
    func testBBI_firstHasValue() throws {
        let v = try run("R:BBI();", bars: trendBars)[0].values
        #expect(v[0] != nil)
    }

    // MARK: - PVT

    @Test("PVT(): 第一根 = 0 · 上涨段累加")
    func testPVT_cumulative() throws {
        let v = try run("R:PVT();", bars: trendBars)[0].values
        #expect(v[0] == 0)
        guard let p4 = v[4] else {
            Issue.record("PVT 在 i=4 应有值"); return
        }
        #expect(p4 > 0)
    }

    @Test("PVT(): 下跌段 PVT 回落")
    func testPVT_fallsInDowntrend() throws {
        let v = try run("R:PVT();", bars: trendBars)[0].values
        guard let p4 = v[4], let p12 = v[12] else {
            Issue.record("PVT 在 i=4 / i=12 应有值"); return
        }
        #expect(p12 < p4)
    }
}
