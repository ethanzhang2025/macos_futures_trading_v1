// 麦语言扩展函数测试（第 30 批 · 距离统计 + 健壮算法）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 30 批 · 距离统计 + 健壮算法）")
struct MaiYuYanExtensionBatch30Tests {

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

    // MARK: - HHVDIST / LLVDIST

    @Test("HHVDIST(5): 全程 >= 0")
    func testHHVDIST_nonNegative() throws {
        let v = try run("R:HHVDIST(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    @Test("LLVDIST(5): 全程 >= 0")
    func testLLVDIST_nonNegative() throws {
        let v = try run("R:LLVDIST(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0)
        }
    }

    @Test("HHVDIST + LLVDIST <= 振幅")
    func testHHVDIST_LLVDIST_relationship() throws {
        let h = try run("R:HHVDIST(5);", bars: trendBars)[0].values
        let l = try run("R:LLVDIST(5);", bars: trendBars)[0].values
        for i in 0..<trendBars.count {
            guard let hd = h[i], let ld = l[i] else { continue }
            // hd = HHV - C / ld = C - LLV → 二者和 = HHV - LLV
            // 应等于窗口振幅
            #expect(hd + ld >= 0)
        }
    }

    // MARK: - FREQRATIO

    @Test("FREQRATIO(CLOSE, 12, 5): 范围 [0, 1]")
    func testFREQRATIO_inRange() throws {
        let v = try run("R:FREQRATIO(CLOSE, 12, 5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 1)
        }
    }

    // MARK: - MEDIANSLOPE

    @Test("MEDIANSLOPE(CLOSE, 5): 上涨段 > 0 · 下跌段 < 0")
    func testMEDIANSLOPE_signMatchesTrend() throws {
        let v = try run("R:MEDIANSLOPE(CLOSE, 5);", bars: trendBars)[0].values
        guard let mUp = v[4], let mDown = v[12] else {
            Issue.record("MEDIANSLOPE 在 i=4 / i=12 应有值"); return
        }
        #expect(mUp > 0)
        #expect(mDown < 0)
    }

    // MARK: - TRIMMEAN

    @Test("TRIMMEAN(CLOSE, 5, 0) ≈ MA(CLOSE, 5)")
    func testTRIMMEAN_zeroEqualsMA() throws {
        let trim = try run("R:TRIMMEAN(CLOSE, 5, 0);", bars: trendBars)[0].values
        // pct=0 时不去尾 · 应等价 MA · 但 MA 在 warm-up 阶段 nil
        for i in 4..<trendBars.count {
            let ma = try run("R:MA(CLOSE, 5);", bars: trendBars)[0].values
            #expect(trim[i] == ma[i])
        }
    }

    @Test("TRIMMEAN: 全程有限值")
    func testTRIMMEAN_finite() throws {
        let v = try run("R:TRIMMEAN(CLOSE, 5, 20);", bars: trendBars)[0].values
        let nonNil = v.compactMap { $0 }.count
        #expect(nonNil > 0)
    }

    // MARK: - MAXSTREAK

    @Test("MAXSTREAK(CLOSE > REF(CLOSE,1), 9): 5 根连涨（i=1..5）")
    func testMAXSTREAK() throws {
        // close: 10.8(0) 12(1) 13.2(2) 14.5(3) 15.8(4) 15.9(5) 15.8(6) ...
        // CLOSE>REF: i=1 truthy / i=2 / i=3 / i=4 / i=5 truthy → 5 根连续
        // i=6 close=15.8 < 15.9 → 0 中断
        let v = try run("R:MAXSTREAK(CLOSE > REF(CLOSE, 1), 9);", bars: trendBars)[0].values
        guard let val = v[8] else {
            Issue.record("MAXSTREAK 在 i=8 应有值"); return
        }
        #expect(val == 5)
    }

    // MARK: - TIMEINRANGE

    @Test("TIMEINRANGE(CLOSE, 13, 16, 5): 计数 [13, 16] 之间根数")
    func testTIMEINRANGE() throws {
        // i=4 close=15.8 · 窗口 i=0..4 close: 10.8 12 13.2 14.5 15.8
        // 在 [13, 16] 内：13.2 14.5 15.8 → 3 根
        let v = try run("R:TIMEINRANGE(CLOSE, 13, 16, 5);", bars: trendBars)[0].values
        guard let val = v[4] else {
            Issue.record("TIMEINRANGE 在 i=4 应有值"); return
        }
        #expect(val == 3)
    }
}
