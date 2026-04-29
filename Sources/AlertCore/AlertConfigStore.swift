// WP-19a-8 · AlertConfig 持久化协议
// 设计取舍：
// - 整组 [Alert] 作为持久化单位（聚合根）；UI 启动时一次性 load，写入时整体覆盖
// - alerts 体量小（< 200 bytes / 条 · v1 用户级别预警量级 < 100 条）· 全量 save 性能可接受
// - 与 WatchlistBookStore 同款模式 · UI 集成最简单（onChange(of: alerts) 触发整批 save）
// - InMemory + SQLite 多实现并存

import Foundation

/// AlertConfig 持久化错误
public enum AlertConfigStoreError: Error, Sendable, Equatable {
    case decodeFailed
    case encodeFailed
    case ioFailed(String)
}

/// AlertConfig 持久化协议
public protocol AlertConfigStore: Sendable {
    /// 加载已存的 alerts（不存在返回 nil · UI 层可决定是否回退 Mock）
    func load() async throws -> [Alert]?

    /// 整体保存（覆盖现有）
    func save(_ alerts: [Alert]) async throws

    /// 清空持久化数据
    func clear() async throws
}

/// 内存实现 · 测试 / 默认占位
public actor InMemoryAlertConfigStore: AlertConfigStore {
    private var stored: [Alert]?

    public init(initial: [Alert]? = nil) {
        self.stored = initial
    }

    public func load() async throws -> [Alert]? { stored }

    public func save(_ alerts: [Alert]) async throws { stored = alerts }

    public func clear() async throws { stored = nil }
}
