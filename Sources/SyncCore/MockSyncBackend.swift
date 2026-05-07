// MockSyncBackend · 内存版 backend（WP-60）
//
// 用途：
//   - SyncEngine 单测
//   - SyncEngineDemo Tools CLI（batch009）
//   - 多设备并发场景模拟（同 backend 多个 SyncEngine 实例）
//
// 行为：
//   - upsert：按 (recordType, id) 主键 · push 时直接覆盖（backend 不做 LWW · 那是 engine 的活）
//   - fetch since：返回 lastModified > since 的记录（含 tombstone）
//   - delete：等价 push 一批 tombstone
//   - failureMode：测试用 · 让 fetch/push 抛错以验证 engine 容错

import Foundation

public actor MockSyncBackend: SyncBackend {

    public enum FailureMode: Sendable {
        case none
        case fetchFails(SyncBackendError)
        case pushFails(SyncBackendError)
    }

    private var storage: [String: [UUID: SyncRecord]] = [:]
    private var failure: FailureMode = .none

    public init() {}

    // MARK: - SyncBackend

    public func fetch(recordType: String, since: Date?) async throws -> [SyncRecord] {
        if case .fetchFails(let err) = failure { throw err }
        let bucket = storage[recordType] ?? [:]
        let all = Array(bucket.values)
        guard let since else { return all }
        return all.filter { $0.lastModified > since }
    }

    public func push(_ records: [SyncRecord]) async throws {
        if case .pushFails(let err) = failure { throw err }
        for record in records {
            var bucket = storage[record.recordType] ?? [:]
            bucket[record.id] = record
            storage[record.recordType] = bucket
        }
    }

    public func delete(recordType: String, ids: [UUID], deletedAt: Date) async throws {
        if case .pushFails(let err) = failure { throw err }
        var bucket = storage[recordType] ?? [:]
        for id in ids {
            if let existing = bucket[id] {
                bucket[id] = SyncRecord(
                    recordType: existing.recordType,
                    id: existing.id,
                    lastModified: deletedAt,
                    version: existing.version + 1,
                    deletedAt: deletedAt,
                    payload: existing.payload
                )
            } else {
                // tombstone-only · 用空 payload 占位
                bucket[id] = SyncRecord(
                    recordType: recordType,
                    id: id,
                    lastModified: deletedAt,
                    version: 1,
                    deletedAt: deletedAt,
                    payload: Data()
                )
            }
        }
        storage[recordType] = bucket
    }

    // MARK: - 测试钩子

    /// 直接读 backend 当前存储（绕过 fetch · 用于断言）
    public func snapshot(recordType: String) -> [SyncRecord] {
        Array(storage[recordType]?.values ?? [:].values)
    }

    public func snapshotAll() -> [String: [SyncRecord]] {
        storage.mapValues { Array($0.values) }
    }

    public func setFailure(_ mode: FailureMode) {
        failure = mode
    }

    public func reset() {
        storage.removeAll()
        failure = .none
    }
}
