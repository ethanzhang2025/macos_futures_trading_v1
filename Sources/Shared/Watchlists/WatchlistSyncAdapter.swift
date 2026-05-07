// WatchlistSyncAdapter · Watchlist ↔ SyncRecord 桥接（WP-60 · v15.24 batch003）
//
// 设计：
//   - Watchlist 实现 SyncableRecord + SyncRecordDecodable
//   - syncRecordType = "watchlist"
//   - payload = JSON(Watchlist)（保留全部业务字段 · 后端只看 metadata）
//   - 同步层使用 Watchlist.updatedAt 作为 lastModified
//
// 用法：
//   let records = book.groups.map { try $0.toSyncRecord() }
//   let result = try await engine.sync(localRecords: records, recordType: Watchlist.syncRecordType)
//   let merged = try result.merged.map { try Watchlist.decode(from: $0) }
//   book = WatchlistBook(groups: merged.filter { $0.deletedAt == nil })
//
// 注意：
//   - tombstone 也带 payload（保留分组 name 用于 UI 显示"已删 N 个"）
//   - decoder 不过滤 tombstone（由调用方决定是否纳入 UI）

import Foundation
import SyncCore

extension Watchlist: SyncableRecord, SyncRecordDecodable {
    public static var syncRecordType: String { "watchlist" }

    public var lastModified: Date { updatedAt }

    public func encodePayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from record: SyncRecord) throws -> Watchlist {
        precondition(record.recordType == syncRecordType,
                     "expected recordType '\(syncRecordType)' got '\(record.recordType)'")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var watchlist = try decoder.decode(Watchlist.self, from: record.payload)
        // metadata 以 SyncRecord 为准（防止 payload JSON 与 record metadata 不一致）
        watchlist.version = record.version
        watchlist.deletedAt = record.deletedAt
        watchlist.updatedAt = record.lastModified
        return watchlist
    }
}
