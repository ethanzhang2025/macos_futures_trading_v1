// 麦语言扩展函数测试（第 21 批 · K 线形态识别）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 21 批 · K 线形态识别）")
struct MaiYuYanExtensionBatch21Tests {

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - ISDOJI

    @Test("ISDOJI: 十字星（C=O · 实体=0）")
    func testISDOJI_pure() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 8, close: 10, volume: 100),  // 十字
            BarData(open: 10, high: 11, low: 9, close: 11, volume: 100),  // 阳
        ]
        let v = try run("R:ISDOJI(0.1);", bars: bars)[0].values
        #expect(v[0] == 1)
        #expect(v[1] == 0)
    }

    // MARK: - ISHAMMER

    @Test("ISHAMMER: 锤子线（下影 > 2*实体 · 上影小）")
    func testISHAMMER() throws {
        let bars = [
            // 锤子：O=10 C=11（实体 1）H=11.2 L=7（下影 3=3*body / 上影 0.2 < body）
            BarData(open: 10, high: 11.2, low: 7, close: 11, volume: 100),
            // 普通：O=10 C=11 H=12 L=9（下影 1 = body · 不是 > 2*body）
            BarData(open: 10, high: 12, low: 9, close: 11, volume: 100),
        ]
        let v = try run("R:ISHAMMER();", bars: bars)[0].values
        #expect(v[0] == 1)
        #expect(v[1] == 0)
    }

    // MARK: - ISINVHAMMER

    @Test("ISINVHAMMER: 倒锤（上影 > 2*实体 · 下影小）")
    func testISINVHAMMER() throws {
        let bars = [
            // 倒锤：O=10 C=11 H=15 L=9.8（实体 1 / 上影 4 / 下影 0.2）
            BarData(open: 10, high: 15, low: 9.8, close: 11, volume: 100),
        ]
        let v = try run("R:ISINVHAMMER();", bars: bars)[0].values
        #expect(v[0] == 1)
    }

    // MARK: - ISBULLENG

    @Test("ISBULLENG: 看涨吞没（前阴当前阳实体包覆）")
    func testISBULLENG() throws {
        let bars = [
            BarData(open: 12, high: 12, low: 10, close: 10, volume: 100), // 阴线
            BarData(open: 9.5, high: 13, low: 9.5, close: 12.5, volume: 100), // 阳线 + 包覆
        ]
        let v = try run("R:ISBULLENG();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISBEARENG

    @Test("ISBEARENG: 看跌吞没")
    func testISBEARENG() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 10, close: 12, volume: 100), // 阳线
            BarData(open: 12.5, high: 12.5, low: 9, close: 9.5, volume: 100), // 阴线 + 包覆
        ]
        let v = try run("R:ISBEARENG();", bars: bars)[0].values
        #expect(v[1] == 1)
    }

    // MARK: - ISGAPUP

    @Test("ISGAPUP: 向上跳空（low > prev high）")
    func testISGAPUP() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 9, close: 11, volume: 100),  // H=12
            BarData(open: 13, high: 14, low: 12.5, close: 13.5, volume: 100), // L=12.5 > 12
            BarData(open: 13.5, high: 14, low: 13, close: 13.8, volume: 100), // L=13 < 14（无 gap）
        ]
        let v = try run("R:ISGAPUP();", bars: bars)[0].values
        #expect(v[0] == nil)
        #expect(v[1] == 1)
        #expect(v[2] == 0)
    }

    // MARK: - ISLONGBODY

    @Test("ISLONGBODY: 长实体（实体/振幅 > 0.7）")
    func testISLONGBODY() throws {
        let bars = [
            // 长阳：O=10 C=14 H=14.5 L=9.8（body=4 / span=4.7 → 0.85 > 0.7）
            BarData(open: 10, high: 14.5, low: 9.8, close: 14, volume: 100),
            // 普通：O=10 C=11 H=14 L=9（body=1 / span=5 → 0.2）
            BarData(open: 10, high: 14, low: 9, close: 11, volume: 100),
        ]
        let v = try run("R:ISLONGBODY(0.7);", bars: bars)[0].values
        #expect(v[0] == 1)
        #expect(v[1] == 0)
    }
}
