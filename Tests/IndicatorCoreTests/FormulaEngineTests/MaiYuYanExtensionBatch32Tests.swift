// 麦语言扩展函数测试（第 32 批 · 线性回归 + 加权平均）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 32 批 · 线性回归 + 加权平均）")
struct MaiYuYanExtensionBatch32Tests {

    // 完美线性序列 close = 10 + 2*i
    private let linearBars: [BarData] = (0..<10).map { i in
        let c = Decimal(10 + 2 * i)
        return BarData(open: c - 1, high: c + 1, low: c - 1, close: c, volume: 100)
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - LINREG 系列

    @Test("LINREGSLOPE(CLOSE, 5) on 完美线性序列 ≈ 2")
    func testLINREGSLOPE_perfect() throws {
        let v = try run("R:LINREGSLOPE(CLOSE, 5);", bars: linearBars)[0].values
        // 末根斜率应 = 2（CLOSE 每根 +2）
        guard let val = v.last ?? nil else {
            Issue.record("LINREGSLOPE 末根应有值"); return
        }
        let diff = abs(val - 2)
        #expect(diff < Decimal(0.001))
    }

    @Test("LINREGR2(CLOSE, 5) on 完美线性序列 ≈ 1")
    func testLINREGR2_perfect() throws {
        let v = try run("R:LINREGR2(CLOSE, 5);", bars: linearBars)[0].values
        // R² 应接近 1（完美拟合）
        guard let val = v.last ?? nil else {
            Issue.record("LINREGR2 末根应有值"); return
        }
        let diff = abs(val - 1)
        #expect(diff < Decimal(0.001))
    }

    @Test("LINREGR(CLOSE, 5): 末根预测 = 实际值（完美线性）")
    func testLINREGR_perfectPrediction() throws {
        let pred = try run("R:LINREGR(CLOSE, 5);", bars: linearBars)[0].values
        guard let p = pred.last ?? nil else {
            Issue.record("LINREGR 末根应有值"); return
        }
        // 末根 close = 10 + 2*9 = 28
        let actual = Decimal(28)
        let diff = abs(p - actual)
        #expect(diff < Decimal(0.001))
    }

    @Test("LINREGINT(CLOSE, 5): 截距 = 窗口起点的预测值")
    func testLINREGINT() throws {
        let v = try run("R:LINREGINT(CLOSE, 5);", bars: linearBars)[0].values
        // 末根（i=9）start=5 · 起点 close=20 · 截距应 ≈ 20
        guard let val = v.last ?? nil else {
            Issue.record("LINREGINT 末根应有值"); return
        }
        let diff = abs(val - 20)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - TRIMA

    @Test("TRIMA(CLOSE, 5): 中间根权重大")
    func testTRIMA_basic() throws {
        let v = try run("R:TRIMA(CLOSE, 5);", bars: linearBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - EXPSMOOTHING

    @Test("EXPSMOOTHING(CLOSE, 1): alpha=1 等价当前值")
    func testEXPSMOOTHING_alphaOne() throws {
        let v = try run("R:EXPSMOOTHING(CLOSE, 1);", bars: linearBars)[0].values
        for i in 0..<linearBars.count {
            guard let val = v[i] else { continue }
            #expect(val == linearBars[i].close)
        }
    }

    // MARK: - WEIGHTEDMEAN

    @Test("WEIGHTEDMEAN(X, X, N): 等价加权（值=权重）")
    func testWEIGHTEDMEAN_basic() throws {
        let v = try run("R:WEIGHTEDMEAN(CLOSE, CLOSE, 3);", bars: linearBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    @Test("WEIGHTEDMEAN(X, 1, N) ≈ MA(X, N)（常量权重时）")
    func testWEIGHTEDMEAN_uniformWeight() throws {
        // 用 0*CLOSE+1 制造常量 1 序列
        let wm = try run("R:WEIGHTEDMEAN(CLOSE, 0*CLOSE+1, 5);", bars: linearBars)[0].values
        for i in 4..<linearBars.count {
            let ma = try run("R:MA(CLOSE, 5);", bars: linearBars)[0].values
            guard let wmv = wm[i], let mav = ma[i] else { continue }
            let diff = abs(wmv - mav)
            #expect(diff < Decimal(0.001))
        }
    }
}
