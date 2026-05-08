// 麦语言扩展函数测试（第 36 批 · 累积统计 EXPANDING + 有效值）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 36 批 · EXPANDING 累积 + 有效值）")
struct MaiYuYanExtensionBatch36Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 12, low: 10, close: 12, volume: 100),
        BarData(open: 12, high: 12, low: 8,  close: 8,  volume: 100),
        BarData(open: 8,  high: 10, low: 8,  close: 10, volume: 100),
        BarData(open: 10, high: 15, low: 10, close: 15, volume: 100),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - EXPANDINGMEAN

    @Test("EXPANDINGMEAN(C): (10+12+8+10+15)/5 = 11")
    func testEXPANDINGMEAN() throws {
        let v = try run("R:EXPANDINGMEAN(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 10)
        #expect(v[1] == 11)  // (10+12)/2
        #expect(v[4] == 11)  // (10+12+8+10+15)/5 = 55/5 = 11
    }

    // MARK: - EXPANDINGMAX

    @Test("EXPANDINGMAX(C): 至 i=4 = 15")
    func testEXPANDINGMAX() throws {
        let v = try run("R:EXPANDINGMAX(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 10)
        #expect(v[1] == 12)
        #expect(v[2] == 12)  // 8 不更新
        #expect(v[4] == 15)
    }

    // MARK: - EXPANDINGMIN

    @Test("EXPANDINGMIN(C): 至 i=4 = 8")
    func testEXPANDINGMIN() throws {
        let v = try run("R:EXPANDINGMIN(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 10)
        #expect(v[1] == 10)  // 12 不更新
        #expect(v[2] == 8)
        #expect(v[4] == 8)
    }

    // MARK: - EXPANDINGSTD

    @Test("EXPANDINGSTD: 全程 >= 0")
    func testEXPANDINGSTD_nonNegative() throws {
        let v = try run("R:EXPANDINGSTD(CLOSE);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    // MARK: - EXPANDINGSUM

    @Test("EXPANDINGSUM(C): 累加 = 10/22/30/40/55")
    func testEXPANDINGSUM() throws {
        let v = try run("R:EXPANDINGSUM(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 10)
        #expect(v[1] == 22)
        #expect(v[2] == 30)
        #expect(v[3] == 40)
        #expect(v[4] == 55)
    }

    // MARK: - FIRSTVALID

    @Test("FIRSTVALID(C): 全程 = 第一根 close")
    func testFIRSTVALID() throws {
        let v = try run("R:FIRSTVALID(CLOSE);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 10)
        }
    }

    @Test("FIRSTVALID(REF(C, 2)): 前 2 根 nil · 从 i=2 起 = close[0]=10")
    func testFIRSTVALID_skipsLeadingNil() throws {
        let v = try run("R:FIRSTVALID(REF(CLOSE, 2));", bars: testBars)[0].values
        // i=0/1 nil（REF 前 2 根 nil）· i=2 起 = 10
        #expect(v[0] == nil)
        #expect(v[1] == nil)
        #expect(v[2] == 10)
        #expect(v[3] == 10)
        #expect(v[4] == 10)
    }

    // MARK: - LASTVALID

    @Test("LASTVALID(C): 全程 = 当前根 close（无 nil）")
    func testLASTVALID() throws {
        let v = try run("R:LASTVALID(CLOSE);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            #expect(v[i] == testBars[i].close)
        }
    }
}
