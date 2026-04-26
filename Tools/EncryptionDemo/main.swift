// SQLCipher 加密层端到端真数据 demo（第 15 个真数据 demo）
//
// 用途：
// - 验证 WP-19b v2：6 个 SQLite store 全部支持 init(path:passphrase:) 加密直通
// - 演示加密前后文件字节差异（明文可见 vs 密文乱码 · 给销售/合规直观证据）
// - 演示错误密钥拒绝（M5 实盘前安全保证）
// - UI 启动时各 store 创建路径完全统一：传 path + passphrase 即可
//
// 拓扑（5 段）：
//   段 1 · 加密 SQLiteJournalStore 写 1 笔 trade
//   段 2 · 明文 SQLiteJournalStore 写同样 1 笔 trade
//   段 3 · hexdump 前 64 字节对比（明文可见 SQLite 头 + 字符串 / 密文应全乱）
//   段 4 · 错误密钥拒绝验证（加密文件用错密钥重开）
//   段 5 · 6 store 加密 init 全部跑通（统一调用模式）
//
// 运行：swift run EncryptionDemo
// 注意：纯本地 SQLite，不依赖 Sina 网络

import Foundation
import Shared
import DataCore
import JournalCore
import AlertCore

@main
struct EncryptionDemo {

    // MARK: - 常量

    private static let sqliteHeader = "SQLite format 3"
    private static let hexdumpBytes = 64
    private static let storeExts = ["analytics", "kline", "journal", "alert", "watchlist", "workspace"]

    static func main() async throws {
        printSection("SQLCipher 加密层端到端真数据 demo（第 15 个真数据 demo）")

        let encryptedPath = NSTemporaryDirectory().appending("enc_journal_\(UUID().uuidString).sqlite")
        let plaintextPath = NSTemporaryDirectory().appending("plain_journal_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(atPath: encryptedPath)
            try? FileManager.default.removeItem(atPath: plaintextPath)
        }

        let sampleTrade = Trade(
            tradeReference: "ENC-DEMO-001",
            instrumentID: "RB2510",
            direction: .buy,
            offsetFlag: .open,
            price: Decimal(3193),
            volume: 2,
            commission: Decimal(4.5),
            timestamp: Date(timeIntervalSince1970: 1_745_500_000),
            source: .manual
        )

        // 段 1：加密 store 写入
        printSection("段 1 · 加密 SQLiteJournalStore 写入（passphrase=\"secret-001\"）")
        let encStore = try SQLiteJournalStore(path: encryptedPath, passphrase: "secret-001")
        try await encStore.saveTrades([sampleTrade])
        await encStore.close()
        let encSize = fileSize(encryptedPath)
        print("  ✅ 加密文件写入完成 · 大小 \(encSize) 字节")

        // 段 2：明文 store 写入
        printSection("段 2 · 明文 SQLiteJournalStore 写入（passphrase=nil · 向后兼容）")
        let plainStore = try SQLiteJournalStore(path: plaintextPath, passphrase: nil)
        try await plainStore.saveTrades([sampleTrade])
        await plainStore.close()
        let plainSize = fileSize(plaintextPath)
        print("  ✅ 明文文件写入完成 · 大小 \(plainSize) 字节")
        print("  💡 文件大小差：\(encSize - plainSize) 字节（加密 reserved bytes / page header）")

        // 段 3：hexdump 字节对比
        printSection("段 3 · hexdump 前 \(hexdumpBytes) 字节对比（明文应见 SQLite 头 + 字符串 / 密文乱码）")
        let plainBytes = readFirstBytes(plaintextPath, count: hexdumpBytes)
        let encBytes = readFirstBytes(encryptedPath, count: hexdumpBytes)
        printBytesBlock(label: "明文文件", bytes: plainBytes)
        printBytesBlock(label: "加密文件", bytes: encBytes)

        // 关键验证：明文应有 "SQLite format 3" 字符串；加密应没有
        let plainHasHeader = containsHeader(plainBytes)
        let encHasHeader = containsHeader(encBytes)
        print("  \(plainHasHeader ? "✅" : "❌") 明文文件包含 \"\(sqliteHeader)\" 字符串：\(plainHasHeader)")
        print("  \(!encHasHeader ? "✅" : "❌") 加密文件不含 \"\(sqliteHeader)\"（已加密）：\(!encHasHeader)")

        // 段 4：错误密钥拒绝
        printSection("段 4 · 错误密钥拒绝（M5 实盘前安全保证）")
        let didReject = (try? SQLiteJournalStore(path: encryptedPath, passphrase: "wrong-key")) == nil
        print("  \(didReject ? "✅" : "❌") 错误密钥打开加密文件 → 抛错拒绝：\(didReject)")

        // 段 5：6 store 加密 init 全部跑通
        printSection("段 5 · 6 store 加密 init 全部跑通（统一调用模式）")
        let key = "uniform-pass"
        let storeResults = try await runAllSixStores(passphrase: key)
        print("  ✅ 6 store 加密 init 全部成功：")
        for r in storeResults {
            print("    · \(r.name) · 加密文件 \(r.size) 字节")
        }

        // 总结
        let allOK = plainHasHeader && !encHasHeader && didReject && storeResults.count == 6
        printSection(allOK
            ? "🎉 第 15 个真数据 demo 通过（加密字节差异 + 错误密钥拒绝 + 6 store 统一调用）"
            : "⚠️  加密验收未达标（详见上方）")
    }

    // MARK: - 6 store 加密 init 串测

    struct StoreResult {
        let name: String
        let size: Int
    }

    static func runAllSixStores(passphrase: String) async throws -> [StoreResult] {
        var results: [StoreResult] = []
        let basePath = NSTemporaryDirectory().appending("enc_all_\(UUID().uuidString)")
        func pathFor(_ ext: String) -> String { "\(basePath)_\(ext).sqlite" }
        defer {
            for ext in storeExts {
                try? FileManager.default.removeItem(atPath: pathFor(ext))
            }
        }

        // 1. SQLiteAnalyticsEventStore
        let analyticsPath = pathFor("analytics")
        let analytics = try SQLiteAnalyticsEventStore(path: analyticsPath, passphrase: passphrase)
        let event = AnalyticsEvent(
            id: 0, userID: "u1", deviceID: "d1", sessionID: "s1",
            eventName: .appLaunch, eventTimestampMs: 1_745_500_000_000,
            properties: [:], appVersion: "0.1.0", uploaded: false
        )
        try await analytics.append(event)
        await analytics.close()
        results.append(.init(name: "SQLiteAnalyticsEventStore", size: fileSize(analyticsPath)))

        // 2. SQLiteKLineCacheStore
        let klinePath = pathFor("kline")
        let kline = try SQLiteKLineCacheStore(path: klinePath, passphrase: passphrase)
        try await kline.save(
            [KLine(instrumentID: "RB", period: .minute1, openTime: Date(),
                   open: 3000, high: 3010, low: 2990, close: 3005,
                   volume: 100, openInterest: 0, turnover: 0)],
            instrumentID: "RB", period: .minute1
        )
        await kline.close()
        results.append(.init(name: "SQLiteKLineCacheStore   ", size: fileSize(klinePath)))

        // 3. SQLiteJournalStore
        let journalPath = pathFor("journal")
        let journal = try SQLiteJournalStore(path: journalPath, passphrase: passphrase)
        try await journal.saveTrades([
            Trade(tradeReference: "T1", instrumentID: "RB", direction: .buy, offsetFlag: .open,
                  price: 3000, volume: 1, commission: 2, timestamp: Date(), source: .manual)
        ])
        await journal.close()
        results.append(.init(name: "SQLiteJournalStore      ", size: fileSize(journalPath)))

        // 4. SQLiteAlertHistoryStore
        let alertPath = pathFor("alert")
        let alert = try SQLiteAlertHistoryStore(path: alertPath, passphrase: passphrase)
        try await alert.append(AlertHistoryEntry(
            alertID: UUID(), alertName: "test", instrumentID: "RB",
            conditionSnapshot: .priceAbove(3000),
            triggeredAt: Date(), triggerPrice: 3010, message: ""
        ))
        await alert.close()
        results.append(.init(name: "SQLiteAlertHistoryStore ", size: fileSize(alertPath)))

        // 5. SQLiteWatchlistBookStore
        let watchlistPath = pathFor("watchlist")
        let watchlist = try SQLiteWatchlistBookStore(path: watchlistPath, passphrase: passphrase)
        var book = WatchlistBook()
        let g = book.addGroup(name: "demo")
        book.addInstrument("RB", to: g.id)
        try await watchlist.save(book)
        await watchlist.close()
        results.append(.init(name: "SQLiteWatchlistBookStore", size: fileSize(watchlistPath)))

        // 6. SQLiteWorkspaceBookStore
        let workspacePath = pathFor("workspace")
        let workspace = try SQLiteWorkspaceBookStore(path: workspacePath, passphrase: passphrase)
        var wb = WorkspaceBook()
        wb.addTemplate(name: "demo", kind: .custom)
        try await workspace.save(wb)
        await workspace.close()
        results.append(.init(name: "SQLiteWorkspaceBookStore", size: fileSize(workspacePath)))

        return results
    }

    // MARK: - 文件 / hexdump helpers

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

    static func asciiPreview(_ data: Data) -> String {
        data.map { (0x20...0x7e).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
    }

    /// 段 3 用：打印「label（前 N 字节）：hex + ASCII」两行
    static func printBytesBlock(label: String, bytes: Data) {
        print("  📋 \(label)（前 \(hexdumpBytes) 字节）：")
        print("    \(hexdump(bytes))")
        print("    ASCII：\(asciiPreview(bytes))")
    }

    /// 段 3 用：检查字节流 ASCII 解码后是否含 SQLite header
    static func containsHeader(_ data: Data) -> Bool {
        String(data: data, encoding: .ascii)?.contains(sqliteHeader) == true
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}
