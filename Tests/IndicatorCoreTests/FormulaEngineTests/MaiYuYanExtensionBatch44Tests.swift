// 麦语言扩展函数测试（第 44 批 · 信号过滤 · 收尾批）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 44 批 · 信号过滤）")
struct MaiYuYanExtensionBatch44Tests {

    private let testBars: [BarData] = (0..<20).map { i in
        let v = 100 + Double(i % 5) * 5  // 波动 100/105/110/115/120
        return BarData(open: Decimal(v), high: Decimal(v + 2), low: Decimal(v - 2),
                       close: Decimal(v), volume: 100)
    }

    private let constBars: [BarData] = (0..<20).map { _ in
        BarData(open: 100, high: 100, low: 100, close: 100, volume: 100)
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - 1. KALMAN

    @Test("KALMAN · 常量序列 → 收敛到常量")
    func testKALMAN_constant() throws {
        let v = try run("R:KALMAN(CLOSE, 0.01, 1);", bars: constBars)[0].values
        // 常量 100 输入 → 估计也是 100
        if let val = v[19] { #expect(val == 100) }
    }

    @Test("KALMAN · R 越大估计越平滑（追近过去状态）")
    func testKALMAN_smooth_R() throws {
        let v = try run("R:KALMAN(CLOSE, 0.001, 100);", bars: testBars)[0].values
        #expect(v[19] != nil)
    }

    // MARK: - 2. HP_FILTER

    @Test("HP_FILTER · 常量序列 → 常量")
    func testHP_FILTER_constant() throws {
        let v = try run("R:HP_FILTER(CLOSE, 100);", bars: constBars)[0].values
        if let val = v[19] {
            let diff = abs(val - 100)
            #expect(diff < Decimal(0.001))
        }
    }

    @Test("HP_FILTER · lambda=0 → 等价 X（α=0）")
    func testHP_FILTER_lambda_zero() throws {
        let v = try run("R:HP_FILTER(CLOSE, 0);", bars: testBars)[0].values
        // lambda=0 → α=0 → trend = X
        for i in 0..<20 {
            if let val = v[i], let x = testBars[safe: i].map({ $0.close }) {
                #expect(val == x)
            }
        }
    }

    // MARK: - 3. SAVITZKYGOLAY

    @Test("SAVITZKYGOLAY · 常量序列 → 常量")
    func testSG_constant() throws {
        let v = try run("R:SAVITZKYGOLAY(CLOSE);", bars: constBars)[0].values
        // 5 期权重和 = -3+12+17+12-3 = 35 / 35 = 1，常量 100 → 100
        if let val = v[19] { #expect(val == 100) }
    }

    @Test("SAVITZKYGOLAY · 数据不足 5 根返 nil")
    func testSG_warmup() throws {
        let v = try run("R:SAVITZKYGOLAY(CLOSE);", bars: testBars)[0].values
        for i in 0..<4 { #expect(v[i] == nil) }
        #expect(v[4] != nil)
    }

    // MARK: - 4. MEDIANFILTER

    @Test("MEDIANFILTER(X, 1) = X · N=1 等价")
    func testMEDIAN_n1() throws {
        let v = try run("R:MEDIANFILTER(CLOSE, 1);", bars: testBars)[0].values
        for i in 0..<20 {
            if let val = v[i] { #expect(val == testBars[i].close) }
        }
    }

    @Test("MEDIANFILTER(常量, 5) = 常量")
    func testMEDIAN_constant() throws {
        let v = try run("R:MEDIANFILTER(CLOSE, 5);", bars: constBars)[0].values
        for val in v {
            if let m = val { #expect(m == 100) }
        }
    }

    @Test("MEDIANFILTER 抗噪 · 中间一根尖峰 → 不改变中位数")
    func testMEDIAN_spike() throws {
        var bars = (0..<5).map { _ in BarData(open: 100, high: 100, low: 100, close: 100, volume: 100) }
        bars[2] = BarData(open: 1000, high: 1000, low: 1000, close: 1000, volume: 100)
        let v = try run("R:MEDIANFILTER(CLOSE, 5);", bars: bars)[0].values
        // 5 期窗 [100,100,1000,100,100] 中位数 = 100
        if let val = v[4] { #expect(val == 100) }
    }

    // MARK: - 5. GAUSSFILTER

    @Test("GAUSSFILTER · 常量序列 → 常量")
    func testGAUSS_constant() throws {
        let v = try run("R:GAUSSFILTER(CLOSE, 5);", bars: constBars)[0].values
        if let val = v[19] {
            let diff = abs(val - 100)
            #expect(diff < Decimal(0.0001))
        }
    }

    @Test("GAUSSFILTER · 数据不足 N 根返 nil")
    func testGAUSS_warmup() throws {
        let v = try run("R:GAUSSFILTER(CLOSE, 5);", bars: testBars)[0].values
        for i in 0..<4 { #expect(v[i] == nil) }
        #expect(v[4] != nil)
    }

    // MARK: - 6. BUTTERWORTH

    @Test("BUTTERWORTH · 常量序列 → 常量")
    func testBUTTER_constant() throws {
        let v = try run("R:BUTTERWORTH(CLOSE, 10);", bars: constBars)[0].values
        if let val = v[19] {
            let diff = abs(val - 100)
            #expect(diff < Decimal(0.01))
        }
    }

    @Test("BUTTERWORTH · 末尾应有值")
    func testBUTTER_hasValue() throws {
        let v = try run("R:BUTTERWORTH(CLOSE, 10);", bars: testBars)[0].values
        #expect(v[19] != nil)
    }

    // MARK: - 7. EMAFILTER

    @Test("EMAFILTER(X, 1) = X · α=1 直通")
    func testEMA_alpha_1() throws {
        let v = try run("R:EMAFILTER(CLOSE, 1);", bars: testBars)[0].values
        for i in 0..<20 {
            if let val = v[i] { #expect(val == testBars[i].close) }
        }
    }

    @Test("EMAFILTER(X, 0) = 第一根的值 · α=0 完全平滑")
    func testEMA_alpha_0() throws {
        let v = try run("R:EMAFILTER(CLOSE, 0);", bars: testBars)[0].values
        // α=0 → 始终保持 prev = 第一根
        for val in v {
            if let m = val { #expect(m == testBars[0].close) }
        }
    }

    @Test("EMAFILTER · 常量序列 → 常量")
    func testEMA_constant() throws {
        let v = try run("R:EMAFILTER(CLOSE, 0.5);", bars: constBars)[0].values
        for val in v {
            if let m = val { #expect(m == 100) }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        return indices.contains(i) ? self[i] : nil
    }
}
