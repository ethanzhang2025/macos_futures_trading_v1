// MockSyncBackend 行为测试 · WP-60 batch001
// 覆盖：push/fetch upsert / since 增量 / delete tombstone / failure mode

import Testing
import Foundation
@testable import SyncCore

@Suite("MockSyncBackend")
struct MockSyncBackendTests {

    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    private let recordType = "watchlist"

    private func record(id: UUID = UUID(),
                        modifiedOffset: TimeInterval = 0,
                        version: Int = 1,
                        payload: String = "p") -> SyncRecord {
        SyncRecord(
            recordType: recordType,
            id: id,
            lastModified: baseTime.addingTimeInterval(modifiedOffset),
            version: version,
            payload: Data(payload.utf8)
        )
    }

    @Test("push 后 fetch 取得全量")
    func pushAndFetchAll() async throws {
        let backend = MockSyncBackend()
        let r1 = record(modifiedOffset: 0)
        let r2 = record(modifiedOffset: 5)
        try await backend.push([r1, r2])

        let all = try await backend.fetch(recordType: recordType, since: nil)
        #expect(all.count == 2)
        #expect(Set(all.map(\.id)) == Set([r1.id, r2.id]))
    }

    @Test("fetch since · 仅返回更新")
    func fetchSinceFiltersOlder() async throws {
        let backend = MockSyncBackend()
        let old = record(modifiedOffset: 0)
        let new = record(modifiedOffset: 10)
        try await backend.push([old, new])

        let cutoff = baseTime.addingTimeInterval(5)
        let recent = try await backend.fetch(recordType: recordType, since: cutoff)
        #expect(recent.count == 1)
        #expect(recent.first?.id == new.id)
    }

    @Test("push 同 id · upsert 覆盖")
    func pushUpserts() async throws {
        let backend = MockSyncBackend()
        let id = UUID()
        try await backend.push([record(id: id, version: 1, payload: "v1")])
        try await backend.push([record(id: id, modifiedOffset: 5, version: 2, payload: "v2")])

        let all = try await backend.fetch(recordType: recordType, since: nil)
        #expect(all.count == 1)
        #expect(all.first?.version == 2)
        #expect(all.first?.payload == Data("v2".utf8))
    }

    @Test("delete 写 tombstone · fetch 取得")
    func deleteWritesTombstone() async throws {
        let backend = MockSyncBackend()
        let id = UUID()
        try await backend.push([record(id: id, version: 1)])

        let deletedAt = baseTime.addingTimeInterval(20)
        try await backend.delete(recordType: recordType, ids: [id], deletedAt: deletedAt)

        let all = try await backend.fetch(recordType: recordType, since: nil)
        #expect(all.count == 1)
        #expect(all.first?.isDeleted == true)
        #expect(all.first?.deletedAt == deletedAt)
        #expect(all.first?.version == 2)  // 自增
    }

    @Test("delete 不存在的 id · 创建 tombstone-only 占位")
    func deleteUnknownCreatesTombstone() async throws {
        let backend = MockSyncBackend()
        let id = UUID()
        let deletedAt = baseTime.addingTimeInterval(10)
        try await backend.delete(recordType: recordType, ids: [id], deletedAt: deletedAt)

        let all = try await backend.fetch(recordType: recordType, since: nil)
        #expect(all.count == 1)
        #expect(all.first?.isDeleted == true)
        #expect(all.first?.payload.isEmpty == true)
    }

    @Test("failureMode fetchFails · fetch 抛错")
    func failureFetch() async throws {
        let backend = MockSyncBackend()
        await backend.setFailure(.fetchFails(.networkUnavailable))
        await #expect(throws: SyncBackendError.self) {
            try await backend.fetch(recordType: self.recordType, since: nil)
        }
    }

    @Test("failureMode pushFails · push 抛错 + 状态未变")
    func failurePush() async throws {
        let backend = MockSyncBackend()
        await backend.setFailure(.pushFails(.quotaExceeded))
        await #expect(throws: SyncBackendError.self) {
            try await backend.push([self.record()])
        }
        let snap = await backend.snapshot(recordType: recordType)
        #expect(snap.isEmpty)
    }

    @Test("reset 清状态")
    func reset() async throws {
        let backend = MockSyncBackend()
        try await backend.push([record(), record()])
        await backend.reset()
        let all = try await backend.fetch(recordType: recordType, since: nil)
        #expect(all.isEmpty)
    }
}
