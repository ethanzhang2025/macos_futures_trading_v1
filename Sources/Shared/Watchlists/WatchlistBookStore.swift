// WP-19a-5 · WatchlistBook 持久化协议
// 设计取舍：
// - 整本 WatchlistBook 作为持久化单位（聚合根）；UI 启动时一次性 load，写入时整体覆盖
// - 单 Book 单例存储足够（Stage A 单用户）；多用户 / 多 Book 留 Stage B
// - 协议先 + 多实现并存（InMemory + SQLite）；SQLCipher 加密留 WP-19b 接同协议

import Foundation

/// WatchlistBook 持久化错误
public enum WatchlistBookStoreError: Error, Sendable, Equatable {
    case decodeFailed
    case encodeFailed
    case ioFailed(String)
}

/// WatchlistBook 持久化协议
public protocol WatchlistBookStore: Sendable {
    /// 加载已存的 Book（不存在返回 nil · UI 层可决定是否回退到默认空簿）
    func load() async throws -> WatchlistBook?

    /// 整体保存（覆盖现有）
    func save(_ book: WatchlistBook) async throws

    /// 清空持久化数据
    func clear() async throws
}

/// 内存实现 · 测试 / 默认占位
public actor InMemoryWatchlistBookStore: WatchlistBookStore {
    private var stored: WatchlistBook?

    public init(initial: WatchlistBook? = nil) {
        self.stored = initial
    }

    public func load() async throws -> WatchlistBook? { stored }

    public func save(_ book: WatchlistBook) async throws { stored = book }

    public func clear() async throws { stored = nil }
}
