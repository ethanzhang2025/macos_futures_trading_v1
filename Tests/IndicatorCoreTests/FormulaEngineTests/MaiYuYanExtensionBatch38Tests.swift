// 麦语言扩展函数测试（第 38 批 · 计数统计）

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 38 批 · 计数统计）")
struct MaiYuYanExtensionBatch38Tests {

    // close: 10/12/8/12/8/10
    private let testBars: [BarData] = [
        BarData(open: 10, high: 11, low: 9,  close: 10, volume: 100),
        BarData(open: 10, high: 12, low: 10, close: 12, volume: 100),
        BarData(open: 12, high: 12, low: 8,  close: 8,  volume: 100),
        BarData(open: 8,  high: 12, low: 8,  close: 12, volume: 100),
        BarData(open: 12, high: 12, low: 8,  close: 8,  volume: 100),
        BarData(open: 8,  high: 10, low: 8,  close: 10, volume: 100),
    ]

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // MARK: - NCROSSUP / NCROSSDN

    @Test("NCROSSUP(C, 10, 6): 序列中上穿 10 几次")
    func testNCROSSUP() throws {
        // close: 10/12/8/12/8/10
        // 上穿 10：i=1 (10→12 >= 10? prev=10 not <10) 不算
        // 实际上穿条件: prev < lvl AND curr >= lvl
        // i=1: 10<10? false → 0
        // i=2: 12<10? false → 0
        // i=3: 8<10 && 12>=10 → 1
        // i=4: 12<10? false → 0
        // i=5: 8<10 && 10>=10 → 1
        // 总 2
        let v = try run("R:NCROSSUP(CLOSE, 10, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("NCROSSUP 末根应有值"); return
        }
        #expect(val == 2)
    }

    @Test("NCROSSDN(C, 10, 6): 序列中下穿 10 几次")
    func testNCROSSDN() throws {
        // 下穿条件: prev > lvl AND curr <= lvl
        // i=2: 12>10 && 8<=10 → 1
        // i=4: 12>10 && 8<=10 → 1
        // 总 2
        let v = try run("R:NCROSSDN(CLOSE, 10, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("NCROSSDN 末根应有值"); return
        }
        #expect(val == 2)
    }

    // MARK: - POSCOUNT / NEGCOUNT / ZEROCOUNT

    @Test("POSCOUNT(C - 10, N): close > 10 的根数")
    func testPOSCOUNT() throws {
        // close - 10: 0/2/-2/2/-2/0
        // > 0 的：i=1, i=3 → 2
        let v = try run("R:POSCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("POSCOUNT 末根应有值"); return
        }
        #expect(val == 2)
    }

    @Test("NEGCOUNT(C - 10, N): close < 10 的根数")
    func testNEGCOUNT() throws {
        // < 0 的：i=2, i=4 → 2
        let v = try run("R:NEGCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("NEGCOUNT 末根应有值"); return
        }
        #expect(val == 2)
    }

    @Test("ZEROCOUNT(C - 10, N): close = 10 的根数")
    func testZEROCOUNT() throws {
        // = 0 的：i=0, i=5 → 2
        let v = try run("R:ZEROCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("ZEROCOUNT 末根应有值"); return
        }
        #expect(val == 2)
    }

    @Test("POSCOUNT + NEGCOUNT + ZEROCOUNT = N（无 nil 时）")
    func testCOUNTS_sumIsN() throws {
        let p = try run("R:POSCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        let n = try run("R:NEGCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        let z = try run("R:ZEROCOUNT(CLOSE - 10, 6);", bars: testBars)[0].values
        for i in 0..<testBars.count {
            guard let pv = p[i], let nv = n[i], let zv = z[i] else { continue }
            // i+1 = 当前根数（窗口起始 0）
            let expected = Decimal(min(i + 1, 6))
            #expect(pv + nv + zv == expected)
        }
    }

    // MARK: - CHANGECOUNT / SAMECOUNT

    @Test("CHANGECOUNT(C, 6): 6 根中变化的次数")
    func testCHANGECOUNT() throws {
        // close: 10/12/8/12/8/10
        // 每根与前根比较：
        // i=1: 12!=10 → 1
        // i=2: 8!=12 → 1
        // i=3: 12!=8 → 1
        // i=4: 8!=12 → 1
        // i=5: 10!=8 → 1
        // 总 5
        let v = try run("R:CHANGECOUNT(CLOSE, 6);", bars: testBars)[0].values
        guard let val = v.last ?? nil else {
            Issue.record("CHANGECOUNT 末根应有值"); return
        }
        #expect(val == 5)
    }

    @Test("SAMECOUNT + CHANGECOUNT = N - 1（i >= 1 时）")
    func testSAMECOUNT_CHANGECOUNT_relationship() throws {
        let s = try run("R:SAMECOUNT(CLOSE, 6);", bars: testBars)[0].values
        let c = try run("R:CHANGECOUNT(CLOSE, 6);", bars: testBars)[0].values
        // i=5 时 6 根 · 5 次比较（i=1..5）· s + c = 5
        guard let sv = s[5], let cv = c[5] else {
            Issue.record("末根应有值"); return
        }
        #expect(sv + cv == 5)
    }
}
