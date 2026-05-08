// 麦语言扩展函数测试（第 16 批 · CMF/ADL/BR/AR/KVO/RVI/BETA）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 16 批 · 量价进阶 + 中国市场 + 配对统计）")
struct MaiYuYanExtensionBatch16Tests {

    private let trendBars: [BarData] = [
        BarData(open: 10.0, high: 11.0, low: 9.5,  close: 10.8, volume: 100),
        BarData(open: 10.8, high: 12.2, low: 10.5, close: 12.0, volume: 110),
        BarData(open: 12.0, high: 13.5, low: 11.8, close: 13.2, volume: 120),
        BarData(open: 13.2, high: 14.8, low: 13.0, close: 14.5, volume: 130),
        BarData(open: 14.5, high: 16.0, low: 14.3, close: 15.8, volume: 140),
        BarData(open: 15.8, high: 16.2, low: 15.5, close: 15.9, volume: 90),
        BarData(open: 15.9, high: 16.1, low: 15.6, close: 15.8, volume: 85),
        BarData(open: 15.8, high: 16.0, low: 15.5, close: 15.7, volume: 80),
        BarData(open: 15.7, high: 15.7, low: 14.0, close: 14.2, volume: 150),
        BarData(open: 14.2, high: 14.5, low: 12.8, close: 13.0, volume: 160),
        BarData(open: 13.0, high: 13.2, low: 11.5, close: 11.8, volume: 170),
        BarData(open: 11.8, high: 12.0, low: 10.3, close: 10.5, volume: 180),
        BarData(open: 10.5, high: 10.8, low: 9.0,  close: 9.2,  volume: 190),
        BarData(open: 9.2,  high: 9.5,  low: 9.0,  close: 9.3,  volume: 80),
        BarData(open: 9.3,  high: 9.6,  low: 9.1,  close: 9.4,  volume: 85),
        BarData(open: 9.4,  high: 9.5,  low: 9.0,  close: 9.2,  volume: 75),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - CMF

    @Test("CMF(5): 范围 [-1, 1]")
    func testCMF_inRange() throws {
        let v = try run("R:CMF(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -1 && val <= 1, "CMF 应在 [-1, 1] · 实际 \(val)")
        }
    }

    // MARK: - ADL

    @Test("ADL(): 第一根有值 · 累加")
    func testADL_cumulative() throws {
        let v = try run("R:ADL();", bars: trendBars)[0].values
        #expect(v[0] != nil)
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - BR

    @Test("BR(5): 上涨段 > 下跌段")
    func testBR_uptrendHigher() throws {
        let v = try run("R:BR(5);", bars: trendBars)[0].values
        guard let bUp = v[4], let bDown = v[12] else {
            Issue.record("BR 在 i=4 / i=12 应有值"); return
        }
        #expect(bUp > bDown)
    }

    // MARK: - AR

    @Test("AR(5): 上涨段 > 下跌段")
    func testAR_uptrendHigher() throws {
        let v = try run("R:AR(5);", bars: trendBars)[0].values
        guard let aUp = v[4], let aDown = v[12] else {
            Issue.record("AR 在 i=4 / i=12 应有值"); return
        }
        #expect(aUp > aDown)
    }

    // MARK: - KVO

    @Test("KVO(3, 7): 上涨段 > 下跌段")
    func testKVO_signTracksTrend() throws {
        let v = try run("R:KVO(3, 7);", bars: trendBars)[0].values
        guard let kUp = v[4], let kDown = v[12] else {
            Issue.record("KVO 在 i=4 / i=12 应有值"); return
        }
        #expect(kUp > kDown)
    }

    // MARK: - RVI

    @Test("RVI(5): 全程有限值（非 nil 数 > 0）")
    func testRVI_hasValues() throws {
        let v = try run("R:RVI(5);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - BETA

    @Test("BETA(X, X, N) = 1（自身 Beta）")
    func testBETA_selfIsOne() throws {
        let v = try run("R:BETA(CLOSE, CLOSE, 5);", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            guard let val = v[i] else { continue }
            let diff = abs(val - 1)
            #expect(diff < Decimal(0.001), "BETA(X,X) 应 = 1 · 实际 \(val) at i=\(i)")
        }
    }

    @Test("BETA: 全程有限值")
    func testBETA_finite() throws {
        let v = try run("R:BETA(CLOSE, OPEN, 5);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }
}
