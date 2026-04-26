// 调查 V-S*S 精度异常 → 修复 + regression 守护
//
// 现象（v6.0+ 2026-04-26 MaiYuYanFormulaDemo 公式 6 暴露）：
//   V:VARIANCE(CLOSE,20); S:STD(CLOSE,20); DIFF:V-S*S;
//   DIFF 末值 = -8.0875（异常 · 应 ≈ 0）
//
// 根因：
//   ExecutionContext.getBuiltinSeries 含 case "VOL", "V", "VOLUME"
//   原 evaluateSeries 顺序 builtin 优先 · 用户 V: 被 VOLUME 遮蔽
//   DIFF 中 V 实际取 VOLUME 序列（末值 ≈ 100）· DIFF = VOLUME - STD² = 100 - 33.25 = 66.75
//
// 修复：
//   evaluateSeries 顺序改为 user variables 优先（标准 lexical scoping）
//
// 本文件 = regression 守护：
//   - testUserVariableShadowsBuiltin · V/S/C 等单字符用户变量必须 shadow builtin
//   - testVarianceStdSquaredOnLargeData · DIFF=V-S*S 必须 ≈ 0（修复后）
//   - testMultiStatementVariableLookup · 多 statement 公式 V/S/DIFF 一致性

import Foundation
import Testing
@testable import IndicatorCore

private func runFormula(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
    var lexer = Lexer(source: source)
    let tokens = try lexer.tokenize()
    var parser = Parser(tokens: tokens)
    let formula = try parser.parse()
    return try Interpreter().execute(formula: formula, bars: bars)
}

@Suite("Interpreter · 用户变量优先于 builtin（修复 V-S*S 精度异常）")
struct VarianceStdInvestigationTests {

    @Test("用户变量 V/C/H/L/O/S 必须 shadow 同名 builtin")
    func testUserVariableShadowsBuiltin() throws {
        var bars: [BarData] = []
        for _ in 0..<5 {
            bars.append(BarData(open: 1, high: 2, low: 3, close: 4, volume: 100))
        }

        // V:999 应 shadow VOLUME=100
        let r = try runFormula("V:999; OUT:V;", bars: bars)
        let outLast = r[1].values.last ?? nil
        #expect(outLast == 999, "用户 V 必须 shadow VOLUME · 实际 \(String(describing: outLast))")

        // 同样测试 C / H / L / O / S
        let pairs: [(String, Decimal)] = [
            ("C", 7), ("H", 8), ("L", 9), ("O", 10), ("S", 11),
        ]
        for (name, expected) in pairs {
            let r2 = try runFormula("\(name):\(expected); OUT:\(name);", bars: bars)
            let v = r2[1].values.last ?? nil
            #expect(v == expected, "用户 \(name) 必须 shadow builtin · 实际 \(String(describing: v))")
        }
    }

    @Test("DIFF: V-S*S 在多 statement 公式中必须 ≈ 0（修复回归）")
    func testVarianceStdSquaredInMultiStatement() throws {
        var bars: [BarData] = []
        for i in 0..<1000 {
            let close = Decimal(3000 + (i % 20))
            bars.append(BarData(open: close, high: close, low: close, close: close, volume: 100))
        }

        let combined = try runFormula(
            "V:VARIANCE(CLOSE,20); S:STD(CLOSE,20); DIFF:V-S*S;",
            bars: bars
        )

        let vLast = combined[0].values.last ?? nil
        let sLast = combined[1].values.last ?? nil
        let diffLast = combined[2].values.last ?? nil

        #expect(vLast != nil)
        #expect(sLast != nil)
        #expect(diffLast != nil)

        // 修复后：DIFF 应 ≈ 0（仅 sqrt Double 精度损失 < 0.001 量级）
        if let diff = diffLast {
            #expect(abs(diff) < Decimal(string: "0.001")!,
                    "修复回归：DIFF 应 ≈ 0 · 实际 \(diff)（修复前 ≈ 66.75 = VOLUME - STD²）")
        }

        // 同时验证：单独 R: 公式（无变量遮蔽）· 与多 statement 结果一致
        let single = try runFormula(
            "R:VARIANCE(CLOSE,20)-STD(CLOSE,20)*STD(CLOSE,20);",
            bars: bars
        )
        let singleLast = single[0].values.last ?? nil
        if let multi = diffLast, let unified = singleLast {
            // 两种写法在修复后应等价
            #expect(abs(multi - unified) < Decimal(string: "0.001")!)
        }
    }

    @Test("中间变量按定义顺序生效（V 在 DIFF 之前定义 · DIFF 取 user V）")
    func testMultiStatementVariableLookup() throws {
        var bars: [BarData] = []
        for _ in 0..<5 {
            bars.append(BarData(open: 1, high: 1, low: 1, close: 1, volume: 100))
        }

        // V:42 然后 DIFF:V*2 应得 84（不是 VOLUME*2=200）
        let r = try runFormula("V:42; DIFF:V*2;", bars: bars)
        #expect(r[1].values.last ?? nil == 84)
    }
}
