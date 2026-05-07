// SyncBackend · 后端通信抽象（WP-60）
//
// 实现者：
//   - MockSyncBackend（内存版 · 测试 + Tools demo）
//   - CloudKitSyncBackend（macOS-only · #if canImport · batch008）
//   - AliyunSyncBackend（Stage B · 敏感数据走自建）
//
// 协议契约：
//   - fetch: 拉取 since 时间戳之后改动的记录（包含 tombstone）· nil 表示全量
//   - push: 推送本地记录（包含 tombstone）
//   - delete: 显式发送 tombstone（push 也支持 tombstone · delete 是便捷方法）
//
// 错误处理：
//   - 网络/认证错误抛 SyncBackendError
//   - SyncEngine 捕获并按策略重试 / 回退

import Foundation

public protocol SyncBackend: Sendable {
    /// 拉取指定类型 since 时间之后改动的记录
    /// - Parameters:
    ///   - recordType: 记录类型（"watchlist" 等）
    ///   - since: 增量基线 · nil 全量拉
    /// - Returns: 含 tombstone（deletedAt != nil）的全部记录
    func fetch(recordType: String, since: Date?) async throws -> [SyncRecord]

    /// 推送记录（含 tombstone）· backend 按 id upsert
    func push(_ records: [SyncRecord]) async throws

    /// 便捷 tombstone 推送（等价 push 一批 deletedAt 非 nil 的记录）
    func delete(recordType: String, ids: [UUID], deletedAt: Date) async throws
}

public enum SyncBackendError: Error, Sendable, Equatable {
    case networkUnavailable
    case authenticationRequired
    case quotaExceeded
    case rateLimited
    case recordNotFound(UUID)
    case schemaMismatch(String)
    case unknown(String)
}
