// TradeJournalSyncAdapter · TradeJournal ↔ SyncRecord 桥接（WP-60 · v15.24 batch006）
//
// 敏感数据 · 阿里云自建通道（Stage B WP-84 启用）：
//   - D4 G1 方案 A：日志含 PII · 不走 CloudKit（境外合规）
//   - 字段预埋让 schema 后期接入 backend 时无需改动
//
// 用法（Stage B 接入时）：
//   let records = try journals.map { try $0.toSyncRecord() }
//   let result = try await aliyunEngine.sync(localRecords: records, recordType: TradeJournal.syncRecordType)
//   let merged = try result.merged.map { try TradeJournal.decode(from: $0) }

import Foundation
import SyncCore

extension TradeJournal: SyncableRecord, SyncRecordDecodable {
    public static var syncRecordType: String { "journal" }

    public var lastModified: Date { updatedAt }

    public func encodePayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from record: SyncRecord) throws -> TradeJournal {
        precondition(record.recordType == syncRecordType,
                     "expected recordType '\(syncRecordType)' got '\(record.recordType)'")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var journal = try decoder.decode(TradeJournal.self, from: record.payload)
        journal.version = record.version
        journal.deletedAt = record.deletedAt
        journal.updatedAt = record.lastModified
        return journal
    }
}
