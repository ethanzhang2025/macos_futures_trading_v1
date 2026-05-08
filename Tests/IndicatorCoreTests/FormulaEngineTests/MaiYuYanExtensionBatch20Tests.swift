// 麦语言扩展函数测试（第 20 批 · CLAMPMIN/MAX · SAFEDIV/NAFILL · CUMSUM/PROD · MAXIDX）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 20 批 · 实用辅助）")
struct MaiYuYanExtensionBatch20Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100),
        BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
        BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        BarData(open: 13, high: 15, low: 12, close: 14, volume: 180),
        BarData(open: 14, high: 16, low: 13, close: 15, volume: 220),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - CLAMP

    @Test("CLAMPMIN(CLOSE, 12): 11 → 12 · >= 12 不变")
    func testCLAMPMIN() throws {
        let v = try run("R:CLAMPMIN(CLOSE, 12);", bars: testBars)[0].values
        #expect(v[0] == 12)  // 11 → 12
        #expect(v[1] == 12)  // 12 → 12
        #expect(v[2] == 13)  // 13 不变
        #expect(v[4] == 15)  // 15 不变
    }

    @Test("CLAMPMAX(CLOSE, 13): 14/15 → 13 · <= 13 不变")
    func testCLAMPMAX() throws {
        let v = try run("R:CLAMPMAX(CLOSE, 13);", bars: testBars)[0].values
        #expect(v[0] == 11)  // 不变
        #expect(v[2] == 13)  // 不变
        #expect(v[3] == 13)  // 14 → 13
        #expect(v[4] == 13)  // 15 → 13
    }

    // MARK: - SAFEDIV

    @Test("SAFEDIV(X, Y, default): Y=0 时返 default")
    func testSAFEDIV_zeroFallback() throws {
        let v = try run("R:SAFEDIV(CLOSE, CLOSE-CLOSE, -1);", bars: testBars)[0].values
        // CLOSE-CLOSE = 0 · 全部走 default
        for value in v {
            #expect(value == -1)
        }
    }

    @Test("SAFEDIV(X, Y, default): Y!=0 时返 X/Y")
    func testSAFEDIV_normal() throws {
        let v = try run("R:SAFEDIV(CLOSE, CLOSE, -1);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 1)
        }
    }

    // MARK: - NAFILL

    @Test("NAFILL(REF(CLOSE,2), -99): 前两根 nil → -99")
    func testNAFILL() throws {
        let v = try run("R:NAFILL(REF(CLOSE, 2), -99);", bars: testBars)[0].values
        #expect(v[0] == -99)
        #expect(v[1] == -99)
        #expect(v[2] == 11)  // REF(CLOSE,2) at i=2 = close[0] = 11
    }

    // MARK: - CUMSUM

    @Test("CUMSUM(CLOSE): 累加 11+12+13+14+15 = 65")
    func testCUMSUM() throws {
        let v = try run("R:CUMSUM(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 11)
        #expect(v[1] == 23)
        #expect(v[2] == 36)
        #expect(v[3] == 50)
        #expect(v[4] == 65)
    }

    // MARK: - CUMPROD

    @Test("CUMPROD: 起始 = 1 · 累乘第一个值")
    func testCUMPROD() throws {
        // 1 * 11 = 11 · * 12 = 132 · ...
        let v = try run("R:CUMPROD(CLOSE);", bars: testBars)[0].values
        #expect(v[0] == 11)  // 1 * 11
        #expect(v[1] == 132) // 11 * 12
    }

    // MARK: - MAXIDX

    @Test("MAXIDX(CLOSE, 5): 最后一根 close=15 是最大 · 偏移 = 0")
    func testMAXIDX() throws {
        let v = try run("R:MAXIDX(CLOSE, 5);", bars: testBars)[0].values
        // i=4 close=15 是窗口最大 · 偏移=0
        #expect(v[4] == 0)
        // i=0 仅一根 · 偏移=0
        #expect(v[0] == 0)
    }

    @Test("MAXIDX: 最大在前 · 偏移 > 0")
    func testMAXIDX_whenMaxIsEarlier() throws {
        let highBars = [
            BarData(open: 10, high: 20, low: 9, close: 19, volume: 100),
            BarData(open: 19, high: 18, low: 17, close: 18, volume: 100),
            BarData(open: 18, high: 17, low: 16, close: 17, volume: 100),
        ]
        // close: 19, 18, 17 · 最大在 i=0 · i=2 时偏移 = 2
        let v = try run("R:MAXIDX(CLOSE, 5);", bars: highBars)[0].values
        #expect(v[2] == 2)
    }
}
