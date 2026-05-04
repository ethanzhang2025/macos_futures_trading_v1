// WP-42 v15.19 batch39 · DrawingTemplate category 单测

import Testing
import Foundation
@testable import Shared

@Suite("DrawingTemplateCategory · v15.19 batch39")
struct DrawingTemplateCategoryTests {

    @Test("5 类全有 displayName 不空")
    func allLabels() {
        for cat in DrawingTemplateCategory.allCases {
            #expect(!cat.displayName.isEmpty)
        }
    }

    @Test("默认 category = .custom")
    func defaultCategory() {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "test", drawing: drawing)
        #expect(template.category == .custom)
    }

    @Test("Codable JSON 往返 · 含 category")
    func codableRoundTrip() throws {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "test", drawing: drawing, category: .keyLevel)
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(DrawingTemplate.self, from: data)
        #expect(decoded.category == .keyLevel)
        #expect(decoded.name == template.name)
    }

    @Test("旧 JSON 缺 category 字段 · fallback .custom")
    func legacyJSONFallback() throws {
        // 模拟 v15.18 末持久化的 JSON（无 category 字段）
        let drawingData = try JSONEncoder().encode(Drawing.horizontalLine(price: 100))
        let drawingJSON = String(data: drawingData, encoding: .utf8)!
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "name": "前高",
          "drawing": \(drawingJSON),
          "createdAt": 768268800
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DrawingTemplate.self, from: data)
        #expect(decoded.category == .custom)
        #expect(decoded.name == "前高")
    }

    @Test("DrawingTemplateExporter Envelope 含 category 字段 · 跨设备同步保留分类")
    func envelopeIncludesCategory() throws {
        let template = DrawingTemplate(
            name: "前高",
            drawing: Drawing.horizontalLine(price: 100),
            category: .keyLevel
        )
        let data = try DrawingTemplateExporter.export([template])
        let merged = try DrawingTemplateExporter.import(from: data, into: [], mode: .replace)
        #expect(merged.first?.category == .keyLevel)
    }
}
