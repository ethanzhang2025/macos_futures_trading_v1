// WP-52 · 条件预警真数据冒烟 demo
//
// 用途：
// - Sina 真行情 → AlertEvaluator.onTick → 触发预警 → AsyncStream 收事件
// - 设 4 类价格预警：必触发 2 个 / 不触发 2 个 · 验证条件判断 + 频控 + AsyncStream 闭环
//
// 运行：swift run AlertSmokeDemo

import Foundation
import Shared
import DataCore
import AlertCore

@main
struct AlertSmokeDemo {

    static func main() async throws {
        print("─────────────────────────────────────────────")
        print("WP-52 · 条件预警真数据冒烟（RB0 螺纹钢 · 真行情驱动）")
        print("─────────────────────────────────────────────")

        // 1. 拉一次当前价做基线
        let sina = SinaMarketData()
        let baselineQuote = try? await sina.fetchQuote(symbol: "RB0")
        let baseline = baselineQuote?.lastPrice ?? 3193
        print("✅ Sina 基线报价 RB0 last=\(baseline)")

        // 2. 设 4 类预警（基于基线价）
        let alerts: [Alert] = [
            Alert(
                name: "RB0 涨破 \(baseline - 1000) [必触发]",
                instrumentID: "RB0",
                condition: .priceAbove(baseline - 1000),
                cooldownSeconds: 10000  // 长冷却 → 只触发 1 次
            ),
            Alert(
                name: "RB0 跌破 \(baseline + 1000) [必触发]",
                instrumentID: "RB0",
                condition: .priceBelow(baseline + 1000),
                cooldownSeconds: 10000
            ),
            Alert(
                name: "RB0 涨破 \(baseline + 1000) [不应触发]",
                instrumentID: "RB0",
                condition: .priceAbove(baseline + 1000),
                cooldownSeconds: 10000
            ),
            Alert(
                name: "RB0 跌破 \(baseline - 1000) [不应触发]",
                instrumentID: "RB0",
                condition: .priceBelow(baseline - 1000),
                cooldownSeconds: 10000
            )
        ]

        let historyStore = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: historyStore)
        for alert in alerts {
            await evaluator.addAlert(alert)
        }
        print("✅ 注册 \(alerts.count) 个预警（2 必触发 / 2 不应触发）")

        // 3. 启动 SinaProvider 真行情订阅
        let provider = SinaMarketDataProvider(fetcher: sina)
        await provider.connect()

        let counter = TriggerCounter()

        // 监听预警事件流
        let eventStream = await evaluator.observe()
        let eventTask = Task {
            for await event in eventStream {
                let stamp = formatNow()
                print("[\(stamp)] 🔔 触发：\(event.alertName) · price=\(event.triggerPrice)")
                await counter.bump(event.alertID)
            }
        }

        // 真行情 → AlertEvaluator
        let evaluatorRef = evaluator
        await provider.subscribe("RB0") { tick in
            Task { await evaluatorRef.onTick(tick) }
        }

        let driver = SinaPollingDriver(provider: provider, interval: 3.0)
        await driver.start()

        print("✅ 启动 Sina 轮询（3s 间隔）· 跑 30 秒")
        print("─────────────────────────────────────────────")

        try await Task.sleep(nanoseconds: 30 * 1_000_000_000)

        await driver.stop()
        await provider.disconnect()
        eventTask.cancel()

        // 4. 统计
        print("─────────────────────────────────────────────")
        let counts = await counter.snapshot()
        print("\n触发统计（30 秒）：")
        for alert in alerts {
            let count = counts[alert.id] ?? 0
            let expected = alert.name.contains("[必触发]") ? "≥1" : "0"
            let status = matches(count: count, expected: expected) ? "✅" : "❌"
            print("  \(status) \(alert.name) → \(count) 次（期望 \(expected)）")
        }

        let triggerCount = counts.values.reduce(0, +)
        print("\n  总触发：\(triggerCount) 次")

        // history 验证
        let allHistory = (try? await historyStore.allHistory()) ?? []
        print("  AlertHistory 持久化：\(allHistory.count) 条")

        print("─────────────────────────────────────────────")
        let allPassed = alerts.allSatisfy { alert in
            let count = counts[alert.id] ?? 0
            let expected = alert.name.contains("[必触发]") ? "≥1" : "0"
            return matches(count: count, expected: expected)
        }
        if allPassed {
            print("🎉 WP-52 条件预警真数据冒烟全通")
        } else {
            print("⚠️  部分预警未按期望触发")
        }
    }

    static func matches(count: Int, expected: String) -> Bool {
        switch expected {
        case "0":  return count == 0
        case "≥1": return count >= 1
        default:   return false
        }
    }

    static func formatNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

// 触发计数器
private actor TriggerCounter {
    private var counts: [UUID: Int] = [:]
    func bump(_ id: UUID) { counts[id, default: 0] += 1 }
    func snapshot() -> [UUID: Int] { counts }
}

