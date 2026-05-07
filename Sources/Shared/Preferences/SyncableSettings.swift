// SyncableSettings · UI 偏好同步包装（WP-60 · v15.24 batch005 · 字段预埋）
//
// 设计：
//   - 整套 settings 合成单条 SyncRecord（固定 id · 全局只有一条）
//   - 粒度内：键值对 · String → SettingsValue（Bool/Int/Double/String/Data）
//   - 同步策略：任何键变更 → 整条 lastModified 更新 + version+1
//
// 范围（v1）：
//   - 仅"白名单"key 进入同步层（SyncableSettings.knownKeys）
//   - 现有 @AppStorage 散落 UI 不动 · 由 SyncableSettings.snapshot(from: UserDefaults) 收集
//   - 实际启用同步由 batch008 接 backend 时触发
//
// 不在 v1 范围：
//   - 自动镜像 UserDefaults 改动到 SyncableSettings（KVO 监听）
//   - 应用 backend 拉下来的 settings 到 UserDefaults（UI 视图重读）
//   - 这两步留给后续 UI 层接入时（batch008+ 或单独 WP）

import Foundation
import SyncCore

/// settings 值类型 · 仅支持 Codable 原始类型
public enum SettingsValue: Sendable, Codable, Equatable, Hashable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)

    public var asBool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var asInt: Int? { if case .int(let v) = self { v } else { nil } }
    public var asDouble: Double? { if case .double(let v) = self { v } else { nil } }
    public var asString: String? { if case .string(let v) = self { v } else { nil } }
    public var asData: Data? { if case .data(let v) = self { v } else { nil } }
}

/// UI 偏好可同步聚合 · 全局单条
public struct SyncableSettings: Sendable, Codable, Equatable {

    /// 全局固定 ID · 同步层用此识别"settings 这一条"
    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// 已知 keys 白名单（仅这些 key 进入同步）
    /// 添加新 key 时此处声明 · 防止误同步敏感数据（如认证 token）
    public static let knownKeys: Set<String> = [
        // K 线 / 图表
        "viewport.v1",
        "subIndicators.v1",
        "subChartHeight.v1",
        // 自选 / 工作区
        "watchlist.activeGroup",
        "workspace.activeTemplate",
        // 主题
        "theme.preferred",
        "theme.candleColor",
        // 复盘 / 日志 / 训练
        "review.dateFilter",
        "journal.sortKey",
        "journal.tradeSortKey",
        "training.recentLimit",
        // 列宽 / 表格
        "table.columnWidths"
    ]

    public var values: [String: SettingsValue]
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?

    public init(
        values: [String: SettingsValue] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        version: Int = 1,
        deletedAt: Date? = nil
    ) {
        self.values = values
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.deletedAt = deletedAt
    }

    /// 设置 key · 自动 version+1 + updatedAt 刷新（仅当值实际变化）
    @discardableResult
    public mutating func set(_ key: String, _ value: SettingsValue, now: Date = Date()) -> Bool {
        guard Self.knownKeys.contains(key) else { return false }
        if values[key] == value { return false }
        values[key] = value
        updatedAt = now
        version += 1
        return true
    }

    /// 移除 key（不算 settings 整体 tombstone · 仅是单 key 删）
    @discardableResult
    public mutating func remove(_ key: String, now: Date = Date()) -> Bool {
        guard values[key] != nil else { return false }
        values.removeValue(forKey: key)
        updatedAt = now
        version += 1
        return true
    }

    public func get(_ key: String) -> SettingsValue? {
        values[key]
    }

    /// 从 UserDefaults 收集已知 key 的快照（迁移期用）
    public static func snapshot(from defaults: UserDefaults, now: Date = Date()) -> SyncableSettings {
        var values: [String: SettingsValue] = [:]
        for key in knownKeys {
            guard let raw = defaults.object(forKey: key) else { continue }
            if let b = raw as? Bool { values[key] = .bool(b) }
            else if let i = raw as? Int { values[key] = .int(i) }
            else if let d = raw as? Double { values[key] = .double(d) }
            else if let s = raw as? String { values[key] = .string(s) }
            else if let data = raw as? Data { values[key] = .data(data) }
        }
        return SyncableSettings(values: values, createdAt: now, updatedAt: now)
    }

    // MARK: - Codable 兼容

    private enum CodingKeys: String, CodingKey {
        case values, createdAt, updatedAt, version, deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.values = try c.decodeIfPresent([String: SettingsValue].self, forKey: .values) ?? [:]
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(values, forKey: .values)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - Sync Adapter

extension SyncableSettings: SyncableRecord, SyncRecordDecodable {
    public static var syncRecordType: String { "settings" }

    public var id: UUID { Self.singletonID }
    public var lastModified: Date { updatedAt }

    public func encodePayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from record: SyncRecord) throws -> SyncableSettings {
        precondition(record.recordType == syncRecordType,
                     "expected recordType '\(syncRecordType)' got '\(record.recordType)'")
        precondition(record.id == singletonID,
                     "settings 是全局单条 · id 必须为 singletonID")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var settings = try decoder.decode(SyncableSettings.self, from: record.payload)
        settings.version = record.version
        settings.deletedAt = record.deletedAt
        settings.updatedAt = record.lastModified
        return settings
    }
}
