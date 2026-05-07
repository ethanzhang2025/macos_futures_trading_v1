// SyncEngine 主循环测试 · WP-60 batch001
// 覆盖：pull-merge-push / 增量基线 / 本地独有 push / 远端独有 pull / 冲突收集

import Testing
import Foundation
@testable import SyncCore

@Suite("SyncEngine · 主同步循环")
struct SyncEngineTests {

    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    private let recordType = "watchlist"

    private func record(id: UUID = UUID(),
                        modifiedOffset: TimeInterval = 0,
                        version: Int = 1,
                        deletedOffset: TimeInterval? = nil,
                        payload: String = "p") -> SyncRecord {
        SyncRecord(
            recordType: recordType,
            id: id,
            lastModified: baseTime.addingTimeInterval(modifiedOffset),
            version: version,
            deletedAt: deletedOffset.map { baseTime.addingTimeInterval($0) },
            payload: Data(payload.utf8)
        )
    }

    @Test("空本地 · 远端 2 条 → 全部拉下来")
    func pullOnly() async throws {
        let backend = MockSyncBackend()
        let r1 = record(modifiedOffset: 0)
        let r2 = record(modifiedOffset: 5)
        try await backend.push([r1, r2])

        let engine = SyncEngine(backend: backend)
        let result = try await engine.sync(localRecords: [], recordType: recordType)

        #expect(result.pulledCount == 2)
        #expect(result.pushedCount == 0)
        #expect(result.merged.count == 2)
        #expect(result.conflicts.isEmpty)
    }

    @Test("本地 2 条 · 远端空 → 全部 push")
    func pushOnly() async throws {
        let backend = MockSyncBackend()
        let local = [record(modifiedOffset: 0), record(modifiedOffset: 5)]

        let engine = SyncEngine(backend: backend)
        let result = try await engine.sync(localRecords: local, recordType: recordType)

        #expect(result.pulledCount == 0)
        #expect(result.pushedCount == 2)
        #expect(result.merged.count == 2)

        let stored = await backend.snapshot(recordType: recordType)
        #expect(stored.count == 2)
    }

    @Test("local 时间晚 · 含被改过 version > 0 的 remote → 冲突 · local 胜 · push")
    func conflictLocalWins() async throws {
        let id = UUID()
        let backend = MockSyncBackend()
        let remote = record(id: id, modifiedOffset: 5, version: 2, payload: "R")
        try await backend.push([remote])

        let local = record(id: id, modifiedOffset: 10, version: 3, payload: "L")
        let engine = SyncEngine(backend: backend)
        let result = try await engine.sync(localRecords: [local], recordType: recordType)

        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.resolution == .local)
        #expect(result.pushedCount == 1)
        #expect(result.merged.first?.payload == Data("L".utf8))

        let stored = await backend.snapshot(recordType: recordType)
        #expect(stored.first?.payload == Data("L".utf8))
    }

    @Test("remote 时间晚 · 双方都改过 → 冲突 · remote 胜 · 不 push")
    func conflictRemoteWins() async throws {
        let id = UUID()
        let backend = MockSyncBackend()
        let remote = record(id: id, modifiedOffset: 10, version: 3, payload: "R")
        try await backend.push([remote])

        let local = record(id: id, modifiedOffset: 5, version: 2, payload: "L")
        let engine = SyncEngine(backend: backend)
        let result = try await engine.sync(localRecords: [local], recordType: recordType)

        #expect(result.conflicts.count == 1)
        #expect(result.conflicts.first?.resolution == .remote)
        #expect(result.pushedCount == 0)
        #expect(result.merged.first?.payload == Data("R".utf8))
    }

    @Test("增量基线 · 第二次 sync 仅拉新")
    func baselineIncremental() async throws {
        let backend = MockSyncBackend()
        let firstSyncTime = baseTime.addingTimeInterval(20)
        let engine = SyncEngine(backend: backend, now: { firstSyncTime })

        try await backend.push([record(modifiedOffset: 5)])
        _ = try await engine.sync(localRecords: [], recordType: recordType)
        let firstBaseline = await engine.lastSync(for: recordType)
        #expect(firstBaseline == firstSyncTime)

        // 第二次：再 push 一条更新过的
        try await backend.push([record(modifiedOffset: 30)])
        let result = try await engine.sync(localRecords: [], recordType: recordType)
        // 仅拉到第二条（first 的 lastModified = 5 < firstSyncTime = 20）
        #expect(result.pulledCount == 1)
    }

    @Test("tombstone 远端 → 本地标记删除")
    func remoteTombstoneSyncs() async throws {
        let id = UUID()
        let backend = MockSyncBackend()
        try await backend.push([record(id: id, modifiedOffset: 5, version: 1)])
        try await backend.delete(recordType: recordType, ids: [id], deletedAt: baseTime.addingTimeInterval(10))

        let engine = SyncEngine(backend: backend)
        let result = try await engine.sync(localRecords: [], recordType: recordType)

        #expect(result.merged.count == 1)
        #expect(result.merged.first?.isDeleted == true)
    }

    @Test("backend 抛 fetchFails · sync 也抛")
    func backendFetchFails() async throws {
        let backend = MockSyncBackend()
        await backend.setFailure(.fetchFails(.networkUnavailable))
        let engine = SyncEngine(backend: backend)

        await #expect(throws: SyncBackendError.self) {
            try await engine.sync(localRecords: [], recordType: self.recordType)
        }
    }

    @Test("resetBaseline · 强制全量拉")
    func resetBaselineForcesFull() async throws {
        let backend = MockSyncBackend()
        try await backend.push([record(modifiedOffset: 5)])
        let engine = SyncEngine(backend: backend)
        _ = try await engine.sync(localRecords: [], recordType: recordType)

        await engine.resetBaseline(for: recordType)
        let result = try await engine.sync(localRecords: [], recordType: recordType)
        #expect(result.pulledCount == 1)  // baseline 重置后又拉到了
    }
}
