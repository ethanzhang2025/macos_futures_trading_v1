// SinaMonthlyContractDemo · 第 21 个真数据 demo（探索 Sina API 月份合约支持度）
//
// 用途：
// - 验证 Sina 实时报价 / 历史 K 线端点是否支持月份合约（rb2510 / RB2510 / I2509 / AU2512 / IF2510 等）
// - 6 合约 × 3 端点 = 18 个真网络请求 · 每个报告：响应/字段/合理性
// - 结论指导 supportedContracts 是否扩展月份合约（解锁 Watchlist 真实持仓盯盘场景）
//
// 运行：swift run SinaMonthlyContractDemo
//
// 三类结果：
//   ✅ 全字段合理 → 支持
//   ⚠️ 端点返回但字段为 0 → 部分支持（合约不存在 / 已下市 / 未活跃）
//   ❌ 网络失败 / 解析失败 → 不支持

import Foundation
import DataCore

@main
struct SinaMonthlyContractDemo {

    static func main() async throws {
        printSection("SinaMonthlyContractDemo（第 21 个真数据 demo · 探索 Sina 月份合约支持）")

        // 测试矩阵：10 合约 · baseline 主连续 + 已交割对照 + 当前活跃（2026-04-29）
        // 已交割合约：测 K 线历史端点是否回放完整生命周期
        // 活跃合约：测当前实盘是否能拿到真行情（用户实际持仓的合约）
        let symbols: [(label: String, code: String)] = [
            ("RB0    主连续 baseline 螺纹钢",     "RB0"),
            ("RB2510 已交割大写 螺纹 25-10",     "RB2510"),
            ("rb2510 已交割小写 螺纹 25-10",     "rb2510"),
            ("I2509  已交割大写 铁矿 25-09",     "I2509"),
            ("AU2512 已交割大写 黄金 25-12",     "AU2512"),
            ("IF2510 已交割大写 股指 25-10",     "IF2510"),
            ("rb2609 活跃 螺纹 26-09 主力月",     "rb2609"),
            ("i2609  活跃 铁矿 26-09 主力月",     "i2609"),
            ("au2606 活跃 黄金 26-06 主力月",     "au2606"),
            ("IF2605 活跃 股指 26-05 主力月",     "IF2605")
        ]

        let sina = SinaMarketData()

        printSection("段 1 · 实时报价 fetchQuote (端点 hq.sinajs.cn/list=nf_<code>)")
        for entry in symbols {
            await testQuote(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 2 · 60min K 线 fetchMinute60KLines (端点 InnerFuturesNewService.getFewMinLine type=60)")
        for entry in symbols {
            await testMinuteKLines(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 3 · 日 K 线 fetchDailyKLines (端点 InnerFuturesNewService.getDailyKLine)")
        for entry in symbols {
            await testDailyKLines(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 4 · 探索结论（2026-04-29 实测）")
        print("  ✅ K 线端点（60min + 日 K）：完全支持月份合约（大小写 + I 字母均可 · 含活跃 + 已交割）")
        print("     → 主图可切月份合约 · 显示真实历史 + 当日数据（活跃合约末 date = 今日）")
        print("")
        print("  ⚠️  实时报价端点（hq.sinajs.cn nf_<code>）：部分支持")
        print("     ✅ 大写 + 非 I 字母合约 → RB2510 / AU2512 / IF2510 / IF2605")
        print("     ❌ 小写 / I 字母合约 → rb2510 / I2509 / rb2609 / i2609 / au2606")
        print("     → 影响 priceTopBar preSettle / Watchlist 行情列表 · 已有 fallback")
        print("")
        print("  📋 实施建议：")
        print("     短期：扩 MarketDataPipeline.supportedContracts 加 active 月份合约（rb2609 / i2609 / au2606 / IF2605）")
        print("           主图 K 线端点 OK · priceTopBar preSettle 失败时 fallback first.close（v12.1 已实现）")
        print("     中期：实现\"主力月动态计算\"（按 oi / 月份递增推断）")
        print("     长期：Stage B CTP 接入 SimNow 真实时数据 · K 线仍走 Sina")
        print("")
        print("  💡 解锁场景：")
        print("     - 用户在 Watchlist 加 rb2609 等真实持仓 → 主图盯盘真月份合约（K 线 OK）")
        print("     - WatchlistImporter（WP-64）文华自选导入的月份合约可直接用")
    }

    // MARK: - 测试辅助

    private static func testQuote(sina: SinaMarketData, label: String, code: String) async {
        do {
            let quote = try await sina.fetchQuote(symbol: code)
            guard let q = quote else {
                print("  ❌ \(label) → 无返回（解析失败 / 字段不足）")
                return
            }
            let lastPriceD = NSDecimalNumber(decimal: q.lastPrice).doubleValue
            let preSettleD = NSDecimalNumber(decimal: q.preSettlement).doubleValue
            let oi = q.openInterest
            let vol = q.volume

            // 字段合理性：lastPrice > 0 + 任一 (preSettle > 0 / oi > 0 / vol > 0)
            let hasPrice = lastPriceD > 0
            let hasContext = preSettleD > 0 || oi > 0 || vol > 0
            let icon = hasPrice && hasContext ? "✅" : (hasPrice ? "⚠️ " : "❌")
            let detail = "last=\(fmt(lastPriceD)) preSettle=\(fmt(preSettleD)) oi=\(oi) vol=\(vol) name=\(q.name)"
            print("  \(icon) \(label) → \(detail)")
        } catch {
            print("  ❌ \(label) → \(error)")
        }
    }

    private static func testMinuteKLines(sina: SinaMarketData, label: String, code: String) async {
        do {
            let bars = try await sina.fetchMinute60KLines(symbol: code)
            guard !bars.isEmpty else {
                print("  ❌ \(label) → 0 根（端点不支持 / 合约不存在）")
                return
            }
            let last = bars.last!
            let closeD = NSDecimalNumber(decimal: last.close).doubleValue
            let icon = closeD > 0 ? "✅" : "⚠️ "
            print("  \(icon) \(label) → \(bars.count) 根 · 末 close=\(fmt(closeD)) date=\(last.date)")
        } catch {
            print("  ❌ \(label) → \(error)")
        }
    }

    private static func testDailyKLines(sina: SinaMarketData, label: String, code: String) async {
        do {
            let bars = try await sina.fetchDailyKLines(symbol: code)
            guard !bars.isEmpty else {
                print("  ❌ \(label) → 0 根（端点不支持 / 合约不存在）")
                return
            }
            let last = bars.last!
            let closeD = NSDecimalNumber(decimal: last.close).doubleValue
            let icon = closeD > 0 ? "✅" : "⚠️ "
            print("  \(icon) \(label) → \(bars.count) 根 · 末 close=\(fmt(closeD)) date=\(last.date)")
        } catch {
            print("  ❌ \(label) → \(error)")
        }
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private static func printSection(_ title: String) {
        print("")
        print(String(repeating: "─", count: 78))
        print("  \(title)")
        print(String(repeating: "─", count: 78))
    }
}
