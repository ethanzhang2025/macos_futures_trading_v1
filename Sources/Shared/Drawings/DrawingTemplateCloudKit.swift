// WP-A6.2 · v17.56 · DrawingTemplate CloudKit 字段映射预埋
//
// 仅做 CKRecord 字段名与类型契约预埋，不 import CloudKit（保持 Linux 跨端可移植）
// 实际 CKContainer 同步、订阅、冲突合并、加密分级 → 留给 M7+（与 Watchlist v8 同节奏）
//
// 字段约束（CKRecord 规范）：
// - 字段名 < 255 字符 / 不与 CloudKit 系统字段重名（recordID/recordName/recordType/createdUser/modifiedUser/recordChangeTag）
// - 类型限定：Int64/Double/String/Date/Data/[String]/Reference/Asset/Location
// - recordName 由 DrawingTemplate.id.uuidString 充当（保证幂等）
// - drawing 整体序列化为 Data 字段（嵌套 Drawing 含 type/anchors/style/text/offset 等 · 一次性 round-trip）
//
// 参照：Sources/Shared/Watchlists/WatchlistCloudKit.swift（WP-43 同模式）

import Foundation

extension DrawingTemplate {

    /// CloudKit 记录类型名（CKRecordType）
    public static let cloudKitRecordType: String = "DrawingTemplate"

    /// CloudKit 字段键（与下方 dictionary key 严格对齐，避免散落字符串）
    public enum CloudKitField {
        public static let name: String = "name"
        public static let category: String = "category"
        public static let drawingData: String = "drawingData"
        public static let createdAt: String = "createdAt"
    }

    /// CloudKit recordName（recordID.recordName）
    public var cloudKitRecordName: String { id.uuidString }

    /// 序列化为 CKRecord 兼容字段字典（M7 启用时直接 forEach 套 record[key] = value）
    /// - Throws: drawing JSON 编码失败（罕见 · 仅恶意构造）
    public func cloudKitFields() throws -> [String: any Sendable] {
        let drawingData = try JSONEncoder().encode(drawing)
        return [
            CloudKitField.name: name,
            CloudKitField.category: category.rawValue,
            CloudKitField.drawingData: drawingData,
            CloudKitField.createdAt: createdAt,
        ]
    }

    /// 从 CKRecord 字段字典反序列化（recordName 单独传入，因为它来自 record.recordID）
    /// - Returns: nil 表示必填字段缺失 / 类型不符 / drawing 反序列化失败
    public init?(cloudKitRecordName recordName: String, fields: [String: Any]) {
        guard let id = UUID(uuidString: recordName),
              let name = fields[CloudKitField.name] as? String,
              let drawingData = fields[CloudKitField.drawingData] as? Data,
              let drawing = try? JSONDecoder().decode(Drawing.self, from: drawingData),
              let createdAt = fields[CloudKitField.createdAt] as? Date
        else { return nil }

        let category: DrawingTemplateCategory = (fields[CloudKitField.category] as? String)
            .flatMap(DrawingTemplateCategory.init(rawValue:)) ?? .custom

        self.init(
            id: id,
            name: name,
            drawing: drawing,
            createdAt: createdAt,
            category: category
        )
    }
}
