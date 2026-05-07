// SyncEngine · 同步主循环（WP-60）
//
// 算法（pull-merge-push）：
//   1. fetch backend records since lastSyncDate[recordType]
//   2. 对每条 remote · 找本地同 id 记录
//      - 找不到 → 直接采纳 remote（merged）
//      - 找到 → SyncResolver.merge → winner + 可能 conflict
//   3. 收集需要 push 的本地新记录（remote 没有 / local 是 winner 但 remote 不同）
//   4. push 这批本地新记录
//   5. 更新 lastSyncDate[recordType] 为本次同步时刻
//   6. 返回 SyncResult（merged 列表 · 冲突 · 进出统计）
//
// 调用方契约：
//   - localRecords 是当前本地全量（按 recordType）· 调用方负责加载
//   - merged 列表是合并后该 recordType 的全量 · 调用方按此覆盖本地
//   - conflicts 由调用方写入持久化（如 InMemoryConflictLog 或 SQLite）

import Foundation

public struct SyncResult: Sendable {
    /// 合并后该 recordType 的全量记录（含 tombstone）
    public let merged: [SyncRecord]
    /// 本次同步发现的冲突
    public let conflicts: [SyncConflict]
    /// 本次推送的记录数
    public let pushedCount: Int
    /// 本次拉取的记录数
    public let pulledCount: Int
    /// 同步时刻（调用方应记录为 lastSyncDate[recordType]）
    public let syncedAt: Date

    public init(
        merged: [SyncRecord],
        conflicts: [SyncConflict],
        pushedCount: Int,
        pulledCount: Int,
        syncedAt: Date
    ) {
        self.merged = merged
        self.conflicts = conflicts
        self.pushedCount = pushedCount
        self.pulledCount = pulledCount
        self.syncedAt = syncedAt
    }
}

public actor SyncEngine {
    private let backend: SyncBackend
    /// 每个 recordType 的最近同步时间（用于增量拉取）
    private var lastSyncDate: [String: Date] = [:]
    /// 注入的"现在时刻"（测试用 · 默认 Date()）
    private let now: @Sendable () -> Date

    public init(backend: SyncBackend, now: @Sendable @escaping () -> Date = { Date() }) {
        self.backend = backend
        self.now = now
    }

    public func lastSync(for recordType: String) -> Date? {
        lastSyncDate[recordType]
    }

    /// 主同步入口
    /// - Parameters:
    ///   - localRecords: 当前本地全量该 recordType 记录（含 tombstone）
    ///   - recordType: 记录类型
    /// - Returns: SyncResult（merged 全量 / 冲突 / 统计）
    public func sync(
        localRecords: [SyncRecord],
        recordType: String
    ) async throws -> SyncResult {
        precondition(localRecords.allSatisfy { $0.recordType == recordType }, "localRecords 必须同 recordType")

        let baseline = lastSyncDate[recordType]
        let remoteRecords = try await backend.fetch(recordType: recordType, since: baseline)

        var localByID: [UUID: SyncRecord] = Dictionary(uniqueKeysWithValues: localRecords.map { ($0.id, $0) })
        var conflicts: [SyncConflict] = []
        var toPush: [SyncRecord] = []

        // 阶段 1：合并 remote · 收集 conflicts · 决定哪些需要 push（local 胜的）
        for remote in remoteRecords {
            if let local = localByID[remote.id] {
                let outcome = SyncResolver.merge(local: local, remote: remote)
                if let conflict = outcome.conflict { conflicts.append(conflict) }
                localByID[remote.id] = outcome.winner
                if outcome.resolution == .local && local != remote {
                    toPush.append(outcome.winner)
                }
            } else {
                localByID[remote.id] = remote
            }
        }

        // 阶段 2：本地独有（remote 没有的）也要 push
        let remoteIDs = Set(remoteRecords.map(\.id))
        for local in localRecords where !remoteIDs.contains(local.id) {
            toPush.append(local)
        }

        // 阶段 3：执行 push
        if !toPush.isEmpty {
            try await backend.push(toPush)
        }

        let syncTime = now()
        lastSyncDate[recordType] = syncTime

        return SyncResult(
            merged: Array(localByID.values),
            conflicts: conflicts,
            pushedCount: toPush.count,
            pulledCount: remoteRecords.count,
            syncedAt: syncTime
        )
    }

    /// 测试 / 重置场景用 · 清除增量基线
    public func resetBaseline(for recordType: String) {
        lastSyncDate.removeValue(forKey: recordType)
    }

    public func resetAllBaselines() {
        lastSyncDate.removeAll()
    }
}
