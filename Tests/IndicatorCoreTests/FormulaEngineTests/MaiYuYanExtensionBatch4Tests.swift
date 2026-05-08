// 麦语言扩展函数测试（第 4 批 · PDI / MDI / ADX / TRIX / CORREL）
// 端到端通过 Lexer + Parser + Interpreter 跑公式

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 4 批 · 兼容度 ~99% → ~99.5%）")
struct MaiYuYanExtensionBatch4Tests {

    // 趋势序列：上涨 5 根 + 横盘 3 根 + 下跌 5 根 + 横盘 3 根 = 16 根
    // ADX 在趋势期高 · 横盘期低
    private let trendBars: [BarData] = [
        // 上涨 5 根（每根高低均上推）
        BarData(open: 10.0, high: 11.0, low: 9.5,  close: 10.8, volume: 100),
        BarData(open: 10.8, high: 12.2, low: 10.5, close: 12.0, volume: 110),
        BarData(open: 12.0, high: 13.5, low: 11.8, close: 13.2, volume: 120),
        BarData(open: 13.2, high: 14.8, low: 13.0, close: 14.5, volume: 130),
        BarData(open: 14.5, high: 16.0, low: 14.3, close: 15.8, volume: 140),
        // 横盘 3 根（窄幅）
        BarData(open: 15.8, high: 16.2, low: 15.5, close: 15.9, volume: 90),
        BarData(open: 15.9, high: 16.1, low: 15.6, close: 15.8, volume: 85),
        BarData(open: 15.8, high: 16.0, low: 15.5, close: 15.7, volume: 80),
        // 下跌 5 根
        BarData(open: 15.7, high: 15.7, low: 14.0, close: 14.2, volume: 150),
        BarData(open: 14.2, high: 14.5, low: 12.8, close: 13.0, volume: 160),
        BarData(open: 13.0, high: 13.2, low: 11.5, close: 11.8, volume: 170),
        BarData(open: 11.8, high: 12.0, low: 10.3, close: 10.5, volume: 180),
        BarData(open: 10.5, high: 10.8, low: 9.0,  close: 9.2,  volume: 190),
        // 横盘 3 根
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

    // MARK: - PDI

    @Test("PDI(7): 上涨段 PDI 应高于下跌段")
    func testPDI_higherInUptrend() throws {
        let v = try run("R:PDI(7);", bars: trendBars)[0].values
        // 上涨末段（i=4）PDI 应明显 > 下跌末段（i=12）
        guard let pdiUp = v[4], let pdiDown = v[12] else {
            Issue.record("PDI 在 i=4 / i=12 应有值")
            return
        }
        #expect(pdiUp > pdiDown, "上涨段 PDI=\(pdiUp) 应 > 下跌段 PDI=\(pdiDown)")
    }

    @Test("PDI(7): 全程值在 [0, 100] 范围内")
    func testPDI_inValidRange() throws {
        let v = try run("R:PDI(7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "PDI 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - MDI

    @Test("MDI(7): 下跌段 MDI 应高于上涨段")
    func testMDI_higherInDowntrend() throws {
        let v = try run("R:MDI(7);", bars: trendBars)[0].values
        guard let mdiUp = v[4], let mdiDown = v[12] else {
            Issue.record("MDI 在 i=4 / i=12 应有值")
            return
        }
        #expect(mdiDown > mdiUp, "下跌段 MDI=\(mdiDown) 应 > 上涨段 MDI=\(mdiUp)")
    }

    @Test("MDI(7): 全程值在 [0, 100] 范围内")
    func testMDI_inValidRange() throws {
        let v = try run("R:MDI(7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "MDI 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - ADX

    @Test("ADX(7): 趋势段 ADX 应高于横盘段")
    func testADX_higherInTrend() throws {
        let v = try run("R:ADX(7);", bars: trendBars)[0].values
        // 上涨末段（i=4）vs 上涨后横盘（i=7）· 趋势刚结束 ADX 还高 · 横盘后期会下来
        // 用 i=12（下跌末段）vs i=15（最后横盘）
        guard let adxTrend = v[12], let adxFlat = v[15] else {
            Issue.record("ADX 在 i=12 / i=15 应有值")
            return
        }
        #expect(adxTrend > adxFlat, "下跌段 ADX=\(adxTrend) 应 > 横盘段 ADX=\(adxFlat)")
    }

    @Test("ADX(7): 全程值在 [0, 100] 范围内")
    func testADX_inValidRange() throws {
        let v = try run("R:ADX(7);", bars: trendBars)[0].values
        for value in v {
            guard let val = value else { continue }
            #expect(val >= 0 && val <= 100, "ADX 应在 [0, 100] · 实际 \(val)")
        }
    }

    // MARK: - TRIX

    @Test("TRIX(5): 上涨段 TRIX > 0 · 下跌段 TRIX < 0")
    func testTRIX_signMatchesTrend() throws {
        let v = try run("R:TRIX(5);", bars: trendBars)[0].values
        // 上涨末段
        guard let trixUp = v[4] else {
            Issue.record("TRIX 在 i=4 应有值")
            return
        }
        // 下跌末段
        guard let trixDown = v[12] else {
            Issue.record("TRIX 在 i=12 应有值")
            return
        }
        #expect(trixUp > 0, "上涨末段 TRIX=\(trixUp) 应 > 0")
        #expect(trixDown < 0, "下跌末段 TRIX=\(trixDown) 应 < 0")
    }

    @Test("TRIX(N): 第一根 nil（无前一根可比）")
    func testTRIX_firstBarNil() throws {
        let v = try run("R:TRIX(5);", bars: trendBars)[0].values
        #expect(v[0] == nil)
    }

    // MARK: - CORREL

    @Test("CORREL(X, X, N): 自身相关 = 1")
    func testCORREL_selfIsOne() throws {
        let v = try run("R:CORREL(CLOSE, CLOSE, 5);", bars: trendBars)[0].values
        // 至少需要 2 个有效值 · 从 i=1 起
        for i in 1..<trendBars.count {
            guard let val = v[i] else { continue }
            let diff = abs(val - 1)
            #expect(diff < Decimal(0.001), "CORREL(X,X) 应 = 1 · 实际 \(val) at i=\(i)")
        }
    }

    @Test("CORREL(CLOSE, -CLOSE, N): 完全反相关 = -1")
    func testCORREL_negativeIsMinusOne() throws {
        // -CLOSE 用 0-CLOSE 表达
        let v = try run("R:CORREL(CLOSE, 0-CLOSE, 5);", bars: trendBars)[0].values
        for i in 1..<trendBars.count {
            guard let val = v[i] else { continue }
            let diff = abs(val - (-1))
            #expect(diff < Decimal(0.001), "CORREL(X,-X) 应 = -1 · 实际 \(val) at i=\(i)")
        }
    }

    @Test("CORREL: 全程值在 [-1, 1] 范围内（含浮点容差 ±1e-6）")
    func testCORREL_inValidRange() throws {
        // 对比 CLOSE 与 REF(CLOSE,2)
        // Decimal → Double sqrt → Decimal 转换有 ~1e-15 精度损失 · 用 1e-6 容差包容
        let v = try run("R:CORREL(CLOSE, REF(CLOSE,2), 5);", bars: trendBars)[0].values
        let tolerance = Decimal(0.000001)
        for value in v {
            guard let val = value else { continue }
            #expect(val >= -1 - tolerance && val <= 1 + tolerance, "CORREL 应 ≈ [-1, 1] · 实际 \(val)")
        }
    }
}
