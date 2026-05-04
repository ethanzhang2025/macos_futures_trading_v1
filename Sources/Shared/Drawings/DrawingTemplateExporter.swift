// v15.18+ batch15 · 画线模板 JSON 导出 / 导入（trader 跨设备同步个人画线风格）
//
// 设计取舍：
// - 与 PreferenceExporter 同模式 · 用户手动 · Stage B 接 CloudKit 自动同步
// - JSON 格式 · 版本化 envelope · 用户可手工编辑
// - 导入 2 种模式：replace（清空旧 · 用导入版）/ append（合并 · 同 id 跳过防覆盖）
// - 不导出运行时状态（locked / id 自动重置由调用方决定）

import Foundation

public enum DrawingTemplateExporter {

    /// 导出文件 envelope · version 字段为未来 schema 演进留余地
    public struct Envelope: Codable, Equatable, Sendable {
        public let version: Int
        public let exportedAt: Date
        public let templates: [DrawingTemplate]

        public init(version: Int = 1, exportedAt: Date = Date(), templates: [DrawingTemplate]) {
            self.version = version
            self.exportedAt = exportedAt
            self.templates = templates
        }
    }

    /// 导入合并模式
    public enum ImportMode: Sendable {
        case replace   // 清空已有 · 全用导入版
        case append    // 合并 · 同 id 跳过（trader 不丢已自定义模板）
    }

    public enum ImportError: Error, Equatable, Sendable {
        case invalidJSON
        case unsupportedVersion(Int)
    }

    /// 导出 templates 为 JSON Data · ISO8601 时间 · 排序键确保 diff 友好
    public static func export(_ templates: [DrawingTemplate], now: Date = Date()) throws -> Data {
        let envelope = Envelope(exportedAt: now, templates: templates)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    /// 从 JSON Data 导入 · 返回合并后的 templates（不 mutate 输入）
    public static func `import`(
        from data: Data,
        into existing: [DrawingTemplate],
        mode: ImportMode
    ) throws -> [DrawingTemplate] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw ImportError.invalidJSON
        }
        guard envelope.version == 1 else {
            throw ImportError.unsupportedVersion(envelope.version)
        }
        switch mode {
        case .replace:
            return envelope.templates
        case .append:
            var merged = existing
            let existingIDs = Set(existing.map(\.id))
            for t in envelope.templates where !existingIDs.contains(t.id) {
                merged.append(t)
            }
            return merged
        }
    }
}
