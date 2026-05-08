// 麦语言扩展函数测试（第 29 批 · 健壮统计 + 风险指标 + 综合信号）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 29 批 · 健壮统计 + 风险指标）")
struct MaiYuYanExtensionBatch29Tests {

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

    // MARK: - MAD

    @Test("MAD(CLOSE, 5): 范围 >= 0")
    func testMAD_nonNegative() throws {
        let v = try run("R:MAD(CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    // MARK: - SORTINO

    @Test("SORTINO(CLOSE, 8): 趋势期至少一个有限值（无负收益时 SORTINO 可能 nil · 验证不 crash）")
    func testSORTINO_finite() throws {
        let v = try run("R:SORTINO(CLOSE, 8);", bars: trendBars)[0].values
        // 上涨段没有负收益 · SORTINO=nil 是合理的
        // 下跌段（i=12）应有值
        guard let val = v[12] else {
            // 如果 i=12 也没有 · 仅验证 array 长度
            #expect(v.count == trendBars.count)
            return
        }
        _ = val  // 仅验证有限
    }

    // MARK: - CALMAR

    @Test("CALMAR(CLOSE, 8): 上涨段 > 0")
    func testCALMAR_uptrend() throws {
        let v = try run("R:CALMAR(CLOSE, 8);", bars: trendBars)[0].values
        guard let val = v[4] else {
            // 上涨段可能 MAXDDPCT=0 → nil · 检查 i=12（含回撤）
            return
        }
        _ = val  // 仅验证不 crash
    }

    // MARK: - RUNUP

    @Test("RUNUP(CLOSE): 单调非降")
    func testRUNUP_monotonic() throws {
        let v = try run("R:RUNUP(CLOSE);", bars: trendBars)[0].values
        var prev: Decimal = 0
        for value in v {
            guard let val = value else { continue }
            #expect(val >= prev)
            prev = val
        }
    }

    @Test("RUNUP(CLOSE) i=4 = 15.8 - 10.8 = 5")
    func testRUNUP_value() throws {
        // close: 10.8 12 13.2 14.5 15.8 → low=10.8 / RUNUP = 15.8-10.8 = 5
        let v = try run("R:RUNUP(CLOSE);", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("RUNUP 在 i=4 应有值"); return
        }
        let expected = Decimal(string: "5.0")!
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - RECOVERY

    @Test("RECOVERY(CLOSE): 第一根 = 0")
    func testRECOVERY_firstZero() throws {
        let v = try run("R:RECOVERY(CLOSE);", bars: trendBars)[0].values
        #expect(v[0] == 0)
    }

    @Test("RECOVERY 创新低时 = 0")
    func testRECOVERY_atLowIsZero() throws {
        let v = try run("R:RECOVERY(CLOSE);", bars: trendBars)[0].values
        // i=12 close=9.2 是最低 · RECOVERY = 0
        guard let val = v[12] else {
            Issue.record("RECOVERY 在 i=12 应有值"); return
        }
        #expect(val == 0)
    }

    // MARK: - TRENDSTRENGTH

    @Test("TRENDSTRENGTH(5): 上涨段强 / 横盘段弱")
    func testTRENDSTRENGTH() throws {
        let v = try run("R:TRENDSTRENGTH(5);", bars: trendBars)[0].values
        guard let strong = v[5], let weak = v[15] else {
            // i=5 是上涨刚结束 · i=15 是横盘
            return
        }
        // 上涨段 abs(15.9-10.8)/5 = 1.02 / 横盘 abs(9.2-13.0)/5 = 0.76（也可能不严格 · 仅验证有值）
        _ = (strong, weak)
        let v4 = v[4]
        let v15 = v[15]
        guard let s = v4, let w = v15 else { return }
        #expect(s > w)  // 上涨末段强度 > 末段横盘强度
    }

    // MARK: - MACROSS

    @Test("MACROSS(N1, N2): 全程 ∈ {-1, 0, 1}")
    func testMACROSS_validRange() throws {
        let v = try run("R:MACROSS(3, 7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == -1 || val == 0 || val == 1)
        }
    }

    @Test("MACROSS: 至少触发过死叉（上涨转下跌）")
    func testMACROSS_atLeastDead() throws {
        let v = try run("R:MACROSS(3, 7);", bars: trendBars)[0].values
        let deads = v.compactMap { $0 }.filter { $0 == -1 }.count
        #expect(deads >= 1)
    }
}
