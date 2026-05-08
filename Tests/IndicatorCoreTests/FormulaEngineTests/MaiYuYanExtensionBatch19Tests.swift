// 麦语言扩展函数测试（第 19 批 · MARKETFI/CHOPPINESS/EFI + PERCENTRANK/ZSCORE/NORM/EMD）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 19 批 · Bill Williams + 统计归一化）")
struct MaiYuYanExtensionBatch19Tests {

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

    // MARK: - MARKETFI

    @Test("MARKETFI(): 全程 > 0（仅 V > 0 时有值）")
    func testMARKETFI_positive() throws {
        let v = try run("R:MARKETFI();", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val > 0)
        }
    }

    // MARK: - CHOPPINESS

    @Test("CHOPPINESS(5): 范围 [0, 100]")
    func testCHOPPINESS_inRange() throws {
        let v = try run("R:CHOPPINESS(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "CHOPPINESS 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - EFI

    @Test("EFI(5): 上涨段 > 0 · 下跌段 < 0")
    func testEFI_signMatchesTrend() throws {
        let v = try run("R:EFI(5);", bars: trendBars)[0].values
        guard let efiUp = v[4], let efiDown = v[12] else {
            Issue.record("EFI 在 i=4 / i=12 应有值"); return
        }
        #expect(efiUp > 0)
        #expect(efiDown < 0)
    }

    // MARK: - PERCENTRANK

    @Test("PERCENTRANK(CLOSE, 5): 范围 [0, 100]")
    func testPERCENTRANK_inRange() throws {
        let v = try run("R:PERCENTRANK(CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "PERCENTRANK 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("PERCENTRANK: 创新高时 = 100")
    func testPERCENTRANK_atHighIs100() throws {
        // i=4 close=15.8 是窗口最高 · 所有元素 <= 15.8 → 100%
        let v = try run("R:PERCENTRANK(CLOSE, 5);", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("PERCENTRANK 在 i=4 应有值"); return
        }
        #expect(val == 100)
    }

    // MARK: - ZSCORE

    @Test("ZSCORE(CLOSE, 5): 上涨段 > 0 · 下跌段 < 0")
    func testZSCORE_signMatchesTrend() throws {
        let v = try run("R:ZSCORE(CLOSE, 5);", bars: trendBars)[0].values
        guard let zUp = v[4], let zDown = v[12] else {
            Issue.record("ZSCORE 在 i=4 / i=12 应有值"); return
        }
        #expect(zUp > 0)
        #expect(zDown < 0)
    }

    // MARK: - NORM

    @Test("NORM(CLOSE, 5): 范围 [0, 1]")
    func testNORM_inRange() throws {
        let v = try run("R:NORM(CLOSE, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1, "NORM 应在 [0, 1] · 实际 \(val)")
        }
    }

    // MARK: - EMD

    @Test("EMD(F, S) = EMA(C, F) - EMA(C, S) · 与 MACDDIF 等价")
    func testEMD_equivalent() throws {
        let emd = try run("R:EMD(5, 10);", bars: trendBars)[0].values
        let dif = try run("R:MACDDIF(5, 10);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            #expect(emd[i] == dif[i])
        }
    }
}
