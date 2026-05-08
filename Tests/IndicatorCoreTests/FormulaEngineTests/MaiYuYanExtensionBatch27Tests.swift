// 麦语言扩展函数测试（第 27 批 · 数据预处理 + 高级统计）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 27 批 · 数据预处理 + 高级统计）")
struct MaiYuYanExtensionBatch27Tests {

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

    // MARK: - PCTRETURN

    @Test("PCTRETURN(CLOSE, 1): 上涨段 > 0")
    func testPCTRETURN_signMatchesTrend() throws {
        let v = try run("R:PCTRETURN(CLOSE, 1);", bars: trendBars)[0].values
        guard let pUp = v[4], let pDown = v[12] else {
            Issue.record("PCTRETURN 在 i=4 / i=12 应有值"); return
        }
        #expect(pUp > 0)
        #expect(pDown < 0)
    }

    // MARK: - LOGRETURN

    @Test("LOGRETURN(CLOSE): 上涨段 > 0 · 下跌段 < 0")
    func testLOGRETURN_signMatchesTrend() throws {
        let v = try run("R:LOGRETURN(CLOSE);", bars: trendBars)[0].values
        guard let lUp = v[4], let lDown = v[12] else {
            Issue.record("LOGRETURN 在 i=4 / i=12 应有值"); return
        }
        #expect(lUp > 0)
        #expect(lDown < 0)
    }

    // MARK: - DETREND

    @Test("DETREND(CLOSE, 5): 数据围绕 0 摇摆")
    func testDETREND_zeroCenter() throws {
        let v = try run("R:DETREND(CLOSE, 5);", bars: trendBars)[0].values
        var posCount = 0
        var negCount = 0
        for value in v {
            guard let val = value else { continue }
            if val > 0 { posCount += 1 }
            else if val < 0 { negCount += 1 }
        }
        // 长趋势会让正负不完全对称 · 但应都有
        #expect(posCount > 0)
        #expect(negCount > 0)
    }

    // MARK: - KURT / SKEW

    @Test("KURT / SKEW: 数据中至少有非 nil 值")
    func testKURT_SKEW_hasValues() throws {
        let k = try run("R:KURT(CLOSE, 8);", bars: trendBars)[0].values
        let s = try run("R:SKEW(CLOSE, 8);", bars: trendBars)[0].values
        #expect(k.compactMap { $0 }.count > 0)
        #expect(s.compactMap { $0 }.count > 0)
    }

    // MARK: - SHARPE

    @Test("SHARPE(CLOSE, 8): 上涨段 > 0")
    func testSHARPE_inUptrend() throws {
        let v = try run("R:SHARPE(CLOSE, 8);", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("SHARPE 在 i=4 应有值"); return
        }
        // 上涨阶段 mean > 0 · std > 0 · Sharpe > 0
        #expect(val > 0)
    }

    // MARK: - ANNUALSTD

    @Test("ANNUALSTD(CLOSE, 5): 全程 >= 0")
    func testANNUALSTD_nonNegative() throws {
        let v = try run("R:ANNUALSTD(CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    @Test("ANNUALSTD = STD * sqrt(252)")
    func testANNUALSTD_relationship() throws {
        let annual = try run("R:ANNUALSTD(CLOSE, 5);", bars: trendBars)[0].values
        let std = try run("R:STD(CLOSE, 5);", bars: trendBars)[0].values
        let factor = Decimal(sqrt(252.0))
        for i in 0..<trendBars.count {
            guard let a = annual[i], let s = std[i] else { continue }
            let diff = abs(a - s * factor)
            #expect(diff < Decimal(0.001), "ANNUALSTD \(a) ≠ STD*sqrt(252) \(s*factor) at i=\(i)")
        }
    }
}
