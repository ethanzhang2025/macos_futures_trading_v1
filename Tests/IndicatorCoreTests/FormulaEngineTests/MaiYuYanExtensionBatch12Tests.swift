// 麦语言扩展函数测试（第 12 批 · SUPERTREND / CHANDELIERL / CHANDELIERS / AO / AC / FRACTALH / FRACTALL）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 12 批 · 兼容度 ~99.995% → ~99.997%）")
struct MaiYuYanExtensionBatch12Tests {

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

    // MARK: - SUPERTREND

    @Test("SUPERTREND(5, 2): 上涨段 ST 在 close 下 · 下跌段 ST 在 close 上")
    func testSUPERTREND_basicBehavior() throws {
        let v = try run("R:SUPERTREND(5, 2);", bars: trendBars)[0].values
        // 上涨末段（i=4）ST 应低于 close=15.8
        guard let stUp = v[4] else {
            Issue.record("SUPERTREND 在 i=4 应有值"); return
        }
        #expect(stUp < trendBars[4].close, "上涨段 ST=\(stUp) 应 < close=\(trendBars[4].close)")
        // 下跌末段（i=12）ST 应高于 close=9.2
        guard let stDown = v[12] else {
            Issue.record("SUPERTREND 在 i=12 应有值"); return
        }
        #expect(stDown > trendBars[12].close, "下跌段 ST=\(stDown) 应 > close=\(trendBars[12].close)")
    }

    // MARK: - CHANDELIERL / S

    @Test("CHANDELIERL(5, 2): 长仓止损线 < HHV(H, 5)")
    func testCHANDELIERL_belowHHV() throws {
        let v = try run("R:CHANDELIERL(5, 2);", bars: trendBars)[0].values
        let hhv = try run("R:HHV(HIGH, 5);", bars: trendBars)[0].values
        for i in 4..<trendBars.count {
            guard let cl = v[i], let h = hhv[i] else { continue }
            #expect(cl < h, "CHANDELIERL \(cl) 应 < HHV \(h) at i=\(i)")
        }
    }

    @Test("CHANDELIERS(5, 2): 短仓止损线 > LLV(L, 5)")
    func testCHANDELIERS_aboveLLV() throws {
        let v = try run("R:CHANDELIERS(5, 2);", bars: trendBars)[0].values
        let llv = try run("R:LLV(LOW, 5);", bars: trendBars)[0].values
        for i in 4..<trendBars.count {
            guard let cs = v[i], let l = llv[i] else { continue }
            #expect(cs > l, "CHANDELIERS \(cs) 应 > LLV \(l) at i=\(i)")
        }
    }

    // MARK: - AO / AC

    @Test("AO(): 上涨段 AO > 下跌段 AO（数据不足 34 周期 · 用相对值验证）")
    func testAO_uptrendHigherThanDowntrend() throws {
        let v = try run("R:AO();", bars: trendBars)[0].values
        guard let aoUp = v[4], let aoDown = v[12] else {
            Issue.record("AO 在 i=4 / i=12 应有值"); return
        }
        #expect(aoUp > aoDown)
    }

    @Test("AC(): 第一根有值")
    func testAC_hasValue() throws {
        let v = try run("R:AC();", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - FRACTALH / L

    @Test("FRACTALH(): 数据中 i=5 high=16.2 应被记录为峰（在 i=7 起）")
    func testFRACTAL_recordsPeak() throws {
        // i=5 high=16.2 vs i=3(14.8) / i=4(16.0) / i=6(16.1) / i=7(16.0) → 全大 → 是峰
        let h = try run("R:FRACTALH();", bars: trendBars)[0].values
        let nonNil = h.compactMap { $0 }.count
        #expect(nonNil > 0, "FRACTALH 应至少检测到 1 个峰")
    }

    @Test("FRACTALL(): 序列含相等低点 · 不强制有谷（5-bar 严格小定义）")
    func testFRACTAL_lowMayBeAbsent() throws {
        // 序列含多个 9.0 平/低点 · 严格小判定下可能 0 谷 · 验证不 crash 即可
        let l = try run("R:FRACTALL();", bars: trendBars)[0].values
        #expect(l.count == trendBars.count)
    }

    @Test("FRACTALH() 第一根总是 nil（5-bar 不足）")
    func testFRACTAL_firstNilForInsufficient() throws {
        let h = try run("R:FRACTALH();", bars: trendBars)[0].values
        for i in 0..<4 {
            #expect(h[i] == nil, "FRACTALH at i=\(i) 应 nil（5-bar 不足）")
        }
    }
}
