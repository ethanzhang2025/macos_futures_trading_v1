// 麦语言扩展函数测试（第 42 批 · 期货专属）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 42 批 · 期货专属）")
struct MaiYuYanExtensionBatch42Tests {

    private let testBars: [BarData] = (1...10).map { i in
        BarData(open: Decimal(i), high: Decimal(i + 1), low: Decimal(i - 1),
                close: Decimal(i), volume: 100)
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - 1. BASIS

    @Test("BASIS(100, 95) = 5 · 现货升水")
    func testBASIS_positive() throws {
        let v = try run("R:BASIS(100, 95);", bars: testBars)[0].values
        #expect(v[0] == 5)
    }

    @Test("BASIS(95, 100) = -5 · 期货升水（基差为负）")
    func testBASIS_negative() throws {
        let v = try run("R:BASIS(95, 100);", bars: testBars)[0].values
        #expect(v[0] == -5)
    }

    // MARK: - 2. ROLLYIELD

    @Test("ROLLYIELD(105, 100, 73) · (5/100)/73*365 = 0.25")
    func testROLLYIELD_basic() throws {
        let v = try run("R:ROLLYIELD(105, 100, 73);", bars: testBars)[0].values
        guard let val = v[0] else { Issue.record("ROLLYIELD 应有值"); return }
        // (105-100)/100/73*365 = 5/100/73*365 = 0.25
        let diff = abs(val - Decimal(string: "0.25")!)
        #expect(diff < Decimal(0.0001))
    }

    @Test("ROLLYIELD 远月价 0 → nil")
    func testROLLYIELD_zero_far() throws {
        let v = try run("R:ROLLYIELD(100, 0, 30);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }

    // MARK: - 3. TERMSTRUCT

    @Test("TERMSTRUCT(100, 105, 110) = 1 · 升水（远 > 中 > 近）")
    func testTERMSTRUCT_contango() throws {
        let v = try run("R:TERMSTRUCT(100, 105, 110);", bars: testBars)[0].values
        #expect(v[0] == 1)
    }

    @Test("TERMSTRUCT(110, 105, 100) = -1 · 贴水（近 > 中 > 远）")
    func testTERMSTRUCT_backwardation() throws {
        let v = try run("R:TERMSTRUCT(110, 105, 100);", bars: testBars)[0].values
        #expect(v[0] == -1)
    }

    @Test("TERMSTRUCT(100, 110, 105) = 0 · 非单调")
    func testTERMSTRUCT_neutral() throws {
        let v = try run("R:TERMSTRUCT(100, 110, 105);", bars: testBars)[0].values
        #expect(v[0] == 0)
    }

    // MARK: - 4. CONTANGO

    @Test("CONTANGO(100, 105) = 1")
    func testCONTANGO_yes() throws {
        let v = try run("R:CONTANGO(100, 105);", bars: testBars)[0].values
        #expect(v[0] == 1)
    }

    @Test("CONTANGO(105, 100) = 0")
    func testCONTANGO_no() throws {
        let v = try run("R:CONTANGO(105, 100);", bars: testBars)[0].values
        #expect(v[0] == 0)
    }

    // MARK: - 5. BACKWARDATION

    @Test("BACKWARDATION(105, 100) = 1 · CONTANGO 的反")
    func testBACKWARDATION_yes() throws {
        let v = try run("R:BACKWARDATION(105, 100);", bars: testBars)[0].values
        #expect(v[0] == 1)
    }

    @Test("CONTANGO 与 BACKWARDATION 互斥（不平时和为 1）")
    func testCONTANGO_BACKWARDATION_exclusive() throws {
        let c = try run("R:CONTANGO(100, 105);", bars: testBars)[0].values
        let b = try run("R:BACKWARDATION(100, 105);", bars: testBars)[0].values
        // 100 != 105 → 必有一个 1
        if let cv = c[0], let bv = b[0] {
            #expect(cv + bv == 1)
        }
    }

    // MARK: - 6. CONTRACTSPREAD

    @Test("CONTRACTSPREAD(105, 100) = 5 · 跨月价差正")
    func testCONTRACTSPREAD_positive() throws {
        let v = try run("R:CONTRACTSPREAD(105, 100);", bars: testBars)[0].values
        #expect(v[0] == 5)
    }

    // MARK: - 7. FRONTMONTH

    @Test("FRONTMONTH(100, 50, 30) = 1 · 第 1 主力")
    func testFRONTMONTH_first() throws {
        let v = try run("R:FRONTMONTH(100, 50, 30);", bars: testBars)[0].values
        #expect(v[0] == 1)
    }

    @Test("FRONTMONTH(50, 200, 100) = 2 · 第 2 主力")
    func testFRONTMONTH_second() throws {
        let v = try run("R:FRONTMONTH(50, 200, 100);", bars: testBars)[0].values
        #expect(v[0] == 2)
    }

    @Test("FRONTMONTH(10, 20, 300) = 3 · 第 3 主力")
    func testFRONTMONTH_third() throws {
        let v = try run("R:FRONTMONTH(10, 20, 300);", bars: testBars)[0].values
        #expect(v[0] == 3)
    }

    @Test("FRONTMONTH(0, 0, 0) = nil · 全无量")
    func testFRONTMONTH_all_zero() throws {
        let v = try run("R:FRONTMONTH(0, 0, 0);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }
}
