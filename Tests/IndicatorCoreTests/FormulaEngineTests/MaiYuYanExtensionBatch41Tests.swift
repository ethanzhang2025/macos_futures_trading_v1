// 麦语言扩展函数测试（第 41 批 · 资金管理）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 41 批 · 资金管理）")
struct MaiYuYanExtensionBatch41Tests {

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

    // MARK: - 1. KELLY

    @Test("KELLY(0.6, 1, 1) = 0.2 · 胜率 60% 盈亏比 1:1")
    func testKELLY_classic() throws {
        let v = try run("R:KELLY(0.6, 1, 1);", bars: testBars)[0].values
        #expect(v[0] == Decimal(string: "0.2"))
    }

    @Test("KELLY(0.5, 2, 1) = 0.25 · 胜率 50% 盈亏比 2:1")
    func testKELLY_high_payoff() throws {
        let v = try run("R:KELLY(0.5, 2, 1);", bars: testBars)[0].values
        // 0.5 - 0.5 * 1/2 = 0.5 - 0.25 = 0.25
        #expect(v[0] == Decimal(string: "0.25"))
    }

    // MARK: - 2. OPTIMALF

    @Test("OPTIMALF · 全负收益 → f=0（无最优值）")
    func testOPTIMALF_all_negative() throws {
        // 构造全 -0.05 returns
        let v = try run("R:OPTIMALF(-0.05, 5);", bars: testBars)[0].values
        // 数据不足前 4 根 nil
        #expect(v[0] == nil)
        if let val = v[4] { #expect(val == 0) }
    }

    @Test("OPTIMALF · 周期数据足时返 [0, 1] 范围 f")
    func testOPTIMALF_range() throws {
        let v = try run("R:OPTIMALF(0.01, 5);", bars: testBars)[0].values
        for val in v {
            if let f = val {
                #expect(f >= 0)
                #expect(f <= 1)
            }
        }
    }

    // MARK: - 3. POSITIONSIZE

    @Test("POSITIONSIZE(100000, 0.02, 100) = 20 · 头寸标准公式")
    func testPOSITIONSIZE_standard() throws {
        let v = try run("R:POSITIONSIZE(100000, 0.02, 100);", bars: testBars)[0].values
        #expect(v[0] == 20)
    }

    @Test("POSITIONSIZE 单位风险 0 → nil（防除零）")
    func testPOSITIONSIZE_zero_risk() throws {
        let v = try run("R:POSITIONSIZE(100000, 0.02, 0);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }

    // MARK: - 4. RISKPCT

    @Test("RISKPCT(100, 95) = 0.05 · 5% 单笔风险")
    func testRISKPCT_basic() throws {
        let v = try run("R:RISKPCT(100, 95);", bars: testBars)[0].values
        #expect(v[0] == Decimal(string: "0.05"))
    }

    @Test("RISKPCT 入场价 0 → nil")
    func testRISKPCT_zero_entry() throws {
        let v = try run("R:RISKPCT(0, 0);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }

    // MARK: - 5. REWARDRATIO

    @Test("REWARDRATIO(110, 100, 95) = 2 · 盈亏比 2:1")
    func testREWARDRATIO_2to1() throws {
        let v = try run("R:REWARDRATIO(110, 100, 95);", bars: testBars)[0].values
        #expect(v[0] == 2)
    }

    @Test("REWARDRATIO 止损=入场 → nil（防除零）")
    func testREWARDRATIO_zero_risk() throws {
        let v = try run("R:REWARDRATIO(110, 100, 100);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }

    // MARK: - 6. EQUITY

    @Test("EQUITY(0.1) · 每根+10% 累积")
    func testEQUITY_10pct() throws {
        let v = try run("R:EQUITY(0.1);", bars: testBars)[0].values
        // i=0 → 1.1 / i=1 → 1.21 / i=2 → 1.331
        #expect(v[0] == Decimal(string: "1.1"))
        #expect(v[1] == Decimal(string: "1.21"))
        let v2 = v[2] ?? 0
        let diff = abs(v2 - Decimal(string: "1.331")!)
        #expect(diff < Decimal(0.0001))
    }

    @Test("EQUITY · 全 0 收益 → 累积始终 1")
    func testEQUITY_zero() throws {
        let v = try run("R:EQUITY(0);", bars: testBars)[0].values
        for val in v { #expect(val == 1) }
    }

    // MARK: - 7. MARTINGALE

    @Test("MARTINGALE(0, 10) = 10 · 无连亏 = base")
    func testMARTINGALE_zero() throws {
        let v = try run("R:MARTINGALE(0, 10);", bars: testBars)[0].values
        #expect(v[0] == 10)
    }

    @Test("MARTINGALE(3, 10) = 80 · 连亏 3 = 8x base")
    func testMARTINGALE_three() throws {
        let v = try run("R:MARTINGALE(3, 10);", bars: testBars)[0].values
        #expect(v[0] == 80)
    }

    @Test("MARTINGALE(31, 10) = nil · 超界保护")
    func testMARTINGALE_overflow_guard() throws {
        let v = try run("R:MARTINGALE(31, 10);", bars: testBars)[0].values
        #expect(v[0] == nil)
    }
}
