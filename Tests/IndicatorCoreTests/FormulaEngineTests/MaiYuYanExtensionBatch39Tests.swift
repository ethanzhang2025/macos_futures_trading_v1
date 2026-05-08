// 麦语言扩展函数测试（第 39 批 · 基础差值 + 中价均线）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 39 批 · 基础差值 + 中价均线）")
struct MaiYuYanExtensionBatch39Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 8, close: 11, volume: 100),
        BarData(open: 11, high: 14, low: 10, close: 13, volume: 100),
        BarData(open: 13, high: 15, low: 12, close: 14, volume: 100),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    @Test("HLDIFF() = H - L · 第一根 = 4")
    func testHLDIFF() throws {
        let v = try run("R:HLDIFF();", bars: testBars)[0].values
        #expect(v[0] == 4)  // 12-8
        #expect(v[1] == 4)  // 14-10
    }

    @Test("HCDIFF() = H - C · 第一根 = 1")
    func testHCDIFF() throws {
        let v = try run("R:HCDIFF();", bars: testBars)[0].values
        #expect(v[0] == 1)  // 12-11
        #expect(v[1] == 1)  // 14-13
    }

    @Test("CLDIFF() = C - L · 第一根 = 3")
    func testCLDIFF() throws {
        let v = try run("R:CLDIFF();", bars: testBars)[0].values
        #expect(v[0] == 3)  // 11-8
    }

    @Test("OCDIFF() = O - C · 阳线为负")
    func testOCDIFF() throws {
        let v = try run("R:OCDIFF();", bars: testBars)[0].values
        // 阳：O < C → O-C < 0
        #expect(v[0] == -1)  // 10-11
    }

    @Test("HCDIFF + CLDIFF = HLDIFF（恒等式）")
    func testHC_CL_decomposition() throws {
        let hc = try run("R:HCDIFF();", bars: testBars)[0].values
        let cl = try run("R:CLDIFF();", bars: testBars)[0].values
        let hl = try run("R:HLDIFF();", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let h = hc[i], let c = cl[i], let total = hl[i] else { continue }
            #expect(h + c == total)
        }
    }

    @Test("TPRMA(N) = MA(TYP, N) 关系（第 N-1 根起精确）")
    func testTPRMA_relationship() throws {
        let tprMA = try run("R:TPRMA(2);", bars: testBars)[0].values
        // 手动 TYP = (H+L+C)/3
        // i=0 TYP = (12+8+11)/3 = 31/3
        // i=1 TYP = (14+10+13)/3 = 37/3
        // TPRMA(2) at i=1 = (31/3 + 37/3) / 2 = 68/6 = 11.333...
        guard let val = tprMA[1] else {
            Issue.record("TPRMA 在 i=1 应有值"); return
        }
        let expected = (Decimal(31) / 3 + Decimal(37) / 3) / 2
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    @Test("HLAVGMA(N): N=1 等价 (H+L)/2")
    func testHLAVGMA_n1() throws {
        let v = try run("R:HLAVGMA(1);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let val = v[i] else { continue }
            let expected = (testBars[i].high + testBars[i].low) / 2
            #expect(val == expected)
        }
    }

    @Test("OCAVGMA(1) = (O+C)/2")
    func testOCAVGMA_n1() throws {
        let v = try run("R:OCAVGMA(1);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let val = v[i] else { continue }
            let expected = (testBars[i].open + testBars[i].close) / 2
            #expect(val == expected)
        }
    }
}
