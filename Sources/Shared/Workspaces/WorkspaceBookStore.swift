// WP-19a-6 · WorkspaceBook 持久化协议
// 设计取舍（同 WP-19a-5 WatchlistBook）：
// - 整本 WorkspaceBook 作为持久化单位（聚合根 · 含 templates + activeTemplateID）
// - templates 内的 windows / shortcut 一并随 Codable JSON 序列化（WorkspaceBook 全 Codable 链路）
// - 单 Book 单例存储；SQLCipher 加密留 WP-19b 接同协议

import Foundation

/// WorkspaceBook 持久化错误
public enum WorkspaceBookStoreError: Error, Sendable, Equatable {
    case decodeFailed
    case encodeFailed
    case ioFailed(String)
}

/// WorkspaceBook 持久化协议
public protocol WorkspaceBookStore: Sendable {
    /// 加载已存的 Book（不存在返回 nil · UI 层可决定是否回退到默认）
    func load() async throws -> WorkspaceBook?

    /// 整体保存（覆盖现有）
    func save(_ book: WorkspaceBook) async throws

    /// 清空持久化数据
    func clear() async throws
}

/// 内存实现 · 测试 / 默认占位
public actor InMemoryWorkspaceBookStore: WorkspaceBookStore {
    private var stored: WorkspaceBook?

    public init(initial: WorkspaceBook? = nil) {
        self.stored = initial
    }

    public func load() async throws -> WorkspaceBook? { stored }

    public func save(_ book: WorkspaceBook) async throws { stored = book }

    public func clear() async throws { stored = nil }
}
