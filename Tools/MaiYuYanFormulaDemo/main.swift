// MaiYuYanFormulaDemo · 第 18 个真数据 demo
//
// 用途：
// - 用 Sina 真行情（RB0 60min K 线）跑 8 个文华常见公式
// - 验证 v6.0+ 麦语言扩展第 1+2 批共 10 个新函数在真数据下工作
// - 给销售 / 合规演示物料：用户从文华复制公式 → 我们的引擎跑出结果
//
// 覆盖的 10 个新函数（expectedNewFunctions 集合）：
//   NOT / CROSSDOWN / MOD / PEAKBARS / TROUGHBARS /
//   BACKSET / VARIANCE / RANGE / MEDIAN / LASTPEAK
// 注：公式 1 顺带用了 CROSS（老函数 · 仅作 CROSSDOWN 的对照参照，不计入覆盖）
//
// 运行：swift run MaiYuYanFormulaDemo
//
// 验收：8 公式全部跑通 + 10 新函数全部覆盖

import Foundation
import Shared
import DataCore
import IndicatorCore

@main
struct MaiYuYanFormulaDemo {

    private struct FormulaCase {
        let name: String
        let source: String
        let usedFunctions: [String]
    }

    private static let formulas: [FormulaCase] = [
        .init(name: "金叉死叉",
              source: "GOLD:CROSS(MA(CLOSE,5),MA(CLOSE,20)); DEAD:CROSSDOWN(MA(CLOSE,5),MA(CLOSE,20));",
              usedFunctions: ["CROSSDOWN"]),
        .init(name: "布林通道外",
              source: "M:MA(CLOSE,20); S:STD(CLOSE,20); OUT:NOT(RANGE(CLOSE,M-2*S,M+2*S));",
              usedFunctions: ["NOT", "RANGE"]),
        .init(name: "信号回设 3 根",
              source: "SIG:CROSS(MA(CLOSE,5),MA(CLOSE,20)); BS:BACKSET(SIG,3);",
              usedFunctions: ["BACKSET"]),
        .init(name: "波峰跟踪",
              source: "PB:PEAKBARS(CLOSE); LP:LASTPEAK(CLOSE);",
              usedFunctions: ["PEAKBARS", "LASTPEAK"]),
        .init(name: "波谷距离",
              source: "TB:TROUGHBARS(CLOSE);",
              usedFunctions: ["TROUGHBARS"]),
        .init(name: "20 周期方差 vs STD²",
              source: "V:VARIANCE(CLOSE,20); S:STD(CLOSE,20); DIFF:V-S*S;",
              usedFunctions: ["VARIANCE"]),
        .init(name: "中位数偏移",
              source: "MED:MEDIAN(CLOSE,21); SPREAD:CLOSE-MED;",
              usedFunctions: ["MEDIAN"]),
        .init(name: "MOD 收盘价取模",
              source: "P:MOD(CLOSE,5);",
              usedFunctions: ["MOD"]),
    ]

    private static let expectedNewFunctions: Set<String> = [
        "NOT", "CROSSDOWN", "MOD", "PEAKBARS", "TROUGHBARS",
        "BACKSET", "VARIANCE", "RANGE", "MEDIAN", "LASTPEAK"
    ]

    static func main() async throws {
        let symbol = "RB0"
        printSection("MaiYuYanFormulaDemo（第 18 个真数据 demo · \(symbol) 60min · 跑 v6.0+ 第 1+2 批 10 函数）")

        // ─────────────── 段 1 ───────────────
        printSection("段 1 · 拉 Sina RB0 60min K 线")
        let sina = SinaMarketData()
        let sinaBars = try await sina.fetchMinute60KLines(symbol: symbol)
        guard !sinaBars.isEmpty else {
            print("❌ 0 K 线，退出")
            return
        }
        let bars: [BarData] = sinaBars.map {
            BarData(
                open: $0.open, high: $0.high, low: $0.low, close: $0.close,
                volume: Int($0.volume), amount: 0, openInterest: 0
            )
        }
        print("  ✅ \(bars.count) 根 · 最早 \(sinaBars.first!.date) ～ 最新 \(sinaBars.last!.date)")
        print("  📈 末根 close = \(fmt(bars.last!.close))")

        // ─────────────── 段 2 ───────────────
        printSection("段 2 · 跑 8 个文华常见公式")
        let interpreter = Interpreter()
        var allOK = true
        var coverage = Set<String>()
        for (idx, fc) in formulas.enumerated() {
            print("─ 公式 \(idx + 1) · \(fc.name)（用到新函数：\(fc.usedFunctions.joined(separator: ", "))）")
            print("    源: \(fc.source)")
            // WHY do/catch：单个公式失败不应中断后续 7 条 + 覆盖统计；catch 内仅打印不 rethrow
            do {
                let lines = try runFormula(source: fc.source, bars: bars, interpreter: interpreter)
                for line in lines {
                    // [Decimal?].last 返回 Decimal??，需 ?? nil 摊平到 Decimal?
                    let lastVal = line.values.last ?? nil
                    let triggers = line.values.lazy.compactMap { $0 }.filter { $0 == 1 }.count
                    print("    · \(line.name) · 末值=\(fmt(lastVal)) · 触发=1 次数=\(triggers)")
                }
                coverage.formUnion(fc.usedFunctions)
            } catch {
                print("    ❌ 失败：\(error)")
                allOK = false
            }
        }

        // ─────────────── 段 3 ───────────────
        printSection("段 3 · 10 新函数覆盖验证")
        let covered = expectedNewFunctions.intersection(coverage)
        let missing = expectedNewFunctions.subtracting(coverage)
        print("  覆盖（\(covered.count)/\(expectedNewFunctions.count)）：\(covered.sorted().joined(separator: ", "))")
        if !missing.isEmpty {
            print("  ❌ 缺：\(missing.sorted().joined(separator: ", "))")
            allOK = false
        } else {
            print("  ✅ 全 10 函数覆盖")
        }

        // ─────────────── 段 4 ───────────────
        printSection(allOK && missing.isEmpty
            ? "🎉 第 18 个真数据 demo 通过（8 公式 × 真行情 × 10 新函数全覆盖）"
            : "⚠️  MaiYuYanFormulaDemo 验收未达标")
    }

    // MARK: - helpers

    /// 一条公式跑全套：lex → parse → execute · 抽出仅为让段 2 主循环更扁平
    private static func runFormula(
        source: String,
        bars: [BarData],
        interpreter: Interpreter
    ) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try interpreter.execute(formula: formula, bars: bars)
    }

    static func fmt(_ value: Decimal?) -> String {
        guard let v = value else { return "nil" }
        return fmt(v)
    }

    static func fmt(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 4
        nf.minimumFractionDigits = 0
        return nf.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}
