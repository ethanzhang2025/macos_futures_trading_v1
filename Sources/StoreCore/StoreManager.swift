// WP-19a-7 · 7 store 统一管理器（WP-19a-8 加 alertConfig）
// 集中：路径模板 + passphrase 注入 + 生命周期
//
// 设计取舍：
// - struct + 各 store 自隔离 actor（不嵌套 actor · StoreManager 仅做容器）
// - 文件名固化为 public static 常量（迁移 / 测试 / 备份脚本可引用 · 避免漂移）
// - passphrase nil/空 → 7 store 全走明文路径（同 SQLiteConnection 行为）
// - close() 串行 await（顺序无关 · 多 store 关闭性能不敏感 · 简单优先）
// - init 失败时已构造的 store SQLite handle 泄漏到进程退出（Swift 6 actor deinit
//   不能调用 actor-isolated 方法 · UI 启动失败 → 进程退出 → OS 回收 · 可接受）
//
// 依赖 DAG：StoreCore → Shared + DataCore + JournalCore + AlertCore
// M5 Mac App 启动一次性 init 后注入到各功能模块

import Foundation
import Shared
import DataCore
import JournalCore
import AlertCore

public struct StoreManager: Sendable {

    // MARK: - 7 store 引用

    public let analytics: SQLiteAnalyticsEventStore
    public let kline: SQLiteKLineCacheStore
    public let journal: SQLiteJournalStore
    public let alertHistory: SQLiteAlertHistoryStore
    public let alertConfig: SQLiteAlertConfigStore
    public let watchlistBook: SQLiteWatchlistBookStore
    public let workspaceBook: SQLiteWorkspaceBookStore

    // MARK: - 配置内省

    public let rootDirectory: URL
    public let isEncrypted: Bool

    // MARK: - 文件名约定（公开常量）

    public static let analyticsFileName = "analytics.sqlite"
    public static let klineFileName = "kline_cache.sqlite"
    public static let journalFileName = "journal.sqlite"
    public static let alertHistoryFileName = "alert_history.sqlite"
    public static let alertConfigFileName = "alert_config.sqlite"
    public static let watchlistFileName = "watchlist.sqlite"
    public static let workspaceFileName = "workspace.sqlite"

    /// 全部 7 个数据库文件名（迁移 / 备份 / 测试可引用）
    public static let allFileNames: [String] = [
        analyticsFileName,
        klineFileName,
        journalFileName,
        alertHistoryFileName,
        alertConfigFileName,
        watchlistFileName,
        workspaceFileName
    ]

    // MARK: - 初始化

    /// 打开 7 store · 自动创建 rootDirectory
    /// - Parameters:
    ///   - rootDirectory: 数据库根目录
    ///   - passphrase: SQLCipher 密钥；nil 或空字符串 = 不加密（行为同原生 SQLite）
    public init(rootDirectory: URL, passphrase: String? = nil) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        self.rootDirectory = rootDirectory
        self.isEncrypted = passphrase?.isEmpty == false

        func dbPath(_ name: String) -> String {
            rootDirectory.appendingPathComponent(name).path
        }

        self.analytics = try SQLiteAnalyticsEventStore(
            path: dbPath(Self.analyticsFileName),
            passphrase: passphrase
        )
        self.kline = try SQLiteKLineCacheStore(
            path: dbPath(Self.klineFileName),
            passphrase: passphrase
        )
        self.journal = try SQLiteJournalStore(
            path: dbPath(Self.journalFileName),
            passphrase: passphrase
        )
        self.alertHistory = try SQLiteAlertHistoryStore(
            path: dbPath(Self.alertHistoryFileName),
            passphrase: passphrase
        )
        self.alertConfig = try SQLiteAlertConfigStore(
            path: dbPath(Self.alertConfigFileName),
            passphrase: passphrase
        )
        self.watchlistBook = try SQLiteWatchlistBookStore(
            path: dbPath(Self.watchlistFileName),
            passphrase: passphrase
        )
        self.workspaceBook = try SQLiteWorkspaceBookStore(
            path: dbPath(Self.workspaceFileName),
            passphrase: passphrase
        )
    }

    // MARK: - 生命周期

    /// 关闭全部 7 store · 进程退出 / 用户登出 / 切换数据库时调用
    public func close() async {
        await analytics.close()
        await kline.close()
        await journal.close()
        await alertHistory.close()
        await alertConfig.close()
        await watchlistBook.close()
        await workspaceBook.close()
    }
}
