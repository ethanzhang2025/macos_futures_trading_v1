// 麦语言扩展函数测试（第 22 批 · K 线形态扩展）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 22 批 · K 线形态扩展）")
struct MaiYuYanExtensionBatch22Tests {

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - ISMORNINGSTAR

    @Test("ISMORNINGSTAR: 阴 + 小实体跳低 + 阳收过中点")
    func testMORNINGSTAR() throws {
        let bars = [
            BarData(open: 14, high: 14, low: 10, close: 10, volume: 100), // 阴线（实体 4）
            BarData(open: 9.5, high: 9.7, low: 9.3, close: 9.6, volume: 100), // 小实体（0.1 < 4/3）
            BarData(open: 9.8, high: 13, low: 9.5, close: 12.5, volume: 100), // 阳 + 收过中点(12)
        ]
        let v = try run("R:ISMORNINGSTAR();", bars: bars)[0].values
        #expect(v[2] == 1)
    }

    // MARK: - ISEVENINGSTAR

    @Test("ISEVENINGSTAR: 阳 + 小实体跳高 + 阴收过中点")
    func testEVENINGSTAR() throws {
        let bars = [
            BarData(open: 10, high: 14, low: 10, close: 14, volume: 100), // 阳线（实体 4）
            BarData(open: 14.5, high: 14.7, low: 14.3, close: 14.4, volume: 100), // 小实体
            BarData(open: 14.2, high: 14.5, low: 11, close: 11.5, volume: 100), // 阴 + 收过中点(12)
        ]
        let v = try run("R:ISEVENINGSTAR();", bars: bars)[0].values
        #expect(v[2] == 1)
    }

    // MARK: - ISHARAMI

    @Test("ISHARAMI: 大实体 + 小实体内嵌")
    func testHARAMI() throws {
        let bars = [
            BarData(open: 10, high: 15, low: 10, close: 15, volume: 100), // 大实体 5
            BarData(open: 13, high: 14, low: 12, close: 13.5, volume: 100), // 小实体 0.5 · 在 [10, 15] 内
        ]
        let v = try run("R:ISHARAMI();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISDARKCLOUD

    @Test("ISDARKCLOUD: 阳 + 跳高开阴 + 收过中点")
    func testDARKCLOUD() throws {
        let bars = [
            BarData(open: 10, high: 15, low: 10, close: 14, volume: 100), // 阳：[10, 14] 中点 12
            BarData(open: 16, high: 16, low: 11, close: 11.5, volume: 100), // 阴：open=16>15 / close=11.5 < 12 中点 / > 10 open
        ]
        let v = try run("R:ISDARKCLOUD();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISPIERCING

    @Test("ISPIERCING: 阴 + 跳低开阳 + 收过中点")
    func testPIERCING() throws {
        let bars = [
            BarData(open: 14, high: 14, low: 10, close: 10, volume: 100), // 阴：[14, 10] 中点 12
            BarData(open: 9, high: 13.5, low: 9, close: 13, volume: 100), // 阳：open=9<10 / close=13 > 12 中点 / < 14 open
        ]
        let v = try run("R:ISPIERCING();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISGAPDOWN

    @Test("ISGAPDOWN: high < prev low")
    func testISGAPDOWN() throws {
        let bars = [
            BarData(open: 14, high: 15, low: 13, close: 14, volume: 100),
            BarData(open: 12, high: 12.5, low: 11, close: 12, volume: 100), // H=12.5 < L=13
        ]
        let v = try run("R:ISGAPDOWN();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISSHAVENTOP

    @Test("ISSHAVENTOP: 无上影")
    func testSHAVENTOP() throws {
        let bars = [
            BarData(open: 10, high: 14, low: 9, close: 14, volume: 100),  // 光头：H = C = 14
            BarData(open: 10, high: 14, low: 9, close: 12, volume: 100),  // 有上影：H=14 > C=12
        ]
        let v = try run("R:ISSHAVENTOP();", bars: bars)[0].values
        #expect(v[0] == 1)
        #expect(v[1] == 0)
    }
}
