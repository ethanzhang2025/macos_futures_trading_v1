// JournalGenerator 半自动日志初稿真数据 demo（第 14 个真数据 demo）
//
// 用途：
// - 演示 P3 文华迁移用户的差异化能力："导入交割单后自动生成日志草稿"（文华没有）
// - 验证 windowSeconds 配置对聚合行为的影响（1h / 8h 默认 / 24h 三档对比）
// - 验证 A09 禁做项 ②：generator 单向不修改 trades 集合
// - 完整数据通路（接续第 13 个 demo）：CSV → Trade → JournalGenerator.generateDrafts → TradeJournal[]
//
// 拓扑（5 段）：
//   段 1 · 构造 7 笔 3 合约 trades（RB d1 三段 / IF d2-d3 三笔 / AU d2 单笔）
//   段 2 · 默认 8h 窗口生成草稿 + 详细打印（title / reason / tradeIDs.count）
//   段 3 · windowSeconds 配置对比（1h / 8h / 24h）→ 草稿数递减
//   段 4 · A09 禁做项 ② 验证（generator 前后 trades 集合 ==）
//   段 5 · 总结
//
// 运行：swift run JournalGeneratorDemo
// 注意：纯本地内存计算，不依赖 Sina 网络

import Foundation
import Shared
import JournalCore

@main
struct JournalGeneratorDemo {

    static func main() async throws {
        printSection("JournalGenerator 半自动日志初稿真数据 demo（第 14 个真数据 demo）")

        // 段 1：构造 trades
        printSection("段 1 · 构造 7 笔 3 合约 trades · 跨 3 天分散时段")
        let trades = makeTrades()
        print("  ✅ 构造 \(trades.count) 笔成交（3 合约：RB2510 / IF2506 / AU2510）")
        print("\n  [Trade 列表 · 按时间升序]")
        print("    时间                合约     方向  开平  价格      量")
        for t in trades.sorted(by: { $0.timestamp < $1.timestamp }) {
            let dir = t.direction == .buy ? "买" : "卖"
            let off = t.offsetFlag == .open ? "开" : "平"
            print("    \(formatDateTime(t.timestamp))  \(t.instrumentID.padded(7))  \(dir)    \(off)    \(fmt(t.price))   ×\(t.volume)")
        }

        // 段 2：默认 8h 窗口生成
        printSection("段 2 · 默认 8h 窗口生成草稿（详细打印第 1 条）")
        let drafts8h = JournalGenerator.generateDrafts(from: trades)
        print("  ✅ 生成 \(drafts8h.count) 条 TradeJournal 草稿（按 createdAt 倒序 · 最近在前）")
        print("\n  [全部草稿摘要]")
        for (i, d) in drafts8h.enumerated() {
            print("    [\(i+1)] \(d.title) · \(d.tradeIDs.count) 笔 · createdAt=\(formatDateTime(d.createdAt))")
        }
        if let first = drafts8h.first {
            print("\n  [第 1 条草稿详情]")
            print("    title:  \(first.title)")
            print("    tradeIDs: \(first.tradeIDs.count) 个")
            print("    reason 模板：")
            for line in first.reason.split(separator: "\n") {
                print("      \(line)")
            }
        }

        // 段 3：windowSeconds 对比
        printSection("段 3 · windowSeconds 配置对比（1h / 8h / 24h）")
        let drafts1h = JournalGenerator.generateDrafts(
            from: trades,
            configuration: .init(windowSeconds: 1 * 3600)
        )
        let drafts24h = JournalGenerator.generateDrafts(
            from: trades,
            configuration: .init(windowSeconds: 24 * 3600)
        )
        print("  📊 windowSeconds=1h   → \(drafts1h.count) 条草稿（窗口紧 · 每笔几乎独立）")
        print("  📊 windowSeconds=8h   → \(drafts8h.count) 条草稿（默认配置）")
        print("  📊 windowSeconds=24h  → \(drafts24h.count) 条草稿（窗口宽 · 同合约多日合并）")
        print("  💡 期望递减：1h ≥ 8h ≥ 24h（窗口越大草稿越少）")
        print("\n  [24h 草稿分桶情况]")
        for d in drafts24h {
            print("    - \(d.title)：\(d.tradeIDs.count) 笔合并到 1 篇")
        }

        // 段 4：A09 禁做项 ② 验证
        printSection("段 4 · A09 禁做项 ② 验证（generator 不修改 trades · 单向）")
        let tradesBefore = trades  // 拷贝
        for windowSeconds in [8 * 3600, 100, 999_999] as [TimeInterval] {
            _ = JournalGenerator.generateDrafts(from: trades, configuration: .init(windowSeconds: windowSeconds))
        }
        let unchanged = (trades == tradesBefore)
        print("  \(unchanged ? "✅" : "❌") trades 集合在 3 次 generateDrafts 后保持不变：\(unchanged)")
        print("  💡 含义：journal.tradeIDs 单向引用 trade · 不允许反向污染")

        // 段 5：总结
        let allOK = drafts1h.count >= drafts8h.count &&
                     drafts8h.count >= drafts24h.count &&
                     drafts24h.count >= 1 &&
                     unchanged
        printSection(allOK
            ? "🎉 第 14 个真数据 demo 通过（JournalGenerator 半自动初稿 · 配置对比 · 单向引用）"
            : "⚠️  草稿数未递减或 trades 被污染（详见上方）")
    }

    // MARK: - 数据构造

    static func makeTrades() -> [Trade] {
        // 设计意图（让 1h/8h/24h 三档对比有显著差异）：
        // RB2510 d1：09:30 / 14:00 / 22:30（间隔 4.5h + 8.5h）→ 8h 分段为 [09:30,14:00]+[22:30] 2 段；24h 合并 1 段
        // IF2506 d2-d3：d2 10:15 / d2 22:30 / d3 10:00（间隔 12.25h + 11.5h）→ 8h 各独立 3 段；24h 合并 1 段
        // AU2510 d2：09:00 单独 → 1 段（任何窗口都 1 段）
        // 期望：1h=7 / 8h=2+3+1=6 / 24h=1+1+1=3
        return [
            mk("2026-04-23 09:30", "RB2510", .buy,  .open,  3100, 2),
            mk("2026-04-23 14:00", "RB2510", .sell, .close, 3180, 2),
            mk("2026-04-23 22:30", "RB2510", .buy,  .open,  3120, 1),
            mk("2026-04-24 10:15", "IF2506", .sell, .open,  4220, 1),
            mk("2026-04-24 22:30", "IF2506", .buy,  .close, 4150, 1),
            mk("2026-04-25 10:00", "IF2506", .sell, .open,  4180, 1),
            mk("2026-04-24 09:00", "AU2510", .buy,  .open,  1041, 3)
        ]
    }

    static func mk(
        _ time: String,
        _ instrumentID: String,
        _ direction: Direction,
        _ offset: OffsetFlag,
        _ price: Decimal,
        _ volume: Int
    ) -> Trade {
        Trade(
            tradeReference: "JG-\(UUID().uuidString.prefix(6))",
            instrumentID: instrumentID,
            direction: direction,
            offsetFlag: offset,
            price: price,
            volume: volume,
            commission: Decimal(volume) * 2.3,
            timestamp: tradeTimeFormatter.date(from: time)!,
            source: .manual
        )
    }

    // MARK: - 通用 helpers

    static func fmt(_ value: Decimal) -> String {
        priceFormatter.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func formatDateTime(_ date: Date) -> String {
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
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    private static let tradeTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

private extension String {
    func padded(_ length: Int) -> String {
        padding(toLength: length, withPad: " ", startingAt: 0)
    }
}
