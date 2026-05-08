// 麦语言扩展函数测试（第 43 批 · 现代量化指标）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 43 批 · 现代量化指标）")
struct MaiYuYanExtensionBatch43Tests {

    /// 30 根 sine-like 测试数据（足以覆盖各指标 warm-up）
    private let testBars: [BarData] = (0..<30).map { i in
        let v = 100 + Double(i % 10) * 5  // 锯齿波
        return BarData(open: Decimal(v), high: Decimal(v + 2), low: Decimal(v - 2),
                       close: Decimal(v), volume: 100)
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - 1. WAVETREND

    @Test("WAVETREND(CLOSE, 10, 21) · 末尾应有值（输入足够）")
    func testWAVETREND_hasValue() throws {
        let v = try run("R:WAVETREND(CLOSE, 10, 21);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("WAVETREND · 常量序列 → 0 或 nil（无波动）")
    func testWAVETREND_constant() throws {
        let bars = (0..<30).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        let v = try run("R:WAVETREND(CLOSE, 10, 21);", bars: bars)[0].values
        // 常量序列 d=0 → ci=nil → wt1=nil（前几根可能是首值）
        #expect(v[29] == nil || v[29] == 0)
    }

    // MARK: - 2. SQUEEZEMOM

    @Test("SQUEEZEMOM(CLOSE, 10) · 末尾应有值")
    func testSQUEEZEMOM_hasValue() throws {
        let v = try run("R:SQUEEZEMOM(CLOSE, 10);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("SQUEEZEMOM · 常量序列 → 0（无振幅）")
    func testSQUEEZEMOM_constant() throws {
        let bars = (0..<30).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        let v = try run("R:SQUEEZEMOM(CLOSE, 10);", bars: bars)[0].values
        // 100 - (100+100)/2/2 - 100/2 = 100 - 50 - 50 = 0
        if let val = v[29] { #expect(val == 0) }
    }

    // MARK: - 3. CONNORSRSI

    @Test("CONNORSRSI · 末尾应有值（足够数据）")
    func testCONNORSRSI_hasValue() throws {
        let v = try run("R:CONNORSRSI(CLOSE, 3, 2, 10);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("CONNORSRSI 值域 [0, 100]")
    func testCONNORSRSI_range() throws {
        let v = try run("R:CONNORSRSI(CLOSE, 3, 2, 10);", bars: testBars)[0].values
        for val in v {
            if let r = val {
                #expect(r >= 0)
                #expect(r <= 100)
            }
        }
    }

    // MARK: - 4. SCHAFFTC

    @Test("SCHAFFTC · 末尾应有值")
    func testSCHAFFTC_hasValue() throws {
        let v = try run("R:SCHAFFTC(CLOSE, 12, 26, 10);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("SCHAFFTC 值域 [0, 100]（双 stochastic）")
    func testSCHAFFTC_range() throws {
        let v = try run("R:SCHAFFTC(CLOSE, 5, 10, 5);", bars: testBars)[0].values
        for val in v {
            if let s = val {
                #expect(s >= 0)
                #expect(s <= 100)
            }
        }
    }

    // MARK: - 5. ELDERRAY

    @Test("ELDERRAY(CLOSE, 13) · 上涨段为正（牛市）")
    func testELDERRAY_basic() throws {
        // 单调递增序列
        let bars = (1...20).map { i in
            BarData(open: Decimal(i), high: Decimal(i + 1), low: Decimal(i - 1),
                    close: Decimal(i), volume: 100)
        }
        let v = try run("R:ELDERRAY(CLOSE, 5);", bars: bars)[0].values
        // 单调递增 close > EMA → ELDERRAY > 0
        #expect((v[19] ?? 0) > 0)
    }

    @Test("ELDERRAY · 常量序列 → 0")
    func testELDERRAY_constant() throws {
        let bars = (0..<20).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        let v = try run("R:ELDERRAY(CLOSE, 5);", bars: bars)[0].values
        if let val = v[19] { #expect(val == 0) }
    }

    // MARK: - 6. COPPOCK

    @Test("COPPOCK(CLOSE, 14, 11, 10) · 末尾应有值")
    func testCOPPOCK_hasValue() throws {
        let v = try run("R:COPPOCK(CLOSE, 14, 11, 10);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("COPPOCK · 常量序列 → 0（ROC=0）")
    func testCOPPOCK_constant() throws {
        let bars = (0..<30).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        let v = try run("R:COPPOCK(CLOSE, 14, 11, 10);", bars: bars)[0].values
        if let val = v[29] { #expect(val == 0) }
    }

    // MARK: - 7. KST

    @Test("KST(CLOSE, 5) · 末尾应有值")
    func testKST_hasValue() throws {
        let v = try run("R:KST(CLOSE, 5);", bars: testBars)[0].values
        #expect(v[29] != nil)
    }

    @Test("KST · 常量序列 → 0（所有 ROC=0）")
    func testKST_constant() throws {
        let bars = (0..<30).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        let v = try run("R:KST(CLOSE, 5);", bars: bars)[0].values
        if let val = v[29] { #expect(val == 0) }
    }
}
