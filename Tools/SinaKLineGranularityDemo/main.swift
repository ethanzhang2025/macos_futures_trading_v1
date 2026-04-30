// SinaKLineGranularityDemo · 第 23 个真数据 demo（探索 Sina K 线端点 type 粒度支持度）
//
// 背景：ChartScene.fetchHistoricalKLines 当前路径
//   - .minute5  → type=5  ✅ 已知支持
//   - .hour1    → type=60 ✅ 已知支持
//   - .daily/weekly/monthly → historicalDaily ✅ 已知支持
//   - default（minute1 / minute15 / minute30 / 其他）→ fallback type=15
//   注释说"Sina 不支持的 fallback 15min" 但 type=1/15/30 实际是否支持未验证
//
// 验证目的：
//   - type=1 / type=15 / type=30 端点是否可用？
//   - 若支持 → 接 ChartScene fetchHistoricalKLines · 修数据/UI 不一致 bug
//   - 若不支持 → 文档化 + 调整 supportedPeriods 或加 UI 警告
//
// 运行：swift run SinaKLineGranularityDemo
//
// 测试矩阵：2 合约（RB0 主连续 + rb2609 active 月份）× 5 type（1/5/15/30/60）= 10 真网络请求

import Foundation
import DataCore

@main
struct SinaKLineGranularityDemo {

    static func main() async throws {
        printSection("SinaKLineGranularityDemo（第 23 个真数据 demo · Sina K 线 type 粒度探索）")

        let symbols = ["RB0", "rb2609"]

        let sina = SinaMarketData()

        for symbol in symbols {
            printSection("合约 \(symbol) · 5 种 type 粒度")
            await testType(label: "type=1 ", bars: try? await sina.fetchMinute1KLines(symbol: symbol))
            await testType(label: "type=5 ", bars: try? await sina.fetchMinute5KLines(symbol: symbol))
            await testType(label: "type=15", bars: try? await sina.fetchMinute15KLines(symbol: symbol))
            await testType(label: "type=30", bars: try? await sina.fetchMinute30KLines(symbol: symbol))
            await testType(label: "type=60", bars: try? await sina.fetchMinute60KLines(symbol: symbol))
        }

        printSection("结论 + 建议")
        print("  根据上述实测结果：")
        print("  - 全部 ✅ → 扩 ChartScene fetchHistoricalKLines 走真 type · 修数据/UI 不一致")
        print("  - type=1/30 ❌ → 维持现状 fallback 15min · supportedPeriods 调整 / UI 加警告")
        print("  - 部分 ✅ → 按支持组合调整 ChartScene switch 路径")
    }

    private static func testType(label: String, bars: [SinaKLineBar]?) async {
        guard let b = bars, let last = b.last else {
            print("  ❌ \(label) → 0 根（端点不支持）")
            return
        }
        let close = NSDecimalNumber(decimal: last.close).doubleValue
        print("  ✅ \(label) → \(b.count) 根 · 末 close=\(fmt(close)) date=\(last.date)")
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private static func printSection(_ title: String) {
        print("")
        print(String(repeating: "─", count: 78))
        print("  \(title)")
        print(String(repeating: "─", count: 78))
    }
}
