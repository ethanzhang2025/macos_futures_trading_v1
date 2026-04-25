// WP-133a · AnalyticsEventStore 协议合约测试
// 同一组测试覆盖 InMemory + JSONFile · 保证两实现行为等价

import Testing
import Foundation
@testable import Shared

// MARK: - 测试 helpers

private func makeEvent(
    userID: String = "u1",
    deviceID: String = "d1",
    sessionID: String? = "s1",
    name: AnalyticsEventName = .appLaunch,
    ts: Int64 = 1_700_000_000_000,
    properties: [String: String] = [:],
    uploaded: Bool = false
) -> AnalyticsEvent {
    AnalyticsEvent(
        userID: userID, deviceID: deviceID, sessionID: sessionID,
        eventName: name, eventTimestampMs: ts,
        properties: properties, appVersion: "1.0.0", uploaded: uploaded
    )
}

private func tempFileURL() -> URL {
    let name = "analytics-\(UUID().uuidString).json"
    return FileManager.default.temporaryDirectory.appendingPathComponent(name)
}

// MARK: - 1. InMemory 实现合约

@Suite("InMemoryAnalyticsEventStore · 协议合约")
struct InMemoryAnalyticsStoreTests {

    @Test("append 自增 id 从 1 起")
    func appendAutoIncrement() async throws {
        let store = InMemoryAnalyticsEventStore()
        let id1 = try await store.append(makeEvent())
        let id2 = try await store.append(makeEvent())
        #expect(id1 == 1)
        #expect(id2 == 2)
    }

    @Test("appendBatch 批量入库 + id 顺序")
    func batchAppendOrdered() async throws {
        let store = InMemoryAnalyticsEventStore()
        let ids = try await store.appendBatch([
            makeEvent(name: .appLaunch),
            makeEvent(name: .sessionStart),
            makeEvent(name: .chartOpen)
        ])
        #expect(ids == [1, 2, 3])
        #expect(try await store.count() == 3)
    }

    @Test("queryPending 仅返回 uploaded=false · 按时间升序")
    func queryPendingFiltersAndSorts() async throws {
        let store = InMemoryAnalyticsEventStore()
        try await store.append(makeEvent(ts: 3000))
        try await store.append(makeEvent(ts: 1000))
        try await store.append(makeEvent(ts: 2000, uploaded: true))

        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 2)
        #expect(pending[0].eventTimestampMs == 1000)
        #expect(pending[1].eventTimestampMs == 3000)
    }

    @Test("queryPending limit 限制条数")
    func queryPendingLimit() async throws {
        let store = InMemoryAnalyticsEventStore()
        for ts in (1...5) {
            try await store.append(makeEvent(ts: Int64(ts) * 1000))
        }
        let limited = try await store.queryPending(limit: 3)
        #expect(limited.count == 3)
        #expect(limited.last?.eventTimestampMs == 3000)
    }

    @Test("markUploaded 翻转 uploaded 字段")
    func markUploaded() async throws {
        let store = InMemoryAnalyticsEventStore()
        let id1 = try await store.append(makeEvent())
        let id2 = try await store.append(makeEvent())

        try await store.markUploaded(ids: [id1])
        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 1)
        #expect(pending[0].id == id2)
    }

    @Test("cleanupUploaded 仅删除 uploaded=true 且时间 < cutoff")
    func cleanupUploadedRespectsCutoff() async throws {
        let store = InMemoryAnalyticsEventStore()
        try await store.append(makeEvent(ts: 1000, uploaded: true))   // 保留：未到 cutoff（cutoff=2000，但 1000<2000 → 删）
        try await store.append(makeEvent(ts: 3000, uploaded: true))   // 保留：>= cutoff
        try await store.append(makeEvent(ts: 500, uploaded: false))   // 保留：未上报

        let removed = try await store.cleanupUploaded(beforeTimestampMs: 2000)
        #expect(removed == 1)
        #expect(try await store.count() == 2)
    }
}

// MARK: - 2. JSONFile 实现合约

@Suite("JSONFileAnalyticsEventStore · 协议合约")
struct JSONFileAnalyticsStoreTests {

    @Test("append + 重启后加载持久化数据")
    func persistenceAcrossRestarts() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = JSONFileAnalyticsEventStore(fileURL: url)
        try await store1.append(makeEvent(ts: 1000))
        try await store1.append(makeEvent(ts: 2000))
        #expect(try await store1.count() == 2)

        // 重启 → 同一文件
        let store2 = JSONFileAnalyticsEventStore(fileURL: url)
        #expect(try await store2.count() == 2)
        let id3 = try await store2.append(makeEvent(ts: 3000))
        #expect(id3 == 3)  // nextID 也持久化了
    }

    @Test("queryPending 持久化后排序仍正确")
    func queryPendingAfterReload() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = JSONFileAnalyticsEventStore(fileURL: url)
        try await store1.append(makeEvent(ts: 3000))
        try await store1.append(makeEvent(ts: 1000))
        try await store1.append(makeEvent(ts: 2000))

        let store2 = JSONFileAnalyticsEventStore(fileURL: url)
        let pending = try await store2.queryPending(limit: 0)
        #expect(pending.map { $0.eventTimestampMs } == [1000, 2000, 3000])
    }

    @Test("markUploaded 持久化")
    func markUploadedPersisted() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = JSONFileAnalyticsEventStore(fileURL: url)
        let id1 = try await store1.append(makeEvent())
        try await store1.append(makeEvent())

        try await store1.markUploaded(ids: [id1])

        let store2 = JSONFileAnalyticsEventStore(fileURL: url)
        let pending = try await store2.queryPending(limit: 0)
        #expect(pending.count == 1)
        #expect(pending[0].id != id1)
    }

    @Test("cleanupUploaded 持久化")
    func cleanupPersisted() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store1 = JSONFileAnalyticsEventStore(fileURL: url)
        try await store1.append(makeEvent(ts: 1000, uploaded: true))
        try await store1.append(makeEvent(ts: 3000, uploaded: false))

        let removed = try await store1.cleanupUploaded(beforeTimestampMs: 2000)
        #expect(removed == 1)

        let store2 = JSONFileAnalyticsEventStore(fileURL: url)
        #expect(try await store2.count() == 1)
    }

    @Test("空文件初始化不抛错")
    func emptyFileInit() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileAnalyticsEventStore(fileURL: url)
        #expect(try await store.count() == 0)
    }

    @Test("自动创建上级目录")
    func createsParentDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nested-\(UUID().uuidString)")
            .appendingPathComponent("subdir")
        let url = dir.appendingPathComponent("events.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = JSONFileAnalyticsEventStore(fileURL: url)
        _ = try await store.append(makeEvent())
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
