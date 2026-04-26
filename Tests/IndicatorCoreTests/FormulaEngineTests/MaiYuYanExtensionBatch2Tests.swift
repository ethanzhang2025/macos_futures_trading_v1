// 麦语言扩展函数测试（第 2 批 · BACKSET / VARIANCE / RANGE / MEDIAN / LASTPEAK）
// 通过 Lexer + Parser + Interpreter 端到端跑公式

import Foundation
import Testing
@testable import IndicatorCore

@Suite("麦语言扩展函数（第 2 批 · 兼容度 ~90% → ~95%）")
struct MaiYuYanExtensionBatch2Tests {

    // CLOSE 序列：11,12,13,14,15,14,13,12,11,10（单峰：i=4 close=15 是波峰）
    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100),
        BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
        BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        BarData(open: 13, high: 15, low: 12, close: 14, volume: 180),
        BarData(open: 14, high: 16, low: 13, close: 15, volume: 220),
        BarData(open: 15, high: 17, low: 14, close: 14, volume: 190),
        BarData(open: 14, high: 15, low: 12, close: 13, volume: 210),
        BarData(open: 13, high: 14, low: 11, close: 12, volume: 170),
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 160),
        BarData(open: 11, high: 12, low: 9,  close: 10, volume: 140),
    ]

    private func run(_ source: String) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: testBars)
    }

    // MARK: - BACKSET

    @Test("BACKSET: CLOSE>14 仅 i=4 触发 → 回设 3 根（i=2/3/4 设 1）")
    func testBACKSET_basic() throws {
        // CLOSE>14: 仅 i=4 (close=15) 为真 → BACKSET(_, 3) 回设 i=2,3,4
        let v = try run("R:BACKSET(CLOSE>14,3);")[0].values
        #expect(v[0] == 0)
        #expect(v[1] == 0)
        #expect(v[2] == 1)
        #expect(v[3] == 1)
        #expect(v[4] == 1)
        #expect(v[5] == 0)
        #expect(v[9] == 0)
    }

    @Test("BACKSET: N=1 退化为原信号")
    func testBACKSET_n1Identity() throws {
        let signal = try run("R:CLOSE>14;")[0].values
        let backset = try run("R:BACKSET(CLOSE>14,1);")[0].values
        for i in 0..<signal.count {
            // CLOSE>14 输出 nil/0/1 ; BACKSET 输出 0/1
            let s: Decimal = (signal[i] ?? 0) != 0 ? 1 : 0
            #expect(backset[i] == s, "差异 at \(i): signal=\(String(describing: signal[i])) backset=\(String(describing: backset[i]))")
        }
    }

    // MARK: - VARIANCE

    @Test("VARIANCE: 11,12,13 三周期方差 = 2/3 ≈ 0.667")
    func testVARIANCE_basic() throws {
        let v = try run("R:VARIANCE(CLOSE,3);")[0].values
        #expect(v[0] == nil)  // 前 2 根无值
        #expect(v[1] == nil)
        // bar 2: close 11,12,13 mean=12, var = ((1+0+1))/3 = 2/3
        let expected = Decimal(2) / Decimal(3)
        #expect(v[2] != nil)
        if let vv = v[2] {
            // 浮点容差比较
            let diff = vv - expected
            #expect(abs(diff) < Decimal(string: "0.0001")!, "实际 \(vv) 期望 \(expected)")
        }
    }

    @Test("VARIANCE 与 STD 关系：STD² ≈ VARIANCE")
    func testVARIANCE_stdSquaredRelation() throws {
        let varVals = try run("R:VARIANCE(CLOSE,3);")[0].values
        let stdVals = try run("R:STD(CLOSE,3);")[0].values
        // bar 2: STD² 应近似等于 VARIANCE
        if let s = stdVals[2], let vr = varVals[2] {
            let s2 = s * s
            let diff = s2 - vr
            #expect(abs(diff) < Decimal(string: "0.001")!, "STD² 与 VARIANCE 偏差过大：\(s2) vs \(vr)")
        } else {
            Issue.record("STD/VARIANCE bar 2 无值")
        }
    }

    // MARK: - RANGE

    @Test("RANGE: CLOSE 在开区间 (12, 14) · 仅 close=13 命中")
    func testRANGE_openInterval() throws {
        // CLOSE: 11,12,13,14,15,14,13,12,11,10
        // (12, 14) 开区间：12 不在（边界），13 在，14 不在
        let v = try run("R:RANGE(CLOSE,12,14);")[0].values
        #expect(v[0] == 0)  // 11
        #expect(v[1] == 0)  // 12 边界
        #expect(v[2] == 1)  // 13
        #expect(v[3] == 0)  // 14 边界
        #expect(v[4] == 0)  // 15
        #expect(v[6] == 1)  // 13
        #expect(v[7] == 0)  // 12 边界
        #expect(v[9] == 0)  // 10
    }

    // MARK: - MEDIAN

    @Test("MEDIAN: 奇数周期 N=3 取中间值")
    func testMEDIAN_oddPeriod() throws {
        let v = try run("R:MEDIAN(CLOSE,3);")[0].values
        // bar 2: 11,12,13 → 12
        // bar 3: 12,13,14 → 13
        // bar 5: 14,15,14 → 排序 14,14,15 → 中位 14
        #expect(v[2] == 12)
        #expect(v[3] == 13)
        #expect(v[5] == 14)
    }

    @Test("MEDIAN: 偶数周期 N=4 取中间两数平均")
    func testMEDIAN_evenPeriod() throws {
        let v = try run("R:MEDIAN(CLOSE,4);")[0].values
        // bar 3: 11,12,13,14 → (12+13)/2 = 12.5
        #expect(v[3] == Decimal(string: "12.5")!)
        // bar 4: 12,13,14,15 → (13+14)/2 = 13.5
        #expect(v[4] == Decimal(string: "13.5")!)
    }

    // MARK: - LASTPEAK

    @Test("LASTPEAK: CLOSE 单峰在 i=4 (close=15) · 从 i=5 起 lastPeakValue=15")
    func testLASTPEAK_singlePeak() throws {
        let v = try run("R:LASTPEAK(CLOSE);")[0].values
        #expect(v[0] == nil)
        #expect(v[3] == nil)
        #expect(v[4] == nil)  // 当前 bar 不能成为新波峰
        #expect(v[5] == 15)   // 检测到 i=4 是峰，值=15
        #expect(v[6] == 15)
        #expect(v[9] == 15)
    }

    @Test("LASTPEAK 与 PEAKBARS 配套：bar 5 → 距 1 + 值 15")
    func testLASTPEAK_pairsWithPeakbars() throws {
        let bars = try run("R:PEAKBARS(CLOSE);")[0].values
        let val = try run("R:LASTPEAK(CLOSE);")[0].values
        #expect(bars[5] == 1 && val[5] == 15)
        #expect(bars[9] == 5 && val[9] == 15)
    }

    // MARK: - 注册表

    @Test("第 2 批 5 个新函数全部注册到 BuiltinFunctions.all")
    func testBatch2AllRegistered() {
        let keys = Set(BuiltinFunctions.all.keys)
        #expect(keys.contains("BACKSET"))
        #expect(keys.contains("VARIANCE"))
        #expect(keys.contains("RANGE"))
        #expect(keys.contains("MEDIAN"))
        #expect(keys.contains("LASTPEAK"))
    }
}
