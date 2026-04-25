// WP-19a · SQLiteAnalyticsEventStore 协议合约测试
// 用 :memory: 数据库 · 每个测试独立连接

import Testing
import Foundation
@testable import Shared

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

private func makeStore() throws -> SQLiteAnalyticsEventStore {
    try SQLiteAnalyticsEventStore(path: ":memory:")
}

@Suite("SQLiteAnalyticsEventStore · 协议合约")
struct SQLiteAnalyticsStoreTests {

    @Test("append 自增 id 从 1 起")
    func appendAutoIncrement() async throws {
        let store = try makeStore()
        let id1 = try await store.append(makeEvent())
        let id2 = try await store.append(makeEvent())
        #expect(id1 == 1)
        #expect(id2 == 2)
    }

    @Test("appendBatch 批量入库 + id 顺序")
    func batchAppendOrdered() async throws {
        let store = try makeStore()
        let ids = try await store.appendBatch([
            makeEvent(name: .appLaunch),
            makeEvent(name: .sessionStart),
            makeEvent(name: .chartOpen)
        ])
        #expect(ids == [1, 2, 3])
        #expect(try await store.count() == 3)
    }

    @Test("appendBatch 空数组 → no-op")
    func batchAppendEmpty() async throws {
        let store = try makeStore()
        let ids = try await store.appendBatch([])
        #expect(ids.isEmpty)
        #expect(try await store.count() == 0)
    }

    @Test("queryPending 仅返回 uploaded=false · 按时间升序")
    func queryPendingFiltersAndSorts() async throws {
        let store = try makeStore()
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
        let store = try makeStore()
        for ts in (1...5) {
            try await store.append(makeEvent(ts: Int64(ts) * 1000))
        }
        let limited = try await store.queryPending(limit: 3)
        #expect(limited.count == 3)
        #expect(limited.last?.eventTimestampMs == 3000)
    }

    @Test("markUploaded 翻转 uploaded 字段")
    func markUploaded() async throws {
        let store = try makeStore()
        let id1 = try await store.append(makeEvent())
        let id2 = try await store.append(makeEvent())

        try await store.markUploaded(ids: [id1])
        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 1)
        #expect(pending[0].id == id2)
    }

    @Test("markUploaded 多 id 一次更新")
    func markUploadedMultiple() async throws {
        let store = try makeStore()
        let id1 = try await store.append(makeEvent())
        let id2 = try await store.append(makeEvent())
        let id3 = try await store.append(makeEvent())

        try await store.markUploaded(ids: [id1, id3])
        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 1)
        #expect(pending[0].id == id2)
    }

    @Test("cleanupUploaded 仅删除 uploaded=true 且时间 < cutoff")
    func cleanupUploadedRespectsCutoff() async throws {
        let store = try makeStore()
        try await store.append(makeEvent(ts: 1000, uploaded: true))   // 删
        try await store.append(makeEvent(ts: 3000, uploaded: true))   // 保留：>= cutoff
        try await store.append(makeEvent(ts: 500, uploaded: false))   // 保留：未上报

        let removed = try await store.cleanupUploaded(beforeTimestampMs: 2000)
        #expect(removed == 1)
        #expect(try await store.count() == 2)
    }

    @Test("properties JSON 持久化往返")
    func propertiesRoundtrip() async throws {
        let store = try makeStore()
        try await store.append(makeEvent(
            name: .chartOpen,
            properties: ["contract_code": "RB0", "period": "60"]
        ))
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].properties["contract_code"] == "RB0")
        #expect(pending[0].properties["period"] == "60")
    }

    @Test("sessionID 可空 · null/text 字段都能解码")
    func nullSessionRoundtrip() async throws {
        let store = try makeStore()
        try await store.append(makeEvent(sessionID: "S1"))
        try await store.append(makeEvent(sessionID: nil))
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].sessionID == "S1")
        #expect(pending[1].sessionID == nil)
    }

    @Test("文件持久化往返：append → 重启 → 数据完整")
    func filePersistenceAcrossRestarts() async throws {
        let path = NSTemporaryDirectory() + "wp19a_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store1 = try SQLiteAnalyticsEventStore(path: path)
        try await store1.append(makeEvent(ts: 1000))
        try await store1.append(makeEvent(ts: 2000))
        await store1.close()

        let store2 = try SQLiteAnalyticsEventStore(path: path)
        #expect(try await store2.count() == 2)
        let id3 = try await store2.append(makeEvent(ts: 3000))
        #expect(id3 == 3)  // AUTOINCREMENT 跨重启持续递增
        await store2.close()
    }
}
