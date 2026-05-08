// 麦语言扩展函数测试（第 6 批 · PSY / BIAS / VR / DPO / HMA / DEMA / OSC）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 6 批 · 兼容度 ~99.8% → ~99.9%）")
struct MaiYuYanExtensionBatch6Tests {

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

    // MARK: - PSY

    @Test("PSY(5): 范围 [0, 100]")
    func testPSY_inRange() throws {
        let v = try run("R:PSY(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "PSY 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("PSY(5): 上涨段 PSY 应明显高于下跌段")
    func testPSY_uptrendHigher() throws {
        let v = try run("R:PSY(5);", bars: trendBars)[0].values
        guard let psyUp = v[4], let psyDown = v[12] else {
            Issue.record("PSY 在 i=4 / i=12 应有值"); return
        }
        #expect(psyUp > psyDown, "上涨段 PSY=\(psyUp) 应 > 下跌段 PSY=\(psyDown)")
    }

    // MARK: - BIAS

    @Test("BIAS(5): 上涨段 > 0 · 下跌段 < 0")
    func testBIAS_signMatchesTrend() throws {
        let v = try run("R:BIAS(5);", bars: trendBars)[0].values
        guard let biasUp = v[4], let biasDown = v[12] else {
            Issue.record("BIAS 在 i=4 / i=12 应有值"); return
        }
        #expect(biasUp > 0)
        #expect(biasDown < 0)
    }

    // MARK: - VR

    @Test("VR(5): 上涨段 VR 高于下跌段")
    func testVR_uptrendHigher() throws {
        let v = try run("R:VR(5);", bars: trendBars)[0].values
        guard let vrUp = v[4], let vrDown = v[12] else {
            Issue.record("VR 在 i=4 / i=12 应有值"); return
        }
        #expect(vrUp > vrDown)
    }

    // MARK: - DPO

    @Test("DPO(5): 第一根足够 nil")
    func testDPO_initialNil() throws {
        let v = try run("R:DPO(5);", bars: trendBars)[0].values
        // shift = 5/2 + 1 = 3 · 前 3 根都该 nil
        #expect(v[0] == nil)
        #expect(v[1] == nil)
        #expect(v[2] == nil)
    }

    @Test("DPO(5): 末段下跌 close 远低于均线 → DPO < 0")
    func testDPO_negativeInDowntrend() throws {
        let v = try run("R:DPO(5);", bars: trendBars)[0].values
        // i=12 close=9.2 是下跌末段最低 · DPO 与 MA 之差应为负
        guard let dpo = v[12] else {
            Issue.record("DPO 在 i=12 应有值"); return
        }
        #expect(dpo < 0)
    }

    // MARK: - HMA

    @Test("HMA(4): 跟随上涨趋势")
    func testHMA_tracksTrend() throws {
        let v = try run("R:HMA(4);", bars: trendBars)[0].values
        guard let h2 = v[2], let h4 = v[4] else {
            Issue.record("HMA 在 i=2 / i=4 应有值"); return
        }
        #expect(h4 > h2, "上涨段 HMA 应递增 · h4=\(h4) h2=\(h2)")
    }

    @Test("HMA(N): 至少返回非 nil 值")
    func testHMA_hasValues() throws {
        let v = try run("R:HMA(4);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - DEMA

    @Test("DEMA(CLOSE, 3): 常量序列 DEMA 收敛常量")
    func testDEMA_constantConverges() throws {
        let v = try run("R:DEMA(7+0*CLOSE, 3);", bars: trendBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("DEMA 末根应有值"); return
        }
        let diff = abs(val - 7)
        #expect(diff < Decimal(0.001), "DEMA(常量) 应 = 常量 · 实际 \(val)")
    }

    @Test("DEMA: 跟随上涨")
    func testDEMA_tracksTrend() throws {
        let v = try run("R:DEMA(CLOSE, 3);", bars: trendBars)[0].values
        guard let d2 = v[2], let d4 = v[4] else {
            Issue.record("DEMA 在 i=2 / i=4 应有值"); return
        }
        #expect(d4 > d2)
    }

    // MARK: - OSC

    @Test("OSC(3, 7): 上涨段 > 0 · 下跌段 < 0（短期 MA 偏离）")
    func testOSC_signMatchesTrend() throws {
        let v = try run("R:OSC(3, 7);", bars: trendBars)[0].values
        guard let oscUp = v[4], let oscDown = v[12] else {
            Issue.record("OSC 在 i=4 / i=12 应有值"); return
        }
        #expect(oscUp > 0)
        #expect(oscDown < 0)
    }
}
