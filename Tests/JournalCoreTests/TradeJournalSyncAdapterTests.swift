// TradeJournalSyncAdapter 测试 · WP-60 batch006

import Testing
import Foundation
@testable import JournalCore
import SyncCore

@Suite("TradeJournalSyncAdapter · 双向转换")
struct TradeJournalSyncAdapterTests {

    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    private func sample(version: Int = 1, deletedAt: Date? = nil) -> TradeJournal {
        TradeJournal(
            id: UUID(),
            tradeIDs: [UUID(), UUID()],
            title: "RB 突破 3500",
            reason: "macd 金叉 + 量能背离",
            emotion: .confident,
            deviation: .asPlanned,
            lesson: "止损要严格执行",
            tags: ["突破", "RB"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            version: version,
            deletedAt: deletedAt
        )
    }

    @Test("syncRecordType = journal")
    func recordType() {
        #expect(TradeJournal.syncRecordType == "journal")
    }

    @Test("toSyncRecord · 字段映射")
    func toSyncRecordMapping() throws {
        let j = sample(version: 5)
        let record = try j.toSyncRecord()
        #expect(record.recordType == "journal")
        #expect(record.id == j.id)
        #expect(record.lastModified == j.updatedAt)
        #expect(record.version == 5)
        #expect(record.deletedAt == nil)
    }

    @Test("round-trip 还原 · 含 emotion / tags / tradeIDs")
    func roundTrip() throws {
        let original = sample(version: 7)
        let record = try original.toSyncRecord()
        let restored = try TradeJournal.decode(from: record)

        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.tradeIDs == original.tradeIDs)
        #expect(restored.emotion == original.emotion)
        #expect(restored.deviation == original.deviation)
        #expect(restored.tags == original.tags)
        #expect(restored.version == original.version)
    }

    @Test("tombstone 保留 payload")
    func tombstonePayload() throws {
        let j = sample(version: 3, deletedAt: now.addingTimeInterval(120))
        let record = try j.toSyncRecord()
        #expect(record.isDeleted)
        #expect(record.deletedAt == j.deletedAt)
    }

    @Test("markDeleted · 设 deletedAt + updatedAt + version+1")
    func markDeleted() {
        var j = sample(version: 2)
        let now = Date()
        j.markDeleted(now: now)
        #expect(j.deletedAt == now)
        #expect(j.updatedAt == now)
        #expect(j.version == 3)
    }

    @Test("markDeleted · 重复幂等")
    func markDeletedIdempotent() {
        var j = sample(deletedAt: now)
        let v = j.version
        j.markDeleted(now: Date())
        #expect(j.version == v)
    }

    @Test("decode · metadata 以 SyncRecord 为准")
    func decodeMetadataPriority() throws {
        let j = sample()
        var record = try j.toSyncRecord()
        record = SyncRecord(
            recordType: record.recordType,
            id: record.id,
            lastModified: now.addingTimeInterval(999),
            version: 99,
            deletedAt: now.addingTimeInterval(999),
            payload: record.payload
        )
        let restored = try TradeJournal.decode(from: record)
        #expect(restored.version == 99)
        #expect(restored.deletedAt == now.addingTimeInterval(999))
    }
}

@Suite("TradeJournal · Codable 向后兼容")
struct TradeJournalCodableCompatTests {

    @Test("旧 JSON 缺 version/deletedAt · 回退")
    func legacyJSON() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "tradeIDs": [],
            "title": "old",
            "reason": "",
            "emotion": "calm",
            "deviation": "asPlanned",
            "lesson": "",
            "tags": [],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let j = try decoder.decode(TradeJournal.self, from: Data(json.utf8))
        #expect(j.version == 1)
        #expect(j.deletedAt == nil)
        #expect(j.title == "old")
    }
}
