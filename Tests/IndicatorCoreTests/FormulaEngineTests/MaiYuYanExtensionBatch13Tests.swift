// 麦语言扩展函数测试（第 13 批 · RSI / STOCH / VOLR / VOSC / DKX / HV / ATRPCT）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 13 批 · 兼容度 ~99.997% → ~99.999%）")
struct MaiYuYanExtensionBatch13Tests {

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

    // MARK: - RSI

    @Test("RSI(7): 范围 [0, 100]")
    func testRSI_inRange() throws {
        let v = try run("R:RSI(7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "RSI 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("RSI(7): 上涨段 > 50 · 下跌段 < 50")
    func testRSI_signMatchesTrend() throws {
        let v = try run("R:RSI(7);", bars: trendBars)[0].values
        guard let rsiUp = v[4], let rsiDown = v[12] else {
            Issue.record("RSI 在 i=4 / i=12 应有值"); return
        }
        #expect(rsiUp > 50)
        #expect(rsiDown < 50)
    }

    // MARK: - STOCH

    @Test("STOCH(5): 范围 [0, 100]")
    func testSTOCH_inRange() throws {
        let v = try run("R:STOCH(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "STOCH 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("STOCH = 100 - WR · 验证关系")
    func testSTOCH_inverseOfWR() throws {
        let stoch = try run("R:STOCH(5);", bars: trendBars)[0].values
        let wr = try run("R:WR(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let s = stoch[i], let w = wr[i] else { continue }
            let diff = abs((s + w) - 100)
            #expect(diff < Decimal(0.001), "STOCH+WR 应=100 · 实际 \(s+w) at i=\(i)")
        }
    }

    // MARK: - VOLR

    @Test("VOLR(5): 巨量根 > 100 · 萎缩根 < 100")
    func testVOLR_relativeVolume() throws {
        let v = try run("R:VOLR(5);", bars: trendBars)[0].values
        // i=4 vol=140 vs MA(vol,5)=120 → > 100
        // i=7 vol=80 vs MA(vol,5)=104 → < 100
        guard let big = v[4], let small = v[7] else {
            Issue.record("VOLR 在 i=4 / i=7 应有值"); return
        }
        #expect(big > 100, "i=4 量大 VOLR=\(big) 应 > 100")
        #expect(small < 100, "i=7 量小 VOLR=\(small) 应 < 100")
    }

    // MARK: - VOSC

    @Test("VOSC(3, 5): 短周期量大于长周期量时 > 0")
    func testVOSC_signFollowsRecentVolume() throws {
        let v = try run("R:VOSC(3, 5);", bars: trendBars)[0].values
        // i=12 短期 3 根 vol=170/180/190 (近期巨量 · 下跌爆量)
        // 长期 5 根 vol=160/170/180/190 + 80（早期）→ 平均较低 → VOSC > 0
        guard let val = v[12] else {
            Issue.record("VOSC 在 i=12 应有值"); return
        }
        #expect(val > 0)
    }

    // MARK: - DKX

    @Test("DKX(): 跟随趋势")
    func testDKX_tracksTrend() throws {
        let v = try run("R:DKX();", bars: trendBars)[0].values
        guard let d2 = v[2], let d4 = v[4] else {
            Issue.record("DKX 在 i=2 / i=4 应有值"); return
        }
        #expect(d4 > d2)
    }

    @Test("DKX(): 全程有值（即使 < 20 根也按现有数据算）")
    func testDKX_alwaysHasValue() throws {
        let v = try run("R:DKX();", bars: trendBars)[0].values
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - HV

    @Test("HV(5): 全程值 >= 0")
    func testHV_nonNegative() throws {
        let v = try run("R:HV(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0, "HV 应 >= 0 · 实际 \(val)")
        }
    }

    // MARK: - ATRPCT

    @Test("ATRPCT(5): 全程值 >= 0")
    func testATRPCT_nonNegative() throws {
        let v = try run("R:ATRPCT(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0, "ATRPCT 应 >= 0 · 实际 \(val)")
        }
    }
}
