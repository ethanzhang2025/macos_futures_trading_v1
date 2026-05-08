// 麦语言扩展函数测试（第 25 批 · 数学 SIN/COS/ATAN/PI + 风险 MAXDD/MAXDDPCT/DRAWDOWN）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 25 批 · 数学完备 + 最大回撤）")
struct MaiYuYanExtensionBatch25Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 12, low: 10, close: 12, volume: 100),  // 峰
        BarData(open: 12, high: 12, low: 8,  close: 8,  volume: 100),  // 跌
        BarData(open: 8,  high: 10, low: 8,  close: 10, volume: 100),  // 反弹
        BarData(open: 10, high: 15, low: 10, close: 15, volume: 100),  // 新高
        BarData(open: 15, high: 15, low: 6,  close: 6,  volume: 100),  // 大跌
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - 数学

    @Test("SIN(0) ≈ 0")
    func testSIN_zero() throws {
        let v = try run("R:SIN(0+0*CLOSE);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(abs(val) < Decimal(0.001))
        }
    }

    @Test("COS(0) ≈ 1")
    func testCOS_zero() throws {
        let v = try run("R:COS(0+0*CLOSE);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(abs(val - 1) < Decimal(0.001))
        }
    }

    @Test("ATAN(0) = 0")
    func testATAN_zero() throws {
        let v = try run("R:ATAN(0+0*CLOSE);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(abs(val) < Decimal(0.001))
        }
    }

    @Test("PI() ≈ 3.14159")
    func testPI() throws {
        let v = try run("R:PI();", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            let diff = abs(val - Decimal(Double.pi))
            #expect(diff < Decimal(0.001))
        }
    }

    @Test("SIN²+COS² = 1")
    func testSINCOS_identity() throws {
        let s = try run("R:SIN(CLOSE);", bars: testBars)[0].values
        let c = try run("R:COS(CLOSE);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let sv = s[i], let cv = c[i] else { continue }
            let sumSq = sv * sv + cv * cv
            let diff = abs(sumSq - 1)
            #expect(diff < Decimal(0.001), "SIN²+COS² 应=1 · 实际 \(sumSq) at i=\(i)")
        }
    }

    // MARK: - MAXDD / MAXDDPCT / DRAWDOWN

    @Test("MAXDD(CLOSE): 全程单调非降")
    func testMAXDD_monotonic() throws {
        let v = try run("R:MAXDD(CLOSE);", bars: testBars)[0].values
        var prev: Decimal = 0
        for value in v {
            guard let val = value else { continue }
            #expect(val >= prev, "MAXDD 应单调非降")
            prev = val
        }
    }

    @Test("MAXDD: i=5 close=6 高=15 → MAXDD=9")
    func testMAXDD_value() throws {
        let v = try run("R:MAXDD(CLOSE);", bars: testBars)[0].values
        guard let val = v[5] else {
            Issue.record("MAXDD 在 i=5 应有值"); return
        }
        #expect(val == 9)
    }

    @Test("MAXDDPCT: i=5 (15-6)/15 = 60%")
    func testMAXDDPCT_value() throws {
        let v = try run("R:MAXDDPCT(CLOSE);", bars: testBars)[0].values
        guard let val = v[5] else {
            Issue.record("MAXDDPCT 在 i=5 应有值"); return
        }
        let diff = abs(val - 60)
        #expect(diff < Decimal(0.001))
    }

    @Test("DRAWDOWN: i=5 = 15 - 6 = 9 · i=4 = 15 - 15 = 0")
    func testDRAWDOWN_currentValue() throws {
        let v = try run("R:DRAWDOWN(CLOSE);", bars: testBars)[0].values
        #expect(v[4] == 0)  // 创新高时 DD=0
        #expect(v[5] == 9)  // 跌至 6 · 高 15 · DD=9
    }
}
