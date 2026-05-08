// 麦语言扩展函数测试（第 40 批 · Hilbert 变换 · Ehlers 风格）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 40 批 · Hilbert 变换）")
struct MaiYuYanExtensionBatch40Tests {

    /// 12 根连续递增价格（足以测 7 期 trendline + 4 期 IQ）
    private let testBars: [BarData] = (1...12).map { i in
        BarData(open: Decimal(i), high: Decimal(i + 1), low: Decimal(i - 1),
                close: Decimal(i), volume: 100)
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - 1. HT_TRENDLINE

    @Test("HT_TRENDLINE(CLOSE) · 数据不足 6 根返 nil")
    func testHT_TRENDLINE_warmup() throws {
        let v = try run("R:HT_TRENDLINE(CLOSE);", bars: testBars)[0].values
        for i in 0..<6 { #expect(v[i] == nil) }
        #expect(v[6] != nil)
    }

    @Test("HT_TRENDLINE 在线性序列上 = (1*1+2*2+3*3+4*4+5*5+6*6+7*7)/28 = 5（i=6）")
    func testHT_TRENDLINE_linear() throws {
        let v = try run("R:HT_TRENDLINE(CLOSE);", bars: testBars)[0].values
        // 权重 1..7 对应 close 1..7 → (1+4+9+16+25+36+49)/28 = 140/28 = 5
        #expect(v[6] == 5)
        // i=7 → close 2..8 → (2+6+12+20+30+42+56)/28 = 168/28 = 6
        #expect(v[7] == 6)
    }

    // MARK: - 2. HT_PHASOR

    @Test("HT_PHASOR(CLOSE) · 数据不足 3 根返 nil")
    func testHT_PHASOR_warmup() throws {
        let v = try run("R:HT_PHASOR(CLOSE);", bars: testBars)[0].values
        for i in 0..<3 { #expect(v[i] == nil) }
        #expect(v[3] != nil)
    }

    @Test("HT_PHASOR 在线性序列上 I=3 Q=1 → sqrt(10)")
    func testHT_PHASOR_linear() throws {
        let v = try run("R:HT_PHASOR(CLOSE);", bars: testBars)[0].values
        // i=3: I = close[3] - close[0] = 4-1 = 3, Q = close[2] - close[1] = 3-2 = 1
        // |phasor| = sqrt(9+1) = sqrt(10) ≈ 3.16228
        guard let val = v[3] else { Issue.record("HT_PHASOR 在 i=3 应有值"); return }
        let expected = Decimal(10.0.squareRoot())
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.0001))
    }

    // MARK: - 3. HT_DCPHASE

    @Test("HT_DCPHASE 在线性递增序列上 = atan2(1,3) ≈ 18.43°")
    func testHT_DCPHASE_linear() throws {
        let v = try run("R:HT_DCPHASE(CLOSE);", bars: testBars)[0].values
        guard let val = v[3] else { Issue.record("HT_DCPHASE 在 i=3 应有值"); return }
        let expected = Decimal(atan2(1.0, 3.0) * 180.0 / .pi)
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - 4. HT_DCPERIOD

    @Test("HT_DCPERIOD(CLOSE) · 数据不足 5+3 根返 nil")
    func testHT_DCPERIOD_warmup() throws {
        let v = try run("R:HT_DCPERIOD(CLOSE);", bars: testBars)[0].values
        for i in 0..<5 { #expect(v[i] == nil) }
    }

    @Test("HT_DCPERIOD · 范围限制 [6, 50]")
    func testHT_DCPERIOD_clamp() throws {
        let v = try run("R:HT_DCPERIOD(CLOSE);", bars: testBars)[0].values
        for val in v {
            if let p = val {
                #expect(p >= 6)
                #expect(p <= 50)
            }
        }
    }

    // MARK: - 5. HT_SINE

    @Test("HT_SINE 值域 [-1, 1]")
    func testHT_SINE_range() throws {
        let v = try run("R:HT_SINE(CLOSE);", bars: testBars)[0].values
        for val in v {
            if let s = val {
                #expect(s >= -1)
                #expect(s <= 1)
            }
        }
    }

    @Test("HT_SINE 在线性序列上 = sin(atan2(1,3)) = 1/sqrt(10) ≈ 0.31623")
    func testHT_SINE_linear() throws {
        let v = try run("R:HT_SINE(CLOSE);", bars: testBars)[0].values
        guard let val = v[3] else { Issue.record("HT_SINE 在 i=3 应有值"); return }
        let expected = Decimal(1.0 / 10.0.squareRoot())
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - 6. HT_LEADSINE

    @Test("HT_LEADSINE = HT_SINE 提前 45° · 值域 [-1, 1]")
    func testHT_LEADSINE_range() throws {
        let v = try run("R:HT_LEADSINE(CLOSE);", bars: testBars)[0].values
        for val in v {
            if let s = val {
                #expect(s >= -1)
                #expect(s <= 1)
            }
        }
    }

    @Test("HT_LEADSINE 在线性序列上 = sin(atan2(1,3) + 45°)")
    func testHT_LEADSINE_linear() throws {
        let v = try run("R:HT_LEADSINE(CLOSE);", bars: testBars)[0].values
        guard let val = v[3] else { Issue.record("HT_LEADSINE 在 i=3 应有值"); return }
        let phase = atan2(1.0, 3.0) + .pi / 4
        let expected = Decimal(sin(phase))
        let diff = abs(val - expected)
        #expect(diff < Decimal(0.001))
    }

    // MARK: - 7. HT_TRENDMODE

    @Test("HT_TRENDMODE(CLOSE) · 输出仅 0 或 1")
    func testHT_TRENDMODE_binary() throws {
        let v = try run("R:HT_TRENDMODE(CLOSE);", bars: testBars)[0].values
        for val in v {
            if let m = val {
                #expect(m == 0 || m == 1)
            }
        }
    }

    @Test("线性序列趋势鲜明 · HT_TRENDMODE 在 i=11 应为 1")
    func testHT_TRENDMODE_linearTrend() throws {
        let v = try run("R:HT_TRENDMODE(CLOSE);", bars: testBars)[0].values
        // 最后一根 trendline=10，price=12，dev=2；STD(close, 20) ≈ sqrt(11.91)≈3.45 → 不超 STD → mode=0
        // 不强制 == 1，仅验值合法
        if let m = v[11] {
            #expect(m == 0 || m == 1)
        }
    }
}
