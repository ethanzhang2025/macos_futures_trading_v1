// WatchlistSyncAdapter · Watchlist ↔ SyncRecord 转换测试（WP-60 · v15.24 batch003）
// 覆盖：
//   - 双向转换 round-trip
//   - tombstone（deletedAt）
//   - mutating 操作 version 自增
//   - softDeleteGroup 行为
//   - 旧 JSON 缺 version/deletedAt 时回退（向后兼容）

import Testing
import Foundation
@testable import Shared
import SyncCore

@Suite("WatchlistSyncAdapter · 双向转换")
struct WatchlistSyncAdapterTests {

    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    @Test("syncRecordType = watchlist")
    func recordType() {
        #expect(Watchlist.syncRecordType == "watchlist")
    }

    @Test("toSyncRecord · 字段映射")
    func toSyncRecordMapping() throws {
        let w = Watchlist(
            id: UUID(),
            name: "黄金套利",
            sortIndex: 2,
            instrumentIDs: ["au0", "ag0"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            version: 3,
            deletedAt: nil
        )
        let record = try w.toSyncRecord()
        #expect(record.recordType == "watchlist")
        #expect(record.id == w.id)
        #expect(record.lastModified == w.updatedAt)
        #expect(record.version == 3)
        #expect(record.deletedAt == nil)
        #expect(!record.payload.isEmpty)
    }

    @Test("toSyncRecord · tombstone 保留 payload")
    func toSyncRecordTombstone() throws {
        let w = Watchlist(
            id: UUID(),
            name: "已删",
            sortIndex: 0,
            instrumentIDs: ["rb0"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            version: 5,
            deletedAt: now.addingTimeInterval(60)
        )
        let record = try w.toSyncRecord()
        #expect(record.isDeleted)
        #expect(record.deletedAt == w.deletedAt)
        #expect(!record.payload.isEmpty)
    }

    @Test("round-trip 还原")
    func roundTrip() throws {
        let original = Watchlist(
            id: UUID(),
            name: "主力",
            sortIndex: 1,
            instrumentIDs: ["rb0", "i0", "hc0"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(120),
            version: 7,
            deletedAt: nil
        )
        let record = try original.toSyncRecord()
        let restored = try Watchlist.decode(from: record)

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.sortIndex == original.sortIndex)
        #expect(restored.instrumentIDs == original.instrumentIDs)
        #expect(restored.version == original.version)
        #expect(restored.deletedAt == original.deletedAt)
    }

    @Test("decode · metadata 以 SyncRecord 为准")
    func decodeUsesRecordMetadata() throws {
        let w = Watchlist(
            id: UUID(),
            name: "test",
            version: 2,
            deletedAt: nil
        )
        var record = try w.toSyncRecord()
        // 后端可能更新了 metadata · 我们以 record 为准
        record = SyncRecord(
            recordType: record.recordType,
            id: record.id,
            lastModified: now.addingTimeInterval(999),
            version: 99,
            deletedAt: now.addingTimeInterval(999),
            payload: record.payload
        )
        let restored = try Watchlist.decode(from: record)
        #expect(restored.version == 99)
        #expect(restored.deletedAt == now.addingTimeInterval(999))
        #expect(restored.updatedAt == now.addingTimeInterval(999))
    }
}

@Suite("WatchlistBook · mutating 操作 version 自增")
struct WatchlistBookVersioningTests {

    @Test("addGroup · 新建 version=1")
    func addGroupVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        #expect(g.version == 1)
        #expect(book.group(id: g.id)?.version == 1)
    }

    @Test("renameGroup · version +1")
    func renameVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        let renamed = book.renameGroup(id: g.id, to: "g2")
        #expect(renamed)
        #expect(book.group(id: g.id)?.version == 2)
    }

    @Test("renameGroup · 同名不变 version")
    func renameSameNameNoBump() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        _ = book.renameGroup(id: g.id, to: "g1")
        #expect(book.group(id: g.id)?.version == 1)
    }

    @Test("addInstrument · version +1")
    func addInstrumentVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        _ = book.addInstrument("rb0", to: g.id)
        _ = book.addInstrument("i0", to: g.id)
        #expect(book.group(id: g.id)?.version == 3)
    }

    @Test("removeInstrument · version +1")
    func removeInstrumentVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        _ = book.addInstrument("rb0", to: g.id)
        _ = book.removeInstrument("rb0", from: g.id)
        #expect(book.group(id: g.id)?.version == 3)
    }

    @Test("moveInstrument 同组 · version +1")
    func moveInstrumentSameGroup() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        _ = book.addInstrument("rb0", to: g.id)
        _ = book.addInstrument("i0", to: g.id)
        let v0 = book.group(id: g.id)!.version
        _ = book.moveInstrument(in: g.id, from: 0, to: 1)
        #expect(book.group(id: g.id)!.version == v0 + 1)
    }

    @Test("moveInstrument 跨组 · 双方各 +1")
    func moveInstrumentCrossGroup() {
        var book = WatchlistBook()
        let g1 = book.addGroup(name: "g1")
        let g2 = book.addGroup(name: "g2")
        _ = book.addInstrument("rb0", to: g1.id)
        let v1 = book.group(id: g1.id)!.version
        let v2 = book.group(id: g2.id)!.version
        _ = book.moveInstrument("rb0", from: g1.id, to: g2.id)
        #expect(book.group(id: g1.id)!.version == v1 + 1)
        #expect(book.group(id: g2.id)!.version == v2 + 1)
    }

    @Test("softDeleteGroup · 设 deletedAt + version+1 + 保留 group")
    func softDelete() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        let deletedAt = Date()
        let ok = book.softDeleteGroup(id: g.id, now: deletedAt)
        #expect(ok)
        #expect(book.group(id: g.id)?.deletedAt == deletedAt)
        #expect(book.group(id: g.id)?.version == 2)
    }

    @Test("softDeleteGroup · 重复 false")
    func softDeleteIdempotent() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "g1")
        _ = book.softDeleteGroup(id: g.id)
        let second = book.softDeleteGroup(id: g.id)
        #expect(second == false)
    }
}

@Suite("Watchlist · Codable 向后兼容")
struct WatchlistCodableCompatTests {

    @Test("旧 JSON 缺 version/deletedAt · decode 用默认值")
    func legacyJSONFallback() throws {
        let oldJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "old",
            "sortIndex": 0,
            "instrumentIDs": ["rb0"],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let w = try decoder.decode(Watchlist.self, from: Data(oldJSON.utf8))
        #expect(w.version == 1)
        #expect(w.deletedAt == nil)
        #expect(w.name == "old")
    }

    @Test("encode · deletedAt nil 时不输出键")
    func encodeNilDeletedAtOmitted() throws {
        let w = Watchlist(name: "x", version: 3, deletedAt: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(w)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"version\":3"))
        #expect(!json.contains("deletedAt"))
    }
}
