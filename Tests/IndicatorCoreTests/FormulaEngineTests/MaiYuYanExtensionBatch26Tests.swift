// 麦语言扩展函数测试（第 26 批 · 盈亏统计）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 26 批 · 盈亏统计 · 组合管理）")
struct MaiYuYanExtensionBatch26Tests {

    // 序列：close 10/12/11/13/15/14/12/11/13/12（5 涨 4 跌）
    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 13, low: 10, close: 12, volume: 100), // +2
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 100), // -1
        BarData(open: 11, high: 14, low: 11, close: 13, volume: 100), // +2
        BarData(open: 13, high: 16, low: 13, close: 15, volume: 100), // +2
        BarData(open: 15, high: 16, low: 13, close: 14, volume: 100), // -1
        BarData(open: 14, high: 14, low: 11, close: 12, volume: 100), // -2
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 100), // -1
        BarData(open: 11, high: 14, low: 11, close: 13, volume: 100), // +2
        BarData(open: 13, high: 14, low: 11, close: 12, volume: 100), // -1
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - GAINS

    @Test("GAINS(9): 5 涨累计 = 2+2+2+2 = 8")
    func testGAINS() throws {
        // 排除 i=0 → 比较 9 次（i=1..9）· 4 次涨（+2/+2/+2/+2）· 1 次大涨 i=8
        // 涨：i=1(+2) i=3(+2) i=4(+2) i=8(+2) = 8
        let v = try run("R:GAINS(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("GAINS 在 i=9 应有值"); return
        }
        #expect(val == 8)
    }

    // MARK: - LOSSES

    @Test("LOSSES(9): 跌累计 = 1+1+2+1+1 = 6")
    func testLOSSES() throws {
        let v = try run("R:LOSSES(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("LOSSES 在 i=9 应有值"); return
        }
        #expect(val == 6)
    }

    // MARK: - WINRATE

    @Test("WINRATE(9): 4 涨 / 9 总 ≈ 0.444")
    func testWINRATE() throws {
        let v = try run("R:WINRATE(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("WINRATE 在 i=9 应有值"); return
        }
        let expected = Decimal(4) / Decimal(9)
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    @Test("WINRATE(N): 范围 [0, 1]")
    func testWINRATE_inRange() throws {
        let v = try run("R:WINRATE(5);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1, "WINRATE 应在 [0, 1] · 实际 \(val)")
        }
    }

    // MARK: - AVGUP / AVGDOWN

    @Test("AVGUP(9) = 8 / 4 = 2")
    func testAVGUP() throws {
        let v = try run("R:AVGUP(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("AVGUP 在 i=9 应有值"); return
        }
        #expect(val == 2)
    }

    @Test("AVGDOWN(9) = 6 / 5 = 1.2")
    func testAVGDOWN() throws {
        let v = try run("R:AVGDOWN(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("AVGDOWN 在 i=9 应有值"); return
        }
        #expect(val == Decimal(string: "1.2")!)
    }

    // MARK: - PROFITRATIO

    @Test("PROFITRATIO(9) = AVGUP/AVGDOWN = 2/1.2 ≈ 1.667")
    func testPROFITRATIO() throws {
        let v = try run("R:PROFITRATIO(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("PROFITRATIO 在 i=9 应有值"); return
        }
        let expected = Decimal(2) / Decimal(string: "1.2")!
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - EXPECTANCY

    @Test("EXPECTANCY(9) = 4/9 * 2 - 5/9 * 1.2 ≈ 0.222")
    func testEXPECTANCY() throws {
        let v = try run("R:EXPECTANCY(9);", bars: testBars)[0].values
        guard let val = v[9] else {
            Issue.record("EXPECTANCY 在 i=9 应有值"); return
        }
        // (4/9)*2 - (5/9)*1.2 = 0.8889 - 0.6667 = 0.2222
        let expected = (Decimal(4) / Decimal(9) * 2) - (Decimal(5) / Decimal(9) * Decimal(string: "1.2")!)
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }
}
