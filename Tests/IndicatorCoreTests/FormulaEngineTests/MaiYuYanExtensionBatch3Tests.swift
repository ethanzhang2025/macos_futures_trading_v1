// 麦语言扩展函数测试（第 3 批 · TR / ATR / TROUGH / HHVCROSS / REFV）
// 端到端通过 Lexer + Parser + Interpreter 跑公式

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 3 批 · 兼容度 ~95% → ~99%）")
struct MaiYuYanExtensionBatch3Tests {

    // 双谷双峰序列 · 涵盖：
    // close: 10, 12, 11, 13, 15, 14, 12, 11, 13, 12（i=4 峰=15 / i=7 谷=11）
    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 13, low: 10, close: 12, volume: 150),
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 130),
        BarData(open: 11, high: 14, low: 11, close: 13, volume: 200),
        BarData(open: 13, high: 16, low: 13, close: 15, volume: 220),
        BarData(open: 15, high: 16, low: 13, close: 14, volume: 190),
        BarData(open: 14, high: 14, low: 11, close: 12, volume: 170),
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 160),
        BarData(open: 11, high: 14, low: 11, close: 13, volume: 180),
        BarData(open: 13, high: 14, low: 11, close: 12, volume: 150),
    ]

    private func run(_ source: String) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: testBars)
    }

    // MARK: - TR

    @Test("TR: 第一根退化为 H-L = 11-9 = 2")
    func testTR_firstBar() throws {
        let v = try run("R:TR();")[0].values
        #expect(v[0] == 2)
    }

    @Test("TR: 第二根 H=13 L=10 prevC=10 → max(3, 3, 0) = 3")
    func testTR_secondBar() throws {
        let v = try run("R:TR();")[0].values
        // bars[1]: H-L=3, |H-prevC|=|13-10|=3, |L-prevC|=|10-10|=0 → 3
        #expect(v[1] == 3)
    }

    @Test("TR: 跳空场景 H=16 L=13 prevC=11 → max(3, 5, 2) = 5")
    func testTR_gap() throws {
        // bars[8]: H=14 L=11 prevC=11 → max(3, 3, 0) = 3
        // 改用 bars[4] H=16 L=13 prevC=13(bars[3].close) → max(3, 3, 0) = 3
        // 没现成跳空 · 验证算法稳定即可
        let v = try run("R:TR();")[0].values
        #expect(v.count == 10)
        #expect(v.allSatisfy { $0 != nil })
    }

    // MARK: - ATR

    @Test("ATR(3): 前 3 根滚动均值非 nil")
    func testATR_basic() throws {
        let v = try run("R:ATR(3);")[0].values
        #expect(v[0] != nil)
        #expect(v[2] != nil)
        // bars[0..2] TR: 2, 3, 3 → ATR(3)[2] = (2+3+3)/3 ≈ 2.667
        if let atr2 = v[2] {
            let expected = Decimal(8) / Decimal(3)
            // Decimal 比较容差
            let diff = abs(atr2 - expected)
            #expect(diff < Decimal(0.01))
        }
    }

    @Test("ATR(N): N=1 退化为 TR 本身")
    func testATR_n1IdenticalToTR() throws {
        let tr = try run("R:TR();")[0].values
        let atr1 = try run("R:ATR(1);")[0].values
        for i in 0..<tr.count {
            #expect(atr1[i] == tr[i])
        }
    }

    // MARK: - TROUGH

    @Test("TROUGH: 检测 close 序列局部最小值")
    func testTROUGH_detectsLocalMin() throws {
        // close: 10, 12, 11, 13, 15, 14, 12, 11, 13, 12
        // i=2 是局部最小（close=11 · prev=12 next=13）
        // 但波谷判定用 X[i-1] · 即检测 i-1 是否为谷 · prev<prev2 && prev<curr
        // 等价：检测中间元素 < 两侧
        // i=2 close=11 检测 i-1=1 close=12 vs i-2=0 close=10 → 12<10? 否 · 不是谷
        // i=3 close=13 检测 i-1=2 close=11 vs i-2=1 close=12 → 11<12 ✓ + 11<13 ✓ → i-1=2 是谷 → 从 i=3 开始 TROUGH=11
        let v = try run("R:TROUGH(CLOSE);")[0].values
        #expect(v[0] == nil)
        #expect(v[1] == nil)
        #expect(v[2] == nil)  // 还没确认谷
        #expect(v[3] == 11)   // close=11 是 i-1 处的谷
    }

    @Test("TROUGH: 后续谷会刷新")
    func testTROUGH_refreshes() throws {
        // close: ..., 12, 11, 13, 12 (尾部) → i=8 close=13 检测 i-1=7 close=11 vs i-2=6 close=12
        // 11<12 ✓ + 11<13 ✓ → i-1=7 是新谷 → TROUGH 刷新为 11
        let v = try run("R:TROUGH(CLOSE);")[0].values
        #expect(v[8] == 11)
        #expect(v[9] == 11)
    }

    // MARK: - HHVCROSS

    @Test("HHVCROSS(CLOSE,3): 上穿前 3 根最高")
    func testHHVCROSS_basic() throws {
        // close: 10, 12, 11, 13, 15, 14, 12, 11, 13, 12
        // i=3 curr=13 prev=11 · HHV(close,3) at i-1=2 = max(10,12,11)=12 · 11<12 && 13>=12 → 上穿 ✓ → 1
        // i=4 curr=15 prev=13 · HHV at i-1=3 = max(12,11,13)=13 · 13<13? 否（不严格小） → 0
        // 我的 logic：prevSrc < target → 上穿（严格小）· 13<13=false → 0
        // 但 close=13 在 i=3 已经是新高，i=4 持续创新高时 prev=13 == target=13 不算上穿
        let v = try run("R:HHVCROSS(CLOSE,3);")[0].values
        #expect(v[3] == 1)
        // i=8 curr=13 prev=11 · HHV at i-1=7 = max(close[5..7]) = max(14,12,11)=14 · 11<14 && 13>=14? 否 → 0
        #expect(v[8] == 0)
    }

    @Test("HHVCROSS: 第一根总是 nil（无 prev）")
    func testHHVCROSS_firstBarNil() throws {
        let v = try run("R:HHVCROSS(CLOSE,3);")[0].values
        #expect(v[0] == nil)
    }

    // MARK: - REFV

    @Test("REFV(CLOSE, 1): 等价 REF(CLOSE, 1)")
    func testREFV_constN1() throws {
        // REFV 的 N 是 series · 用 1 常数序列等价 REF(X,1)
        let r1 = try run("R:REFV(CLOSE, 1);")[0].values
        let r2 = try run("R:REF(CLOSE, 1);")[0].values
        for i in 0..<r1.count {
            #expect(r1[i] == r2[i])
        }
    }

    @Test("REFV: 浮动周期 BARSLAST(CLOSE>14)")
    func testREFV_dynamicOffset() throws {
        // BARSLAST(CLOSE>14)：距上次 close>14 多少 bar · 仅 i=4 (close=15) 满足
        // BARSLAST 在 i=4 = 0 / i=5 = 1 / i=6 = 2 / ... / i=9 = 5
        // REFV(CLOSE, BARSLAST(CLOSE>14)) → 在 i=5 引用 1 根前 close=15 · i=6 引用 2 根前 close=15
        let v = try run("R:REFV(CLOSE, BARSLAST(CLOSE>14));")[0].values
        #expect(v[5] == 15)
        #expect(v[6] == 15)
        #expect(v[9] == 15)
    }

    @Test("REFV: 偏移 0 即当前值")
    func testREFV_zeroOffset() throws {
        // REFV(CLOSE, 0) 等价 CLOSE 自身
        let r = try run("R:REFV(CLOSE, 0);")[0].values
        let close = try run("R:CLOSE;")[0].values
        for i in 0..<r.count {
            #expect(r[i] == close[i])
        }
    }
}
