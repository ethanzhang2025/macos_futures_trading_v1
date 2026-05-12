// MainApp · Shell · v17.137 · 用户 Workspace 预设导入导出 transfer 容器
// trader 场景：
// - 备份精心调好的预设（防误删 / 跨机器迁移 / 重装恢复）
// - 分享给同事或社区（论坛贴 .json 文件）
//
// 设计：
// - 顶层加 version 字段（v1 = 当前 schema）· 防未来 schema 演变破坏旧文件
// - exportedAt 时间戳便于查看（trader 看文件归属）
// - 数组本身就是 UserWorkspacePreset 单体 · 不重新声明
// - 导入失败降级到友好错误（trader 看到「文件格式不支持」而非崩溃）

import Foundation

/// 用户 Workspace 预设导入导出容器（version 1）
public struct UserWorkspacePresetTransfer: Codable, Sendable, Equatable {

    /// 当前 schema 版本（变更 schema 时 +1 · decoder 兼容 fallback）
    public static let currentSchemaVersion: Int = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var presets: [UserWorkspacePreset]

    public init(presets: [UserWorkspacePreset], exportedAt: Date = Date(), schemaVersion: Int = currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.presets = presets
    }

    // MARK: - Codable（容错：旧文件缺 schemaVersion / exportedAt 时降级处理）

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, presets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date(timeIntervalSince1970: 0)
        self.presets = try c.decode([UserWorkspacePreset].self, forKey: .presets)
    }
}

/// 导入模式（trader 决策）
public enum WorkspacePresetImportMode: Sendable {
    /// 追加（保留现有预设 · 导入数组逐个 append · 新 UUID 防 id 碰撞）
    case append
    /// 全量替换（清空现有 · 用导入数组替换）
    case replaceAll
}

/// 导入结果（UI 显示反馈）
public struct WorkspacePresetImportResult: Sendable, Equatable {
    public var importedCount: Int
    public var totalAfterImport: Int

    public init(importedCount: Int, totalAfterImport: Int) {
        self.importedCount = importedCount
        self.totalAfterImport = totalAfterImport
    }
}

/// 导入错误（区分常见失败模式 · UI 给具体提示）
public enum WorkspacePresetImportError: Error, Equatable {
    case fileEmpty
    case invalidJSON(String)
    case unsupportedSchemaVersion(Int)
}
