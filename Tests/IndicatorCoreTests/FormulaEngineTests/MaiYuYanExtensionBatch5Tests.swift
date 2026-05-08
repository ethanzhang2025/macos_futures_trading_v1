// 麦语言扩展函数测试（第 5 批 · CCI / WR / ROC / MOM / OBV / MFI / TEMA）
// 端到端通过 Lexer + Parser + Interpreter 跑公式

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 5 批 · 兼容度 ~99.5% → ~99.8%）")
struct MaiYuYanExtensionBatch5Tests {

    // 趋势序列：上涨 5 + 横盘 3 + 下跌 5 + 横盘 3
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

    // MARK: - CCI

    @Test("CCI(7): 上涨末段 > 0（强势）· 下跌末段 < 0（弱势）")
    func testCCI_signMatchesTrend() throws {
        let v = try run("R:CCI(7);", bars: trendBars)[0].values
        guard let cciUp = v[4], let cciDown = v[12] else {
            Issue.record("CCI 在 i=4 / i=12 应有值"); return
        }
        #expect(cciUp > 0)
        #expect(cciDown < 0)
    }

    // MARK: - WR

    @Test("WR(5): 取值范围 [0, 100]")
    func testWR_inValidRange() throws {
        let v = try run("R:WR(5);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "WR 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("WR(5): 创新高时 close=hhv 接近 0（超买）")
    func testWR_atHighIsZero() throws {
        // i=4 close=15.8 是 5 根内最高 · WR 接近 0
        let v = try run("R:WR(5);", bars: trendBars)[0].values
        guard let wr4 = v[4] else {
            Issue.record("WR 在 i=4 应有值"); return
        }
        #expect(wr4 < 20, "创新高 WR 应 < 20 · 实际 \(wr4)")
    }

    // MARK: - ROC

    @Test("ROC(3): 上涨段 > 0 · 下跌段 < 0")
    func testROC_signMatchesTrend() throws {
        let v = try run("R:ROC(3);", bars: trendBars)[0].values
        guard let rocUp = v[4], let rocDown = v[12] else {
            Issue.record("ROC 在 i=4 / i=12 应有值"); return
        }
        #expect(rocUp > 0)
        #expect(rocDown < 0)
    }

    @Test("ROC(N): 第一根到 N-1 根都是 nil")
    func testROC_initialNil() throws {
        let v = try run("R:ROC(3);", bars: trendBars)[0].values
        #expect(v[0] == nil)
        #expect(v[1] == nil)
        #expect(v[2] == nil)
        #expect(v[3] != nil)
    }

    // MARK: - MOM

    @Test("MOM(3) = CLOSE - REF(CLOSE,3)")
    func testMOM_equivalentToManual() throws {
        let mom = try run("R:MOM(3);", bars: trendBars)[0].values
        let manual = try run("R:CLOSE - REF(CLOSE, 3);", bars: trendBars)[0].values
        for i in 0..<mom.count {
            #expect(mom[i] == manual[i], "MOM 应等价 CLOSE-REF · 差异 at i=\(i)")
        }
    }

    // MARK: - OBV

    @Test("OBV(): 累计单调性 · close 涨累加 · close 跌减")
    func testOBV_cumulative() throws {
        let v = try run("R:OBV();", bars: trendBars)[0].values
        // i=0 OBV=0
        #expect(v[0] == 0)
        // i=4 上涨末段 OBV 应 > 0（前 4 根全涨）
        guard let obv4 = v[4] else {
            Issue.record("OBV 在 i=4 应有值"); return
        }
        #expect(obv4 > 0)
        // i=12 下跌末段 OBV 应回落
        guard let obv12 = v[12] else {
            Issue.record("OBV 在 i=12 应有值"); return
        }
        #expect(obv12 < obv4, "下跌后 OBV \(obv12) 应 < 上涨末 \(obv4)")
    }

    @Test("OBV: 第一根 = 0")
    func testOBV_firstZero() throws {
        let v = try run("R:OBV();", bars: trendBars)[0].values
        #expect(v[0] == 0)
    }

    // MARK: - MFI

    @Test("MFI(7): 取值范围 [0, 100]")
    func testMFI_inValidRange() throws {
        let v = try run("R:MFI(7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "MFI 应在 [0, 100] · 实际 \(val)")
        }
    }

    @Test("MFI(5): 上涨段高于下跌段")
    func testMFI_higherInUptrend() throws {
        let v = try run("R:MFI(5);", bars: trendBars)[0].values
        guard let mfiUp = v[4], let mfiDown = v[12] else {
            Issue.record("MFI 在 i=4 / i=12 应有值"); return
        }
        #expect(mfiUp > mfiDown)
    }

    // MARK: - TEMA

    @Test("TEMA(CLOSE, 3): 跟随趋势 · 上涨段值递增")
    func testTEMA_tracksTrend() throws {
        let v = try run("R:TEMA(CLOSE, 3);", bars: trendBars)[0].values
        // i=4 上涨末段 TEMA 应大于 i=2
        guard let t2 = v[2], let t4 = v[4] else {
            Issue.record("TEMA 在 i=2 / i=4 应有值"); return
        }
        #expect(t4 > t2)
    }

    @Test("TEMA(CONST, N): 常量序列 TEMA 等于该常量")
    func testTEMA_constantConverges() throws {
        // 常量 5 用 5+0*CLOSE 表达（让其变 series）
        let v = try run("R:TEMA(5+0*CLOSE, 3);", bars: trendBars)[0].values
        // 常量序列经任意 EMA 仍是常量
        guard let last = v.last, let val = last else {
            Issue.record("TEMA 末根应有值"); return
        }
        let diff = abs(val - 5)
        #expect(diff < Decimal(0.001), "TEMA(常量) 应 = 常量 · 实际 \(val)")
    }
}
