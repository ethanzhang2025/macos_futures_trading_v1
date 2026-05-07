// SyncConflict · 冲突日志记录（WP-60）
//
// 用途：
//   - 用户排查"为什么我的修改没生效"
//   - 后期 UI 可展示"最近 N 条冲突"
//   - 支持回滚（保留败方 payload · 由调用方决定是否落盘 · 默认不持久化 payload）

import Foundation

public struct SyncConflict: Sendable, Codable, Equatable, Hashable {
    public let recordType: String
    public let recordID: UUID
    public let localVersion: Int
    public let remoteVersion: Int
    public let localModified: Date
    public let remoteModified: Date
    public let resolution: SyncResolution
    public let resolvedAt: Date

    public init(
        recordType: String,
        recordID: UUID,
        localVersion: Int,
        remoteVersion: Int,
        localModified: Date,
        remoteModified: Date,
        resolution: SyncResolution,
        resolvedAt: Date
    ) {
        self.recordType = recordType
        self.recordID = recordID
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.localModified = localModified
        self.remoteModified = remoteModified
        self.resolution = resolution
        self.resolvedAt = resolvedAt
    }
}

/// 内存版冲突日志 · 默认实现（actor 线程安全）
/// SQLite 持久化版本由 batch002 / 后续接入 StoreCore 时实现
public actor InMemoryConflictLog {
    private var entries: [SyncConflict] = []
    private let cap: Int

    public init(cap: Int = 1000) {
        self.cap = cap
    }

    public func record(_ conflict: SyncConflict) {
        entries.append(conflict)
        if entries.count > cap {
            entries.removeFirst(entries.count - cap)
        }
    }

    public func recordAll(_ conflicts: [SyncConflict]) {
        for c in conflicts { record(c) }
    }

    public func all() -> [SyncConflict] { entries }

    public func count() -> Int { entries.count }

    public func clear() { entries.removeAll() }
}
