// 麦语言扩展函数测试（第 28 批 · 线性缩放 + K 线统计比率）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 28 批 · 线性缩放 + K 线统计比率）")
struct MaiYuYanExtensionBatch28Tests {

    private let mixedBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100), // 阳
        BarData(open: 11, high: 13, low: 10, close: 12, volume: 100), // 阳
        BarData(open: 12, high: 13, low: 11, close: 11, volume: 100), // 阴
        BarData(open: 11, high: 13, low: 11, close: 13, volume: 100), // 阳
        BarData(open: 13, high: 14, low: 12, close: 12, volume: 100), // 阴
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - SCALE

    @Test("SCALE(CLOSE, 11, 13, 0, 100): 11→0 · 13→100 · 12→50")
    func testSCALE_basic() throws {
        // close: 11 12 11 13 12
        let v = try run("R:SCALE(CLOSE, 11, 13, 0, 100);", bars: mixedBars)[0].values
        #expect(v[0] == 0)   // 11 → 0
        #expect(v[1] == 50)  // 12 → 50
        #expect(v[3] == 100) // 13 → 100
    }

    // MARK: - LERP

    @Test("LERP(A, B, 0) = A · LERP(A, B, 1) = B · LERP(A, B, 0.5) = (A+B)/2")
    func testLERP_basic() throws {
        let mid = try run("R:LERP(OPEN, CLOSE, 0.5+0*CLOSE);", bars: mixedBars)[0].values
        for i in 0..<mixedBars.count {
            guard let val = mid[i] else { continue }
            let expected = (mixedBars[i].open + mixedBars[i].close) / 2
            #expect(val == expected)
        }
    }

    // MARK: - GREENRATIO / REDRATIO

    @Test("GREENRATIO(5): 5 根中 3 阳 → 0.6")
    func testGREENRATIO() throws {
        let v = try run("R:GREENRATIO(5);", bars: mixedBars)[0].values
        guard let val = v[4] else {
            Issue.record("GREENRATIO 在 i=4 应有值"); return
        }
        let expected = Decimal(3) / Decimal(5)
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    @Test("REDRATIO(5): 5 根中 2 阴 → 0.4")
    func testREDRATIO() throws {
        let v = try run("R:REDRATIO(5);", bars: mixedBars)[0].values
        guard let val = v[4] else {
            Issue.record("REDRATIO 在 i=4 应有值"); return
        }
        let expected = Decimal(2) / Decimal(5)
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    @Test("GREENRATIO + REDRATIO + 平盘比 = 1（无平盘时 G+R=1）")
    func testRATIO_sum() throws {
        let g = try run("R:GREENRATIO(5);", bars: mixedBars)[0].values
        let r = try run("R:REDRATIO(5);", bars: mixedBars)[0].values
        for i in 0..<mixedBars.count {
            guard let gv = g[i], let rv = r[i] else { continue }
            // mixedBars 全部非平 · g+r=1
            let diff = abs(gv + rv - 1)
            #expect(diff < Decimal(0.001))
        }
    }

    // MARK: - AVGBODY / AVGRANGE / BODYRATIO

    @Test("AVGBODY: 平均实体大小")
    func testAVGBODY() throws {
        // mixedBars body: |C-O| = |11-10|=1, 1, 1, 2, 1 → 平均 6/5=1.2
        let v = try run("R:AVGBODY(5);", bars: mixedBars)[0].values
        guard let val = v[4] else {
            Issue.record("AVGBODY 在 i=4 应有值"); return
        }
        #expect(val == Decimal(string: "1.2")!)
    }

    @Test("AVGRANGE: 平均振幅")
    func testAVGRANGE() throws {
        // ranges: 12-9=3, 13-10=3, 13-11=2, 13-11=2, 14-12=2 → 12/5 = 2.4
        let v = try run("R:AVGRANGE(5);", bars: mixedBars)[0].values
        guard let val = v[4] else {
            Issue.record("AVGRANGE 在 i=4 应有值"); return
        }
        #expect(val == Decimal(string: "2.4")!)
    }

    @Test("BODYRATIO: AVGBODY/AVGRANGE = 1.2/2.4 = 0.5")
    func testBODYRATIO() throws {
        let v = try run("R:BODYRATIO(5);", bars: mixedBars)[0].values
        guard let val = v[4] else {
            Issue.record("BODYRATIO 在 i=4 应有值"); return
        }
        #expect(val == Decimal(string: "0.5")!)
    }

    @Test("BODYRATIO 范围 [0, 1]")
    func testBODYRATIO_inRange() throws {
        let v = try run("R:BODYRATIO(5);", bars: mixedBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1)
        }
    }
}
