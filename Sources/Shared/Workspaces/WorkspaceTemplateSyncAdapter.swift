// WorkspaceTemplateSyncAdapter · WorkspaceTemplate ↔ SyncRecord 桥接（WP-60 · v15.24 batch004）
//
// 设计：
//   - WorkspaceTemplate 实现 SyncableRecord + SyncRecordDecodable
//   - syncRecordType = "workspace_template"
//   - payload = JSON(WorkspaceTemplate)
//
// 用法：
//   let records = book.templates.map { try $0.toSyncRecord() }
//   let result = try await engine.sync(localRecords: records, recordType: WorkspaceTemplate.syncRecordType)
//   let merged = try result.merged.map { try WorkspaceTemplate.decode(from: $0) }
//   book = WorkspaceBook(templates: merged.filter { $0.deletedAt == nil })

import Foundation
import SyncCore

extension WorkspaceTemplate: SyncableRecord, SyncRecordDecodable {
    public static var syncRecordType: String { "workspace_template" }

    public var lastModified: Date { updatedAt }

    public func encodePayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from record: SyncRecord) throws -> WorkspaceTemplate {
        precondition(record.recordType == syncRecordType,
                     "expected recordType '\(syncRecordType)' got '\(record.recordType)'")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var template = try decoder.decode(WorkspaceTemplate.self, from: record.payload)
        template.version = record.version
        template.deletedAt = record.deletedAt
        template.updatedAt = record.lastModified
        return template
    }
}
