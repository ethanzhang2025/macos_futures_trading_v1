// WP-A6.2 v17.56 · DrawingTemplate CloudKit 字段映射单测
// 模式参照：Sources/Shared/Watchlists/WatchlistCloudKit.swift

import Testing
import Foundation
@testable import Shared

@Suite("DrawingTemplate CloudKit 字段映射 · v17.56 A6.2")
struct DrawingTemplateCloudKitTests {

    @Test("recordType / recordName 契约")
    func recordTypeAndName() {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "前高阻力位", drawing: drawing)
        #expect(DrawingTemplate.cloudKitRecordType == "DrawingTemplate")
        #expect(template.cloudKitRecordName == template.id.uuidString)
    }

    @Test("cloudKitFields 含 4 字段 · 类型符合 CKRecord 规范")
    func fieldsTypes() throws {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "test", drawing: drawing, category: .keyLevel)
        let fields = try template.cloudKitFields()
        #expect(fields[DrawingTemplate.CloudKitField.name] as? String == "test")
        #expect(fields[DrawingTemplate.CloudKitField.category] as? String == "keyLevel")
        #expect(fields[DrawingTemplate.CloudKitField.drawingData] is Data)
        #expect(fields[DrawingTemplate.CloudKitField.createdAt] is Date)
    }

    @Test("CKRecord round-trip · 字段完整恢复")
    func roundTrip() throws {
        let drawing = Drawing.horizontalLine(price: 3500)
        let original = DrawingTemplate(name: "阻力", drawing: drawing, category: .channel)
        let fields = try original.cloudKitFields()
        let restored = DrawingTemplate(cloudKitRecordName: original.cloudKitRecordName, fields: fields)
        #expect(restored != nil)
        #expect(restored?.id == original.id)
        #expect(restored?.name == "阻力")
        #expect(restored?.category == .channel)
        #expect(restored?.drawing == original.drawing)
    }

    @Test("缺必填字段 · init 返回 nil")
    func missingRequiredFields() {
        let recordName = UUID().uuidString
        // name 缺
        #expect(DrawingTemplate(cloudKitRecordName: recordName, fields: [:]) == nil)
        // drawingData 缺
        let partial: [String: Any] = [
            DrawingTemplate.CloudKitField.name: "x",
            DrawingTemplate.CloudKitField.createdAt: Date(),
        ]
        #expect(DrawingTemplate(cloudKitRecordName: recordName, fields: partial) == nil)
    }

    @Test("category 缺失 → fallback .custom")
    func missingCategoryFallback() throws {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "x", drawing: drawing, category: .channel)
        var fields = try template.cloudKitFields()
        fields.removeValue(forKey: DrawingTemplate.CloudKitField.category)
        let restored = DrawingTemplate(cloudKitRecordName: template.cloudKitRecordName,
                                       fields: fields as [String: Any])
        #expect(restored?.category == .custom)
    }

    @Test("非法 recordName UUID · init 返回 nil")
    func invalidRecordName() throws {
        let drawing = Drawing.horizontalLine(price: 100)
        let template = DrawingTemplate(name: "x", drawing: drawing)
        let fields = try template.cloudKitFields()
        #expect(DrawingTemplate(cloudKitRecordName: "not-a-uuid",
                                fields: fields as [String: Any]) == nil)
    }
}
