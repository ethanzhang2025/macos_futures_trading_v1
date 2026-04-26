// 麦语言扩展函数测试（第 1 批 · NOT / CROSSDOWN / MOD / PEAKBARS / TROUGHBARS）
// 通过 Lexer + Parser + Interpreter 端到端跑公式 · 与项目其他 FormulaEngine 测试同风格

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 1 批 · 兼容度 85% → ~90%）")
struct MaiYuYanExtensionFunctionTests {

    // CLOSE 序列：11,12,13,14,15,14,13,12,11,10（单峰：i=4 close=15 是波峰）
    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100),
        BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
        BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        BarData(open: 13, high: 15, low: 12, close: 14, volume: 180),
        BarData(open: 14, high: 16, low: 13, close: 15, volume: 220),
        BarData(open: 15, high: 17, low: 14, close: 14, volume: 190),
        BarData(open: 14, high: 15, low: 12, close: 13, volume: 210),
        BarData(open: 13, high: 14, low: 11, close: 12, volume: 170),
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 160),
        BarData(open: 11, high: 12, low: 9,  close: 10, volume: 140),
    ]

    private func run(_ source: String) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: testBars)
    }

    // MARK: - NOT

    @Test("NOT: CLOSE>12 取反 · 0/1 翻转")
    func testNOT_basic() throws {
        // CLOSE: 11,12,13,14,15,14,13,12,11,10
        // CLOSE>12: 0,0,1,1,1,1,1,0,0,0（12 > 12 = false）
        // NOT:     1,1,0,0,0,0,0,1,1,1
        let v = try run("R:NOT(CLOSE>12);")[0].values
        #expect(v[0] == 1)
        #expect(v[1] == 1)
        #expect(v[2] == 0)
        #expect(v[6] == 0)
        #expect(v[7] == 1)
        #expect(v[9] == 1)
    }

    @Test("NOT: 双重否定 NOT(NOT(X)) 等于 X 的 0/1 化")
    func testNOT_doubleNegation() throws {
        let v = try run("R:NOT(NOT(CLOSE>12));")[0].values
        #expect(v[0] == 0)
        #expect(v[4] == 1)
        #expect(v[7] == 0)
    }

    // MARK: - CROSSDOWN

    @Test("CROSSDOWN: CLOSE 在 i=6 由 14→13 下穿 13.5")
    func testCROSSDOWN_basic() throws {
        let v = try run("R:CROSSDOWN(CLOSE,13.5);")[0].values
        #expect(v[6] == 1)
        #expect(v[5] == 0)
        #expect(v[7] == 0)
        #expect(v[3] == 0)  // 上穿不算
    }

    @Test("CROSSDOWN 与 CROSS 对偶 · 同阈值上下穿互斥")
    func testCROSSDOWN_dualToCross() throws {
        let up = try run("R:CROSS(CLOSE,13.5);")[0].values
        let dn = try run("R:CROSSDOWN(CLOSE,13.5);")[0].values
        // 上穿在 i=3（CLOSE 13→14 跨 13.5）
        #expect(up[3] == 1 && dn[3] == 0)
        // 下穿在 i=6（CLOSE 14→13 跨 13.5）
        #expect(up[6] == 0 && dn[6] == 1)
    }

    // MARK: - MOD

    @Test("MOD: CLOSE MOD 5")
    func testMOD_basic() throws {
        // CLOSE: 11,12,13,14,15,14,13,12,11,10
        // MOD 5: 1, 2, 3, 4, 0, 4, 3, 2, 1, 0
        let v = try run("R:MOD(CLOSE,5);")[0].values
        #expect(v[0] == 1)
        #expect(v[3] == 4)
        #expect(v[4] == 0)
        #expect(v[5] == 4)
        #expect(v[9] == 0)
    }

    @Test("MOD: 除数为 0 → 全 nil（不抛 · 安全降级）")
    func testMOD_divisionByZero() throws {
        let v = try run("R:MOD(CLOSE,0);")[0].values
        for value in v {
            #expect(value == nil)
        }
    }

    // MARK: - PEAKBARS

    @Test("PEAKBARS: CLOSE 单峰在 i=4 · 距离从 i=5 起递增")
    func testPEAKBARS_singlePeak() throws {
        let v = try run("R:PEAKBARS(CLOSE);")[0].values
        #expect(v[0] == nil)
        #expect(v[3] == nil)
        #expect(v[4] == nil)  // 当前 bar 无右邻不能成为新波峰
        #expect(v[5] == 1)    // 检测到 i=4 是峰，距离 5-4=1
        #expect(v[6] == 2)
        #expect(v[9] == 5)
    }

    // MARK: - TROUGHBARS

    @Test("TROUGHBARS: CLOSE 单峰序列无波谷 → 全 nil")
    func testTROUGHBARS_noTrough() throws {
        let v = try run("R:TROUGHBARS(CLOSE);")[0].values
        for value in v {
            #expect(value == nil)
        }
    }

    @Test("TROUGHBARS 与 PEAKBARS 对偶 · 用 100-CLOSE 翻转")
    func testTROUGHBARS_dualToPeakbars() throws {
        // 100-CLOSE: 89,88,87,86,85,86,87,88,89,90 → 波谷在 i=4（85）
        let v = try run("R:TROUGHBARS(100-CLOSE);")[0].values
        #expect(v[4] == nil)
        #expect(v[5] == 1)
        #expect(v[6] == 2)
        #expect(v[9] == 5)
    }

    // MARK: - 注册表

    @Test("5 个新函数全部注册到 BuiltinFunctions.all")
    func testAllRegistered() {
        let keys = Set(BuiltinFunctions.all.keys)
        #expect(keys.contains("NOT"))
        #expect(keys.contains("CROSSDOWN"))
        #expect(keys.contains("MOD"))
        #expect(keys.contains("PEAKBARS"))
        #expect(keys.contains("TROUGHBARS"))
    }
}
