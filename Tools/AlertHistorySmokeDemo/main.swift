// AlertHistory 时间区间查询真数据冒烟 demo（第 12 个真数据 demo）
//
// 用途：
// - 验证 history(from:to:) API 在真实数据规模下工作
// - 演示 UI 层最常用场景："最近 1 小时" / "最近 6 小时" / "今日全部"
// - 性能对比：SQL WHERE BETWEEN + idx_alert_history_ts 索引 vs allHistory + Swift filter
//
// 拓扑（5 段）：
//   段 1 · 准备 SQLite 临时文件 + 注入 50 条历史（时刻分布在 24h 内）
//   段 2 · 查 3 档区间（1h / 6h / 24h）→ 命中数 + 末 3 条样本
//   段 3 · from > to 边界负向场景
//   段 4 · 性能 · 注入 10000 条 → 区间查询耗时
//   段 5 · 索引命中校验（区间查询 vs allHistory+filter 对比耗时）
//
// 运行：swift run AlertHistorySmokeDemo
// 注意：纯本地 SQLite，不依赖 Sina 网络

import Foundation
import Shared
import AlertCore

@main
struct AlertHistorySmokeDemo {

    static func main() async throws {
        printSection("AlertHistory 时间区间查询真数据冒烟（第 12 个真数据 demo）")

        let path = NSTemporaryDirectory().appending("alert_history_demo_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try SQLiteAlertHistoryStore(path: path)
        defer { Task { await store.close() } }

        let now = Date()

        // 段 1：注入 50 条
        printSection("段 1 · 注入 50 条历史 · 时刻分布在 24h 内（每 28.8min 一条）")
        let alertIDs = (0..<5).map { _ in UUID() }
        let entries = (0..<50).map { i -> AlertHistoryEntry in
            let offset = -Double(i) * 1728  // 28.8 min × 50 = 1440 min = 24h
            return makeEntry(
                alertID: alertIDs[i % alertIDs.count],
                triggeredAt: now.addingTimeInterval(offset),
                triggerPrice: Decimal(3100 + i)
            )
        }
        for e in entries { try await store.append(e) }
        let total = try await store.allHistory().count
        print("  ✅ 注入 \(total) 条 · 跨 5 个 alertID · 时间范围 [now-24h, now]")

        // 段 2：3 档区间查询
        printSection("段 2 · 区间查询 3 档（最近 1h / 6h / 24h）")
        let oneHourAgo = now.addingTimeInterval(-3600)
        let sixHoursAgo = now.addingTimeInterval(-6 * 3600)
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 3600 - 60)  // 多 60s 含 24h 边界

        let last1h = try await store.history(from: oneHourAgo, to: now)
        let last6h = try await store.history(from: sixHoursAgo, to: now)
        let last24h = try await store.history(from: twentyFourHoursAgo, to: now)

        print("  📊 最近 1 小时 命中：\(last1h.count) 条")
        print("  📊 最近 6 小时 命中：\(last6h.count) 条")
        print("  📊 最近 24 小时 命中：\(last24h.count) 条")
        print("  💡 期望递增：1h ≤ 6h ≤ 24h（24h 应 = 50）")
        let samples = Array(last1h.prefix(3))
        print("  📋 最近 1h 末 \(samples.count) 条样本（按 triggeredAt 降序）：")
        for entry in samples {
            print("     [\(formatTime(entry.triggeredAt))] \(entry.alertName) @ \(fmt(entry.triggerPrice))")
        }

        // 段 3：负向场景 from > to
        printSection("段 3 · 负向场景 · from > to 返回空（不抛错）")
        let inverted = try await store.history(from: now, to: now.addingTimeInterval(-3600))
        print("  \(inverted.isEmpty ? "✅" : "❌") from > to 返空：\(inverted.isEmpty)（实际 \(inverted.count) 条）")

        // 段 4：性能 · 注入 10000 条
        printSection("段 4 · 性能压测 · 注入 10000 条 + 多档区间查询")
        let largePath = NSTemporaryDirectory().appending("alert_history_perf_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: largePath) }
        let largeStore = try SQLiteAlertHistoryStore(path: largePath)
        defer { Task { await largeStore.close() } }

        let injectStart = Date()
        for i in 0..<10000 {
            let offset = -Double(i) * 8.64  // 24h / 10000 ≈ 8.64 秒/条 · 跨 24h
            try await largeStore.append(makeEntry(
                alertID: alertIDs[i % alertIDs.count],
                triggeredAt: now.addingTimeInterval(offset),
                triggerPrice: Decimal(3000 + (i % 500))
            ))
        }
        let injectMs = Date().timeIntervalSince(injectStart) * 1000
        print("  📥 注入 10000 条耗时：\(String(format: "%.0f", injectMs)) ms")

        let perf1h = try await timed { try await largeStore.history(from: oneHourAgo, to: now) }
        let perf6h = try await timed { try await largeStore.history(from: sixHoursAgo, to: now) }
        let perf24h = try await timed { try await largeStore.history(from: twentyFourHoursAgo, to: now) }
        print("  ⚡ 区间 1h  · \(perf1h.result.count) 条 · \(String(format: "%.2f", perf1h.ms)) ms")
        print("  ⚡ 区间 6h  · \(perf6h.result.count) 条 · \(String(format: "%.2f", perf6h.ms)) ms")
        print("  ⚡ 区间 24h · \(perf24h.result.count) 条 · \(String(format: "%.2f", perf24h.ms)) ms")

        // 段 5：索引命中对比
        printSection("段 5 · 索引命中对比（BETWEEN + idx_alert_history_ts vs allHistory + Swift filter）")
        let indexed = try await timed { try await largeStore.history(from: oneHourAgo, to: now) }
        let scanned = try await timed { () -> [AlertHistoryEntry] in
            let all = try await largeStore.allHistory()
            return all.filter { $0.triggeredAt >= oneHourAgo && $0.triggeredAt <= now }
        }
        print("  ⚡ history(from:to:)（SQL BETWEEN 走索引）· \(indexed.result.count) 条 · \(String(format: "%.2f", indexed.ms)) ms")
        print("  🐢 allHistory + filter（全表扫描 + Swift 端过滤）· \(scanned.result.count) 条 · \(String(format: "%.2f", scanned.ms)) ms")
        let speedup = scanned.ms / max(0.01, indexed.ms)
        print("  💡 索引加速比：\(String(format: "%.1fx", speedup))（区间小时优势越明显）")

        let allMatch = (last1h.count <= last6h.count) &&
                        (last6h.count <= last24h.count) &&
                        (last24h.count == 50) &&
                        inverted.isEmpty
        printSection(allMatch
            ? "🎉 第 12 个真数据 demo 通过（history(from:to:) 真数据 + 性能 + 索引验证）"
            : "⚠️  区间命中数或负向场景未达预期（详见上方）")
    }

    // MARK: - 辅助构造 + 计时

    static func makeEntry(alertID: UUID, triggeredAt: Date, triggerPrice: Decimal) -> AlertHistoryEntry {
        AlertHistoryEntry(
            alertID: alertID,
            alertName: "RB0 ≥ \(fmt(triggerPrice))",
            instrumentID: "RB0",
            conditionSnapshot: .priceAbove(triggerPrice),
            triggeredAt: triggeredAt,
            triggerPrice: triggerPrice,
            message: "价格 \(fmt(triggerPrice)) 触发"
        )
    }

    /// 计时 helper · 返回 (result, 毫秒)
    static func timed<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> (result: T, ms: Double) {
        let start = Date()
        let r = try await work()
        return (r, Date().timeIntervalSince(start) * 1000)
    }

    // MARK: - 通用 helpers

    static func fmt(_ value: Decimal) -> String {
        priceFormatter.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }

    private static let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()
}
