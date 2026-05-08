// 麦语言扩展函数测试（第 37 批 · 高级均值 + 价格指数化）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 37 批 · 高级均值 + 指数化）")
struct MaiYuYanExtensionBatch37Tests {

    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 12, low: 10, close: 12, volume: 100),
        BarData(open: 12, high: 16, low: 12, close: 16, volume: 100),
        BarData(open: 16, high: 20, low: 16, close: 20, volume: 100),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - HARMONICMEAN

    @Test("HARMONICMEAN <= MA（恒等式：调和均值 <= 算术均值）")
    func testHARMONICMEAN_lessThanMA() throws {
        let h = try run("R:HARMONICMEAN(CLOSE, 3);", bars: testBars)[0].values
        let m = try run("R:MA(CLOSE, 3);", bars: testBars)[0].values
        for i in 2..<testBars.count {
            guard let hv = h[i], let mv = m[i] else { continue }
            #expect(hv <= mv)
        }
    }

    // MARK: - GEOMEAN

    @Test("GEOMEAN <= MA（恒等式）")
    func testGEOMEAN_lessThanMA() throws {
        let g = try run("R:GEOMEAN(CLOSE, 3);", bars: testBars)[0].values
        let m = try run("R:MA(CLOSE, 3);", bars: testBars)[0].values
        for i in 2..<testBars.count {
            guard let gv = g[i], let mv = m[i] else { continue }
            #expect(gv <= mv)
        }
    }

    // MARK: - POWMEAN

    @Test("POWMEAN(X, N, 1) ≈ MA(X, N)")
    func testPOWMEAN_p1EqualsMA() throws {
        let p = try run("R:POWMEAN(CLOSE, 3, 1);", bars: testBars)[0].values
        let m = try run("R:MA(CLOSE, 3);", bars: testBars)[0].values
        for i in 2..<testBars.count {
            guard let pv = p[i], let mv = m[i] else { continue }
            let diff = abs(pv - mv)
            #expect(diff < Decimal(0.01))
        }
    }

    @Test("POWMEAN(X, N, 0) ≈ GEOMEAN(X, N)")
    func testPOWMEAN_p0EqualsGEOMEAN() throws {
        let p = try run("R:POWMEAN(CLOSE, 3, 0);", bars: testBars)[0].values
        let g = try run("R:GEOMEAN(CLOSE, 3);", bars: testBars)[0].values
        for i in 2..<testBars.count {
            guard let pv = p[i], let gv = g[i] else { continue }
            let diff = abs(pv - gv)
            #expect(diff < Decimal(0.01))
        }
    }

    // MARK: - RMS

    @Test("RMS >= MA（恒等式 · 平方平均 >= 算术平均）")
    func testRMS_greaterThanMA() throws {
        let r = try run("R:RMS(CLOSE, 3);", bars: testBars)[0].values
        let m = try run("R:MA(CLOSE, 3);", bars: testBars)[0].values
        for i in 2..<testBars.count {
            guard let rv = r[i], let mv = m[i] else { continue }
            #expect(rv >= mv)
        }
    }

    // MARK: - RANGEMID

    @Test("RANGEMID(N) = ICHITENKAN(N)")
    func testRANGEMID_equalsICHITENKAN() throws {
        let r = try run("R:RANGEMID(3);", bars: testBars)[0].values
        let i = try run("R:ICHITENKAN(3);", bars: testBars)[0].values
        for k in 0..<testBars.count {
            #expect(r[k] == i[k])
        }
    }

    // MARK: - PRICESCORE

    @Test("PRICESCORE(C, 10, 20): 10 → 0 / 15 → 0.5 / 20 → 1")
    func testPRICESCORE() throws {
        let v = try run("R:PRICESCORE(CLOSE, 10, 20);", bars: testBars)[0].values
        // close: 10, 12, 16, 20
        #expect(v[0] == 0)
        #expect(v[1] == Decimal(string: "0.2")!)
        #expect(v[2] == Decimal(string: "0.6")!)
        #expect(v[3] == 1)
    }

    // MARK: - INDEXED

    @Test("INDEXED(C, 0) = 100（自身基期）")
    func testINDEXED_selfIs100() throws {
        let v = try run("R:INDEXED(CLOSE, 0);", bars: testBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val == 100)
        }
    }

    @Test("INDEXED(C, 1): 12/10*100 = 120 等")
    func testINDEXED_n1() throws {
        let v = try run("R:INDEXED(CLOSE, 1);", bars: testBars)[0].values
        // close[1]/close[0]*100 = 12/10*100 = 120
        #expect(v[1] == 120)
        // close[3]/close[2]*100 = 20/16*100 = 125
        #expect(v[3] == 125)
    }
}
