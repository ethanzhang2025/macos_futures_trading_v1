// MaiYuYanWhDemo · 第 20 个真数据 demo（WP-63 · .wh 公式批量导入端到端）
//
// 用途：
// - 用 Sina 真行情（RB0 60min K 线）跑 .wh 文件批量导入：WhImporter.importAll → 编译 20 公式
// - 编译成功的公式再走 Interpreter.execute · 端到端验证"用户从文华复制 .wh → 我们引擎跑出结果"
// - 给销售 / 合规演示物料：覆盖 8 demo 公式 + 12 经典指标（KDJ/MACD/RSI/CCI/WR/ROC/BIAS/PSY/ATR/OBV/DMA/SLOPE）
//
// 运行：swift run MaiYuYanWhDemo
//
// 验收：20 公式 100% 编译 + 100% 执行成功（最后一行打印通过标志）

import Foundation
import Shared
import DataCore
import IndicatorCore

@main
struct MaiYuYanWhDemo {

    static func main() async throws {
        let symbol = "RB0"
        printSection("MaiYuYanWhDemo（第 20 个真数据 demo · \(symbol) 60min · WP-63 .wh 批量导入端到端）")

        // ─────────────── 段 1 · 拉真行情 ───────────────
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

        // ─────────────── 段 2 · WhImporter 批量编译 ───────────────
        printSection("段 2 · WhImporter.importAll · 20 公式 .wh 批量编译")
        let results = WhImporter.importAll(wenhuaTop20Wh)
        let compiledOK = results.filter { $0.isSuccess }.count
        print("  · 编译 \(compiledOK)/\(results.count)")
        for r in results where !r.isSuccess {
            if let err = r.error {
                print("    ❌ \(r.formula.name) · \(err)")
            }
        }

        // ─────────────── 段 3 · Interpreter 批量执行 ───────────────
        printSection("段 3 · Interpreter.execute · 编译成功公式批量执行")
        let interpreter = Interpreter()
        var executedOK = 0
        for (idx, r) in results.enumerated() {
            guard case .success(let formula) = r.compiled else { continue }
            do {
                let lines = try interpreter.execute(formula: formula, bars: bars)
                executedOK += 1
                let summary = lines.prefix(3).map { line -> String in
                    let lastVal = line.values.last ?? nil
                    return "\(line.name)末=\(fmt(lastVal))"
                }.joined(separator: " / ")
                print("  ✅ \(idx + 1). \(r.formula.name) · \(summary)\(lines.count > 3 ? " ..." : "")")
            } catch {
                print("  ❌ \(idx + 1). \(r.formula.name) · 执行失败：\(error)")
            }
        }

        // ─────────────── 段 4 · 总结 ───────────────
        printSection("段 4 · 总结")
        print("  · 编译：\(compiledOK)/20 \(compiledOK == 20 ? "✅" : "❌")")
        print("  · 执行：\(executedOK)/20 \(executedOK == 20 ? "✅" : "❌")")
        let allPass = compiledOK == 20 && executedOK == 20
        print(allPass
              ? "🎉 第 20 个真数据 demo 通过（20 公式 × 真行情 × 100% 编译 × 100% 执行）"
              : "❌ 未达标")
    }

    // MARK: - Helpers

    private static func printSection(_ title: String) {
        print("\n────── \(title) ──────")
    }

    private static func fmt(_ d: Decimal?) -> String {
        guard let d else { return "nil" }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: d as NSNumber) ?? "\(d)"
    }
}

// MARK: - 20 公式 .wh fixture（与 WhImporterTests.wenhuaTop20Formulas 同步 · demo 独立 hardcode）

private let wenhuaTop20Wh: String = """
# WP-63 · 20 个文华典型公式（.wh 批量导入演示）

{金叉死叉}
GOLD:CROSS(MA(CLOSE,5),MA(CLOSE,20));
DEAD:CROSSDOWN(MA(CLOSE,5),MA(CLOSE,20));

{布林通道外|MA20 ± 2σ 范围外}
M:MA(CLOSE,20);
S:STD(CLOSE,20);
OUT:NOT(RANGE(CLOSE,M-2*S,M+2*S));

{信号回设 3 根}
SIG:CROSS(MA(CLOSE,5),MA(CLOSE,20));
BS:BACKSET(SIG,3);

{波峰跟踪}
PB:PEAKBARS(CLOSE);
LP:LASTPEAK(CLOSE);

{波谷距离}
TB:TROUGHBARS(CLOSE);

{方差 vs STD²}
V:VARIANCE(CLOSE,20);
S:STD(CLOSE,20);
DIFF:V-S*S;

{中位数偏移}
MED:MEDIAN(CLOSE,21);
SPREAD:CLOSE-MED;

{MOD 取模}
P:MOD(CLOSE,5);

{KDJ|经典 9-3-3 KDJ}
RSV:=(CLOSE-LLV(LOW,9))/(HHV(HIGH,9)-LLV(LOW,9))*100;
K:SMA(RSV,3,1);
D:SMA(K,3,1);
J:3*K-2*D;

{MACD|经典 12-26-9 MACD}
DIFF:EMA(CLOSE,12)-EMA(CLOSE,26);
DEA:EMA(DIFF,9);
BAR:(DIFF-DEA)*2;

{RSI|14 期相对强弱指数}
LC:=REF(CLOSE,1);
RSI:SMA(MAX(CLOSE-LC,0),14,1)/SMA(ABS(CLOSE-LC),14,1)*100;

{CCI|14 期顺势指标}
TYP:=(HIGH+LOW+CLOSE)/3;
CCI:(TYP-MA(TYP,14))/(0.015*AVEDEV(TYP,14));

{WR|14 期威廉指标}
WR:100*(HHV(HIGH,14)-CLOSE)/(HHV(HIGH,14)-LLV(LOW,14));

{ROC|12 期变动率}
ROC:100*(CLOSE-REF(CLOSE,12))/REF(CLOSE,12);

{BIAS|6 期乖离率}
BIAS:(CLOSE-MA(CLOSE,6))/MA(CLOSE,6)*100;

{PSY|12 期心理线}
PSY:COUNT(CLOSE>REF(CLOSE,1),12)/12*100;

{ATR|14 期真实波幅}
TR:=MAX(MAX(HIGH-LOW,ABS(HIGH-REF(CLOSE,1))),ABS(LOW-REF(CLOSE,1)));
ATR:MA(TR,14);

{OBV|能量潮}
VA:=IF(CLOSE>REF(CLOSE,1),VOL,IF(CLOSE<REF(CLOSE,1),-VOL,0));
OBV:SUM(VA,0);

{DMA|动态平均}
AMA:DMA(CLOSE,0.1);

{SLOPE|10 期线性回归斜率}
SLP:SLOPE(CLOSE,10);
"""
