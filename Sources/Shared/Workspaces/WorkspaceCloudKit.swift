// WP-55 · CloudKit 字段映射预埋
// WorkspaceTemplate 整体序列化为一条 CKRecord：
//   - 标量字段直接映射（name/kind/sortIndex/createdAt/updatedAt/shortcutKeyCode/shortcutModifiers）
//   - windows 用 Codable JSON 嵌入 String 字段（避免 CKReference 复杂性，v1 简单优先）
// 不 import CloudKit（Linux 跨端兼容）；实际 CKContainer 同步留 A12（M7-M9）

import Foundation

extension WorkspaceTemplate {

    /// CloudKit 记录类型名（CKRecordType）
    public static let cloudKitRecordType: String = "WorkspaceTemplate"

    /// CloudKit 字段键（与 cloudKitFields 严格对齐）
    public enum CloudKitField {
        public static let name: String = "name"
        public static let kind: String = "kind"
        public static let sortIndex: String = "sortIndex"
        public static let createdAt: String = "createdAt"
        public static let updatedAt: String = "updatedAt"
        public static let shortcutKeyCode: String = "shortcutKeyCode"
        public static let shortcutModifiers: String = "shortcutModifiers"
        /// windows 序列化后的 JSON 字符串（v1 嵌入式；v2 视量级再考虑拆 CKReference）
        public static let windowsJSON: String = "windowsJSON"
    }

    /// CloudKit recordName（recordID.recordName）
    public var cloudKitRecordName: String { id.uuidString }

    /// 序列化为 CKRecord 兼容字段字典
    /// - Throws: windows JSON 编码失败时抛 EncodingError
    public func cloudKitFields() throws -> [String: any Sendable] {
        let windowsData = try JSONEncoder.cloudKit.encode(windows)
        let windowsJSON = String(decoding: windowsData, as: UTF8.self)

        var fields: [String: any Sendable] = [
            CloudKitField.name: name,
            CloudKitField.kind: kind.rawValue,
            CloudKitField.sortIndex: Int64(sortIndex),
            CloudKitField.createdAt: createdAt,
            CloudKitField.updatedAt: updatedAt,
            CloudKitField.windowsJSON: windowsJSON,
        ]
        if let shortcut = shortcut {
            fields[CloudKitField.shortcutKeyCode] = Int64(shortcut.keyCode)
            fields[CloudKitField.shortcutModifiers] = Int64(shortcut.modifierFlags)
        }
        return fields
    }

    /// 从 CKRecord 字段字典反序列化
    /// - Returns: nil 表示必填字段缺失或类型不符 / windows JSON 解析失败
    public init?(cloudKitRecordName recordName: String, fields: [String: Any]) {
        guard let id = UUID(uuidString: recordName),
              let name = fields[CloudKitField.name] as? String,
              let kindRaw = fields[CloudKitField.kind] as? String,
              let kind = Kind(rawValue: kindRaw),
              let createdAt = fields[CloudKitField.createdAt] as? Date,
              let updatedAt = fields[CloudKitField.updatedAt] as? Date,
              let windowsJSON = fields[CloudKitField.windowsJSON] as? String,
              let windowsData = windowsJSON.data(using: .utf8),
              let windows = try? JSONDecoder.cloudKit.decode([WindowLayout].self, from: windowsData)
        else { return nil }

        // CKRecord Number 字段实际类型是 Int64，但本地 Mock/测试可能传 Int → 双路径兼容
        let sortIndex = (fields[CloudKitField.sortIndex] as? Int64).map(Int.init)
            ?? (fields[CloudKitField.sortIndex] as? Int)
            ?? 0

        let shortcut: WorkspaceShortcut? = {
            let keyCode = (fields[CloudKitField.shortcutKeyCode] as? Int64).map(UInt16.init)
                ?? (fields[CloudKitField.shortcutKeyCode] as? Int).map { UInt16($0) }
            let mods = (fields[CloudKitField.shortcutModifiers] as? Int64).map(UInt32.init)
                ?? (fields[CloudKitField.shortcutModifiers] as? Int).map { UInt32($0) }
            guard let k = keyCode, let m = mods else { return nil }
            return WorkspaceShortcut(keyCode: k, modifierFlags: m)
        }()

        self.init(
            id: id,
            name: name,
            kind: kind,
            windows: windows,
            shortcut: shortcut,
            sortIndex: sortIndex,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - JSON 编码统一策略（CloudKit 嵌入与本地持久化共享）

extension JSONEncoder {
    /// CloudKit 嵌入字段统一策略：iso8601 日期、稳定字段顺序
    static let cloudKit: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let cloudKit: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
