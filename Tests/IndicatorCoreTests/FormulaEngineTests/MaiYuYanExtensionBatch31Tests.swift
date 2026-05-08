// 麦语言扩展函数测试（第 31 批 · K 线细节统计）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 31 批 · K 线细节统计）")
struct MaiYuYanExtensionBatch31Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100),  // 阳 · 上影 1 / 下影 1
        BarData(open: 13, high: 14, low: 12, close: 13.5, volume: 100), // 跳空向上 (13 > 11)
        BarData(open: 13.5, high: 14, low: 11, close: 11.5, volume: 100), // 阴 · 长下影
        BarData(open: 11, high: 13, low: 11, close: 13, volume: 100), // 跳空向下 (11 < 11.5) 阳
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - GAPSIZE

    @Test("GAPSIZE: 跳空 = O - REF(C, 1)")
    func testGAPSIZE() throws {
        let v = try run("R:GAPSIZE();", bars: testBars)[0].values
        // i=1 O=13 prevC=11 → 2
        #expect(v[1] == 2)
        // i=3 O=11 prevC=11.5 → -0.5
        #expect(v[3] == Decimal(string: "-0.5")!)
    }

    // MARK: - BODYPCT

    @Test("BODYPCT: 阳=正 / 阴=负")
    func testBODYPCT() throws {
        let v = try run("R:BODYPCT();", bars: testBars)[0].values
        // i=0 O=10 C=11 → (1/10)*100=10
        #expect(v[0] == 10)
        // i=2 O=13.5 C=11.5 → (-2/13.5)*100 ≈ -14.81
        guard let v2 = v[2] else { return }
        #expect(v2 < 0)
    }

    // MARK: - UPPERWICK / LOWERWICK

    @Test("UPPERWICK / LOWERWICK")
    func testWICKS() throws {
        let upper = try run("R:UPPERWICK();", bars: testBars)[0].values
        let lower = try run("R:LOWERWICK();", bars: testBars)[0].values
        // i=0 阳 O=10 C=11 H=12 L=9 · upper=12-11=1 · lower=10-9=1
        #expect(upper[0] == 1)
        #expect(lower[0] == 1)
    }

    @Test("UPPERWICK + LOWERWICK + body = H - L")
    func testWICKS_decomposition() throws {
        let upper = try run("R:UPPERWICK();", bars: testBars)[0].values
        let lower = try run("R:LOWERWICK();", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let u = upper[i], let l = lower[i] else { continue }
            let body = abs(testBars[i].close - testBars[i].open)
            let totalRange = testBars[i].high - testBars[i].low
            let diff = abs(u + l + body - totalRange)
            #expect(diff < Decimal(0.001))
        }
    }

    // MARK: - WICKRATIO

    @Test("WICKRATIO: 平衡时 = 1")
    func testWICKRATIO_balanced() throws {
        let v = try run("R:WICKRATIO();", bars: testBars)[0].values
        // i=0 upper=1 lower=1 → ratio=1
        #expect(v[0] == 1)
    }

    // MARK: - PRICEDIST

    @Test("PRICEDIST: |X - target|")
    func testPRICEDIST() throws {
        let v = try run("R:PRICEDIST(CLOSE, 12);", bars: testBars)[0].values
        // close=11 → |11-12|=1
        #expect(v[0] == 1)
        // close=13.5 → |13.5-12|=1.5
        #expect(v[1] == Decimal(string: "1.5")!)
    }

    // MARK: - RANGEPCT

    @Test("RANGEPCT(N): 全程 >= 0")
    func testRANGEPCT_nonNegative() throws {
        let v = try run("R:RANGEPCT(3);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }
}
