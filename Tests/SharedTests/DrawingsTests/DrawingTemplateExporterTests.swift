// WP-42 v15.18+ batch15 · 画线模板 JSON 导出/导入测试
//
// 覆盖：
// - 空数组 / 非空数组导出 → 导入 round-trip
// - replace 模式：清空已有 · 全用导入版
// - append 模式：保留已有 · 同 id 跳过
// - 错误 JSON 抛 invalidJSON
// - 不支持版本抛 unsupportedVersion

import Testing
import Foundation
@testable import Shared

private func makeTemplate(_ name: String, id: UUID = UUID(),
                          category: DrawingTemplateCategory = .custom) -> DrawingTemplate {
    let drawing = Drawing.horizontalLine(price: 3850)
    return DrawingTemplate(id: id, name: name, drawing: drawing, category: category)
}

@Suite("DrawingTemplateExporter · v15.18+ batch15 JSON 导出/导入")
struct DrawingTemplateExporterTests {

    @Test("空数组 round-trip · 导出导入恒等")
    func emptyRoundTrip() throws {
        let data = try DrawingTemplateExporter.export([])
        let merged = try DrawingTemplateExporter.import(from: data, into: [], mode: .replace)
        #expect(merged.isEmpty)
    }

    @Test("非空数组 replace 导入 · 清空旧 · 全用导入版")
    func replaceMode() throws {
        let imported = [makeTemplate("前高"), makeTemplate("通道")]
        let existing = [makeTemplate("旧模板 1"), makeTemplate("旧模板 2"), makeTemplate("旧模板 3")]
        let data = try DrawingTemplateExporter.export(imported)
        let merged = try DrawingTemplateExporter.import(from: data, into: existing, mode: .replace)
        #expect(merged.count == 2)
        #expect(merged.map(\.name) == ["前高", "通道"])
    }

    @Test("append 模式 · 保留已有 · 添加新模板")
    func appendModeAddsNew() throws {
        let imported = [makeTemplate("新 1"), makeTemplate("新 2")]
        let existing = [makeTemplate("旧 1"), makeTemplate("旧 2")]
        let data = try DrawingTemplateExporter.export(imported)
        let merged = try DrawingTemplateExporter.import(from: data, into: existing, mode: .append)
        #expect(merged.count == 4)
        #expect(merged.map(\.name) == ["旧 1", "旧 2", "新 1", "新 2"])
    }

    @Test("append 模式 · 同 id 跳过 · 防覆盖已有")
    func appendModeSkipsSameID() throws {
        let sharedID = UUID()
        let oldOne = makeTemplate("旧名字", id: sharedID)
        let importedClash = makeTemplate("新名字", id: sharedID)
        let importedNew = makeTemplate("真的新")
        let data = try DrawingTemplateExporter.export([importedClash, importedNew])
        let merged = try DrawingTemplateExporter.import(from: data, into: [oldOne], mode: .append)
        #expect(merged.count == 2)
        // 旧 id 保留旧 · 不被同 id 的导入覆盖
        #expect(merged.first { $0.id == sharedID }?.name == "旧名字")
        #expect(merged.contains { $0.name == "真的新" })
    }

    @Test("错误 JSON 抛 invalidJSON")
    func invalidJSON() {
        let bad = Data("not a json envelope".utf8)
        #expect(throws: DrawingTemplateExporter.ImportError.invalidJSON) {
            _ = try DrawingTemplateExporter.import(from: bad, into: [], mode: .append)
        }
    }

    @Test("不支持版本抛 unsupportedVersion(v)")
    func unsupportedVersion() throws {
        let envelope = """
        {
          "version": 99,
          "exportedAt": "2026-05-04T00:00:00Z",
          "templates": []
        }
        """
        let data = Data(envelope.utf8)
        #expect(throws: DrawingTemplateExporter.ImportError.unsupportedVersion(99)) {
            _ = try DrawingTemplateExporter.import(from: data, into: [], mode: .append)
        }
    }

    @Test("envelope 含 version=1 + ISO8601 时间 + sortedKeys 输出 diff 友好")
    func envelopeFormat() throws {
        let templates = [makeTemplate("前高")]
        let now = Date(timeIntervalSince1970: 1746360000)  // 固定时间便于断言
        let data = try DrawingTemplateExporter.export(templates, now: now)
        let json = String(data: data, encoding: .utf8) ?? ""
        // 关键字段在 JSON 中（sortedKeys 保序）
        #expect(json.contains("\"version\""))
        #expect(json.contains("\"exportedAt\""))
        #expect(json.contains("\"templates\""))
        #expect(json.contains("前高"))
        // ISO8601 格式（2026-05-04T... · UTC Z）
        #expect(json.contains("2026-05-04"))
    }
}
