// 麦语言扩展函数测试（第 35 批 · 数学辅助函数）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 35 批 · 数学辅助）")
struct MaiYuYanExtensionBatch35Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 12, low: 10, close: 12, volume: 100),
        BarData(open: 12, high: 12, low: 8,  close: 8,  volume: 100),
        BarData(open: 8,  high: 10, low: 8,  close: 10, volume: 100),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    @Test("POSITIVE(C - 10): 正部")
    func testPOSITIVE() throws {
        let v = try run("R:POSITIVE(CLOSE - 10);", bars: testBars)[0].values
        #expect(v[0] == 0)   // 10-10=0
        #expect(v[1] == 2)   // 12-10=2
        #expect(v[2] == 0)   // 8-10=-2 → 0
    }

    @Test("NEGATIVE(C - 10): 负部")
    func testNEGATIVE() throws {
        let v = try run("R:NEGATIVE(CLOSE - 10);", bars: testBars)[0].values
        #expect(v[0] == 0)
        #expect(v[1] == 0)
        #expect(v[2] == -2)  // 8-10=-2
    }

    @Test("POSITIVE + NEGATIVE = X")
    func testPOS_NEG_decomposition() throws {
        let p = try run("R:POSITIVE(CLOSE - 10);", bars: testBars)[0].values
        let n = try run("R:NEGATIVE(CLOSE - 10);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let pv = p[i], let nv = n[i] else { continue }
            let sum = pv + nv
            let expected = testBars[i].close - 10
            #expect(sum == expected)
        }
    }

    @Test("CLIP(C, 9, 11): 限值")
    func testCLIP() throws {
        let v = try run("R:CLIP(CLOSE, 9, 11);", bars: testBars)[0].values
        #expect(v[0] == 10)  // 10 不变
        #expect(v[1] == 11)  // 12 → 11
        #expect(v[2] == 9)   // 8 → 9
    }

    @Test("HEAVISIDE: X>=0 → 1 / X<0 → 0")
    func testHEAVISIDE() throws {
        let v = try run("R:HEAVISIDE(CLOSE - 10);", bars: testBars)[0].values
        #expect(v[0] == 1)   // 0 >= 0 → 1
        #expect(v[1] == 1)
        #expect(v[2] == 0)   // -2 < 0
    }

    @Test("SQUARED(2) = 4 / SQUARED(-3) = 9")
    func testSQUARED() throws {
        let v = try run("R:SQUARED(CLOSE - 10);", bars: testBars)[0].values
        #expect(v[0] == 0)
        #expect(v[1] == 4)
        #expect(v[2] == 4)   // (-2)² = 4
    }

    @Test("CUBED(2) = 8 / CUBED(-2) = -8")
    func testCUBED() throws {
        let v = try run("R:CUBED(CLOSE - 10);", bars: testBars)[0].values
        #expect(v[1] == 8)
        #expect(v[2] == -8)
    }

    @Test("INVERT(2) = 0.5 / INVERT(0) = nil")
    func testINVERT() throws {
        let v = try run("R:INVERT(CLOSE - 10);", bars: testBars)[0].values
        // 0 → nil
        #expect(v[0] == nil)
        // 2 → 0.5
        #expect(v[1] == Decimal(string: "0.5")!)
    }
}
