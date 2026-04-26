// StoreManager M5 启动流程预演（第 17 个真数据 demo）
//
// 用途：
// - 验证 WP-19a-7：StoreManager 一次 init → 6 store 联动写读 → close → 重启恢复
// - 模拟 M5 上线后用户首次登录 + 业务数据持久化 + 登出 + 重新登录恢复全流程
// - 端到端覆盖：6 store 联动 + 加密路径 + 错误密钥拒绝 + 6 文件 hexdump 全验证
// - UI 启动只需 1 行：try StoreManager(rootDirectory: appSupportURL, passphrase: keychainKey)
//
// 拓扑（8 段）：
//   段 1 · 首次启动 · StoreManager init 加密 · 6 .sqlite 文件就位
//   段 2 · M5 业务数据写入 · 6 store 联动各 1 笔
//   段 3 · 用户登出 · close()
//   段 4 · 重新登录 · 同密钥重开 · 6 store 数据全部读回
//   段 5 · 错误密钥拒绝 · M5 实盘前安全保证
//   段 6 · 6 个文件头 hexdump · 全部无 SQLite magic（加密保证）
//   段 7 · 配置内省 · rootDirectory / isEncrypted / allFileNames
//   段 8 · 总结
//
// 运行：swift run StoreManagerDemo
// 注意：纯本地 · 不依赖网络

import Foundation
import Shared
import DataCore
import JournalCore
import AlertCore
import StoreCore

@main
struct StoreManagerDemo {

    // MARK: - 常量

    private static let sqliteHeader = "SQLite format 3"
    private static let hexdumpBytes = 32
    private static let passphrase = "m5-launch-key"

    static func main() async throws {
        printSection("StoreManager M5 启动流程预演（第 17 个真数据 demo）")

        let rootDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("storemanager_demo_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        // ─────────────────────── 段 1 ───────────────────────
        printSection("段 1 · 首次启动 · StoreManager init（passphrase=\"\(passphrase)\"）")
        let m1 = try StoreManager(rootDirectory: rootDir, passphrase: passphrase)
        print("  ✅ rootDirectory：\(m1.rootDirectory.path)")
        print("  ✅ isEncrypted：\(m1.isEncrypted)")
        for name in StoreManager.allFileNames {
            let path = rootDir.appendingPathComponent(name).path
            let exists = FileManager.default.fileExists(atPath: path)
            print("    · \(name) · 创建：\(exists ? "✅" : "❌") · 大小：\(fileSize(path)) 字节")
        }

        // ─────────────────────── 段 2 ───────────────────────
        printSection("段 2 · M5 业务数据写入（6 store 联动 · 各 1 笔）")

        let nowMs: Int64 = 1_745_500_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000)
        let alertID = UUID()

        try await m1.analytics.append(AnalyticsEvent(
            id: 0, userID: "u-m5-001", deviceID: "mac-001", sessionID: "s-001",
            eventName: .appLaunch, eventTimestampMs: nowMs,
            properties: ["v": "1.0", "platform": "macOS"],
            appVersion: "1.0.0", uploaded: false
        ))
        print("  ✅ Analytics · appLaunch 事件写入")

        try await m1.kline.save(
            [KLine(instrumentID: "RB2510", period: .minute1, openTime: now,
                   open: 3193, high: 3198, low: 3190, close: 3195,
                   volume: 1280, openInterest: 0, turnover: 0)],
            instrumentID: "RB2510", period: .minute1
        )
        print("  ✅ KLine · RB2510 minute1 1 根 K 线写入")

        try await m1.journal.saveTrades([
            Trade(
                tradeReference: "M5-T-001", instrumentID: "RB2510",
                direction: .buy, offsetFlag: .open,
                price: Decimal(3193), volume: 2, commission: Decimal(4.5),
                timestamp: now, source: .manual
            )
        ])
        print("  ✅ Journal · RB2510 buy 1 笔 trade 写入")

        try await m1.alertHistory.append(AlertHistoryEntry(
            alertID: alertID, alertName: "RB2510 突破 3000", instrumentID: "RB2510",
            conditionSnapshot: .priceAbove(3000),
            triggeredAt: now, triggerPrice: 3193, message: "突破上行压力"
        ))
        print("  ✅ AlertHistory · priceAbove(3000) 触发记录写入")

        var wbook = WatchlistBook()
        let group = wbook.addGroup(name: "M5 demo")
        wbook.addInstrument("RB2510", to: group.id)
        wbook.addInstrument("IF2506", to: group.id)
        try await m1.watchlistBook.save(wbook)
        print("  ✅ WatchlistBook · 1 group + 2 合约（RB2510/IF2506）写入")

        var ws = WorkspaceBook()
        ws.addTemplate(name: "M5 默认布局", kind: .custom)
        try await m1.workspaceBook.save(ws)
        print("  ✅ WorkspaceBook · 1 template（M5 默认布局）写入")

        // ─────────────────────── 段 3 ───────────────────────
        printSection("段 3 · 用户登出 · close 全部 6 store")
        await m1.close()
        print("  ✅ 6 store close 完成")

        // ─────────────────────── 段 4 ───────────────────────
        printSection("段 4 · 重新登录 · 同密钥重开 · 6 store 数据全部读回")
        let m2 = try StoreManager(rootDirectory: rootDir, passphrase: passphrase)

        let analyticsCount = try await m2.analytics.count()
        let klineLoaded = try await m2.kline.load(instrumentID: "RB2510", period: .minute1)
        let trades = try await m2.journal.loadAllTrades()
        let alerts = try await m2.alertHistory.allHistory()
        let watchlistLoaded = try await m2.watchlistBook.load()
        let workspaceLoaded = try await m2.workspaceBook.load()

        let watchlistInstruments = watchlistLoaded?.groups.flatMap { $0.instrumentIDs } ?? []
        let templateCount = workspaceLoaded?.templates.count ?? 0

        let okAnalytics = analyticsCount == 1
        let okKline = klineLoaded.count == 1 && klineLoaded.first?.instrumentID == "RB2510"
        let okTrade = trades.count == 1 && trades.first?.tradeReference == "M5-T-001"
        let okAlert = alerts.count == 1 && alerts.first?.alertID == alertID
        let okWatchlist = watchlistInstruments.contains("RB2510") && watchlistInstruments.contains("IF2506")
        let okWorkspace = templateCount == 1

        print("  📊 持久化校验：")
        print("    · Analytics 事件数：\(analyticsCount) → \(okAnalytics ? "✅" : "❌") 期望 1")
        print("    · KLine 数：\(klineLoaded.count)（首根 \(klineLoaded.first?.instrumentID ?? "nil")）→ \(okKline ? "✅" : "❌")")
        print("    · Trade 数：\(trades.count)（首笔 ref=\(trades.first?.tradeReference ?? "nil")）→ \(okTrade ? "✅" : "❌")")
        print("    · Alert 历史：\(alerts.count) 条（alertID 匹配：\(alerts.first?.alertID == alertID)）→ \(okAlert ? "✅" : "❌")")
        print("    · Watchlist 含 RB2510+IF2506：\(watchlistInstruments) → \(okWatchlist ? "✅" : "❌")")
        print("    · Workspace template 数：\(templateCount) → \(okWorkspace ? "✅" : "❌") 期望 1")

        await m2.close()
        let allPersistOK = okAnalytics && okKline && okTrade && okAlert && okWatchlist && okWorkspace

        // ─────────────────────── 段 5 ───────────────────────
        printSection("段 5 · 错误密钥拒绝（M5 实盘前安全保证）")
        let didReject = (try? StoreManager(rootDirectory: rootDir, passphrase: "WRONG-KEY")) == nil
        print("  \(didReject ? "✅" : "❌") 错误密钥打开 → init 抛错拒绝：\(didReject)")

        // ─────────────────────── 段 6 ───────────────────────
        printSection("段 6 · 6 个文件头 hexdump · 全部应无 \"\(sqliteHeader)\" magic")
        var allEncrypted = true
        for name in StoreManager.allFileNames {
            let path = rootDir.appendingPathComponent(name).path
            let bytes = readFirstBytes(path, count: hexdumpBytes)
            let hasHeader = containsHeader(bytes)
            if hasHeader { allEncrypted = false }
            print("  📋 \(name)（前 \(hexdumpBytes) 字节）")
            print("    \(hexdump(bytes))")
            print("    \(hasHeader ? "❌ 含 SQLite magic" : "✅ 无 SQLite magic（已加密）")")
        }

        // ─────────────────────── 段 7 ───────────────────────
        printSection("段 7 · 配置内省（StoreManager 公开属性）")
        let m3 = try StoreManager(rootDirectory: rootDir, passphrase: passphrase)
        print("  · rootDirectory：\(m3.rootDirectory.path)")
        print("  · isEncrypted：\(m3.isEncrypted)")
        print("  · allFileNames（\(StoreManager.allFileNames.count) 个）：")
        for name in StoreManager.allFileNames {
            print("      · \(name)")
        }
        await m3.close()

        // ─────────────────────── 段 8 ───────────────────────
        let allOK = allPersistOK && didReject && allEncrypted
        printSection(allOK
            ? "🎉 第 17 个真数据 demo 通过（M5 启动流程端到端 · 6 store 持久化 + 加密 + 错密钥拒绝）"
            : "⚠️  StoreManagerDemo 验收未达标（详见上方）"
        )
    }

    // MARK: - hexdump / 文件 helpers

    static func fileSize(_ path: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
    }

    static func readFirstBytes(_ path: String, count: Int) -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    static func hexdump(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    static func containsHeader(_ data: Data) -> Bool {
        String(data: data, encoding: .ascii)?.contains(sqliteHeader) == true
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}
