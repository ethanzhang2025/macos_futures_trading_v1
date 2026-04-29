// SinaQuoteWorkaroundDemo · 第 22 个真数据 demo（探索 Sina 实时报价失败合约的 workaround）
//
// v12.2 已知问题（SinaMonthlyContractDemo e386a53）：
//   实时报价 fetchQuote 端点对 4 类合约失败：
//   - rb2510 / rb2609 / au2606（小写月份合约）
//   - i2609 / I2509（i/I 字母铁矿）
//
// 探索 2 种 workaround：
//   W1 大小写转换：自动 uppercase 后重试（rb2609 → RB2609）
//   W4 K 线 5min 最末根作伪实时：从 fetchMinute5KLines 末根 close + volume 构造伪 quote
//      （K 线端点已证实 100% 支持月份合约 · 含 i 字母）
//
// 运行：swift run SinaQuoteWorkaroundDemo
//
// 三类结果：
//   ✅ workaround 成功 → 字段合理（last > 0）
//   ⚠️  workaround 部分成功（K 线 OK 但字段不全 · 如 preSettle 缺失）
//   ❌ 仍失败 → 该 workaround 不适用

import Foundation
import DataCore

@main
struct SinaQuoteWorkaroundDemo {

    static func main() async throws {
        printSection("SinaQuoteWorkaroundDemo（第 22 个真数据 demo · 探索失败合约 workaround）")

        // v12.2 已知失败的 4 类合约 · 加 1 baseline 已知支持作对比
        let failedSymbols: [(label: String, code: String)] = [
            ("baseline RB2510 已知大写支持",    "RB2510"),
            ("rb2609 失败 螺纹小写",             "rb2609"),
            ("i2609  失败 铁矿 i 小写",          "i2609"),
            ("au2606 失败 黄金小写",             "au2606"),
            ("I2509  失败 铁矿 I 大写已交割",    "I2509")
        ]

        let sina = SinaMarketData()

        printSection("段 1 · W1 大小写转换 workaround（小写 → uppercase 重试）")
        for entry in failedSymbols {
            await testW1Uppercase(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 2 · W4 K 线 5min 末根伪实时 workaround（fetchMinute5KLines 末根）")
        for entry in failedSymbols {
            await testW4KLineFallback(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 3 · 探索 fetchTimeline 分时数据可用性（末点 = 当前价候选）")
        for entry in failedSymbols {
            await testTimeline(sina: sina, label: entry.label, code: entry.code)
        }

        printSection("段 4 · 结论 + 落地建议")
        print("  W1 大小写转换：")
        print("     ✅ 解决小写合约 → 改 SinaMarketData.fetchQuote 自动 uppercase 即可（最简单 workaround）")
        print("     ❌ 不解决 i/I 字母合约失败（铁矿 Sina 实时报价端点不支持）")
        print("")
        print("  W4 K 线 5min 末根伪实时：")
        print("     ✅ 适用所有 K 线端点支持的合约（含 i 字母）· 可作通用 fallback")
        print("     ⚠️  字段降级：preSettle 缺失（K 线无前结算字段）→ priceTopBar baseline 仍 fallback first.close")
        print("     ⚠️  非真实时（5min 周期延迟）· 但盯盘体验已显著优于显示「—」")
        print("")
        print("  📋 实施建议：SinaMarketData.fetchQuoteWithFallback：")
        print("     1) 先 fetchQuote(uppercase(code))（W1）→ 成功则直接返回")
        print("     2) 失败 → fetchMinute5KLines(code) 末根构造 partial quote（W4）")
        print("     3) ChartScene fetchPreSettle 改用此函数 · Watchlist 行情列表也走此函数")
    }

    // MARK: - W1: 大小写转换

    private static func testW1Uppercase(sina: SinaMarketData, label: String, code: String) async {
        let upper = code.uppercased()
        let attempted = upper == code ? "(原大写 不变)" : "(\(code) → \(upper))"
        do {
            let quote = try await sina.fetchQuote(symbol: upper)
            guard let q = quote else {
                print("  ❌ \(label) \(attempted) → 无返回")
                return
            }
            let last = NSDecimalNumber(decimal: q.lastPrice).doubleValue
            let pre = NSDecimalNumber(decimal: q.preSettlement).doubleValue
            let icon = last > 0 ? "✅" : "⚠️ "
            print("  \(icon) \(label) \(attempted) → last=\(fmt(last)) preSettle=\(fmt(pre)) oi=\(q.openInterest) vol=\(q.volume)")
        } catch {
            print("  ❌ \(label) \(attempted) → \(error)")
        }
    }

    // MARK: - W4: K 线 5min 末根伪实时

    private static func testW4KLineFallback(sina: SinaMarketData, label: String, code: String) async {
        do {
            let bars = try await sina.fetchMinute5KLines(symbol: code)
            guard let last = bars.last else {
                print("  ❌ \(label) → 0 K 线（端点也不支持）")
                return
            }
            let close = NSDecimalNumber(decimal: last.close).doubleValue
            let icon = close > 0 ? "✅" : "⚠️ "
            print("  \(icon) \(label) → 末根 close=\(fmt(close)) date=\(last.date) vol=\(last.volume) oi=\(last.openInterest) (从 \(bars.count) 根 5min K 线)")
        } catch {
            print("  ❌ \(label) → \(error)")
        }
    }

    // MARK: - W3: 分时数据探索

    private static func testTimeline(sina: SinaMarketData, label: String, code: String) async {
        do {
            let points = try await sina.fetchTimeline(symbol: code)
            guard let last = points.last else {
                print("  ❌ \(label) → 0 分时点")
                return
            }
            let price = NSDecimalNumber(decimal: last.price).doubleValue
            let avg = NSDecimalNumber(decimal: last.avgPrice).doubleValue
            print("  ✅ \(label) → 末点 time=\(last.time) price=\(fmt(price)) avg=\(fmt(avg)) (\(points.count) 点)")
        } catch {
            print("  ❌ \(label) → \(error)")
        }
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private static func printSection(_ title: String) {
        print("")
        print(String(repeating: "─", count: 78))
        print("  \(title)")
        print(String(repeating: "─", count: 78))
    }
}
