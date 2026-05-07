// AlertSyncAdapter · Alert ↔ SyncRecord 桥接（WP-60 · v15.24 batch007）
//
// 敏感数据 · 阿里云自建通道（Stage B WP-84 启用）：
//   - D4 G1 方案 A：预警条件含交易意图 · 不走 CloudKit
//   - 字段预埋让 schema 后期接入 backend 时无需改动

import Foundation
import SyncCore

extension Alert: SyncableRecord, SyncRecordDecodable {
    public static var syncRecordType: String { "alert" }

    public var lastModified: Date { updatedAt }

    public func encodePayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from record: SyncRecord) throws -> Alert {
        precondition(record.recordType == syncRecordType,
                     "expected recordType '\(syncRecordType)' got '\(record.recordType)'")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var alert = try decoder.decode(Alert.self, from: record.payload)
        alert.version = record.version
        alert.deletedAt = record.deletedAt
        alert.updatedAt = record.lastModified
        return alert
    }
}
