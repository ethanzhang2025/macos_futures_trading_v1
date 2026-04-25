// WP-43 · CloudKit 字段映射预埋
// 仅做 CKRecord 字段名与类型契约预埋，不 import CloudKit（保持 Linux 跨端可移植）
// 实际 CKContainer 同步、订阅、冲突合并、加密分级 → 留给 A12（M7-M9）
//
// 字段约束（CKRecord 规范）：
// - 字段名 < 255 字符 / 不与 CloudKit 系统字段重名（recordID/recordName/recordType/createdUser/modifiedUser/recordChangeTag）
// - 类型限定：Int64/Double/String/Date/Data/[String]/Reference/Asset/Location
// - recordName 由 Watchlist.id.uuidString 充当（保证幂等）

import Foundation

extension Watchlist {

    /// CloudKit 记录类型名（CKRecordType）
    public static let cloudKitRecordType: String = "Watchlist"

    /// CloudKit 字段键（与下方 dictionary key 严格对齐，避免散落字符串）
    public enum CloudKitField {
        public static let name: String = "name"
        public static let sortIndex: String = "sortIndex"
        public static let instrumentIDs: String = "instrumentIDs"
        public static let createdAt: String = "createdAt"
        public static let updatedAt: String = "updatedAt"
    }

    /// CloudKit recordName（recordID.recordName）
    public var cloudKitRecordName: String { id.uuidString }

    /// 序列化为 CKRecord 兼容字段字典（A12 时直接 forEach 套 record[key] = value）
    public func cloudKitFields() -> [String: any Sendable] {
        [
            CloudKitField.name: name,
            CloudKitField.sortIndex: Int64(sortIndex),
            CloudKitField.instrumentIDs: instrumentIDs,
            CloudKitField.createdAt: createdAt,
            CloudKitField.updatedAt: updatedAt,
        ]
    }

    /// 从 CKRecord 字段字典反序列化（recordName 单独传入，因为它来自 record.recordID）
    /// - Returns: nil 表示必填字段缺失或类型不符
    public init?(cloudKitRecordName recordName: String, fields: [String: Any]) {
        guard let id = UUID(uuidString: recordName),
              let name = fields[CloudKitField.name] as? String,
              let createdAt = fields[CloudKitField.createdAt] as? Date,
              let updatedAt = fields[CloudKitField.updatedAt] as? Date
        else { return nil }

        // CKRecord Number 字段实际类型是 Int64，但本地 Mock/测试可能传 Int → 双路径兼容
        let sortIndex = (fields[CloudKitField.sortIndex] as? Int64).map(Int.init)
            ?? (fields[CloudKitField.sortIndex] as? Int)
            ?? 0

        let instrumentIDs = fields[CloudKitField.instrumentIDs] as? [String] ?? []

        self.init(
            id: id,
            name: name,
            sortIndex: sortIndex,
            instrumentIDs: instrumentIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
