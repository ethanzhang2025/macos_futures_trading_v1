// WP-55 · 工作区模板 v1 测试
// WindowLayout / WorkspaceTemplate / WorkspaceBook · CRUD / 复制 / 切换 / 快捷键唯一 / 边界 / Codable / CloudKit

import Testing
import Foundation
@testable import Shared

// MARK: - 测试辅助

private func makeWindow(
    _ instrumentID: String = "rb2510",
    period: KLinePeriod = .minute5,
    indicators: [String] = ["MA", "MACD"]
) -> WindowLayout {
    WindowLayout(
        instrumentID: instrumentID,
        period: period,
        indicatorIDs: indicators,
        frame: LayoutFrame(x: 0, y: 0, width: 800, height: 600)
    )
}

private func makeBook(templateNames: [String] = []) -> WorkspaceBook {
    var book = WorkspaceBook()
    for name in templateNames { book.addTemplate(name: name) }
    return book
}

// MARK: - 1. LayoutFrame / KLinePeriod Codable

@Suite("LayoutFrame & KLinePeriod Codable")
struct LayoutFrameAndPeriodTests {

    @Test("LayoutFrame.zero 与初始化")
    func layoutFrameInit() {
        #expect(LayoutFrame.zero == LayoutFrame(x: 0, y: 0, width: 0, height: 0))
        let f = LayoutFrame(x: 10, y: 20, width: 800, height: 600)
        #expect(f.x == 10 && f.y == 20 && f.width == 800 && f.height == 600)
    }

    @Test("KLinePeriod Codable 往返（rawValue）")
    func periodCodable() throws {
        let original: [KLinePeriod] = [.minute1, .minute5, .hour1, .daily, .weekly]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([KLinePeriod].self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - 2. WindowLayout

@Suite("WindowLayout · 数据契约")
struct WindowLayoutTests {

    @Test("默认值与必填字段")
    func windowDefaults() {
        let w = WindowLayout(instrumentID: "rb2510", period: .minute5)
        #expect(w.indicatorIDs.isEmpty)
        #expect(w.drawingIDs.isEmpty)
        #expect(w.frame == .zero)
        #expect(w.zIndex == 0)
    }

    @Test("Codable JSON 往返")
    func windowCodable() throws {
        let original = makeWindow("hc2510", period: .hour1, indicators: ["MA", "BOLL"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(WindowLayout.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - 3. WorkspaceTemplate

@Suite("WorkspaceTemplate · 数据契约")
struct WorkspaceTemplateTests {

    @Test("4 种 Kind 全枚举")
    func kindAllCases() {
        #expect(WorkspaceTemplate.Kind.allCases.count == 4)
        #expect(Set(WorkspaceTemplate.Kind.allCases.map(\.rawValue))
                == Set(["preMarket", "inMarket", "postMarket", "custom"]))
    }

    @Test("默认 kind=custom，shortcut=nil")
    func templateDefaults() {
        let t = WorkspaceTemplate(name: "我的工作区")
        #expect(t.kind == .custom)
        #expect(t.shortcut == nil)
        #expect(t.windows.isEmpty)
    }
}

// MARK: - 4. WorkspaceBook · 模板 CRUD

@Suite("WorkspaceBook · 模板 CRUD")
struct WorkspaceBookCRUDTests {

    @Test("addTemplate 自动 sortIndex 与首个自动激活")
    func addTemplateAutoActivate() {
        var book = WorkspaceBook()
        let t1 = book.addTemplate(name: "盘前", kind: .preMarket)
        let t2 = book.addTemplate(name: "盘中", kind: .inMarket)
        let t3 = book.addTemplate(name: "盘后", kind: .postMarket)

        #expect(book.templates.count == 3)
        #expect(book.templates.map(\.sortIndex) == [0, 1, 2])
        #expect(book.activeTemplateID == t1.id)
        #expect(t2.kind == .inMarket && t3.kind == .postMarket)
    }

    @Test("renameTemplate 命中与不命中")
    func renameTemplate() {
        var book = makeBook(templateNames: ["A"])
        let id = book.templates[0].id

        let hit = book.renameTemplate(id: id, to: "已改名")
        let miss = book.renameTemplate(id: UUID(), to: "X")

        #expect(hit)
        #expect(book.templates[0].name == "已改名")
        #expect(!miss)
    }

    @Test("removeTemplate 自动重排 sortIndex + 激活切换")
    func removeTemplateActiveFallback() {
        var book = makeBook(templateNames: ["A", "B", "C"])
        let aID = book.templates[0].id
        let bID = book.templates[1].id

        // A 被激活（首个），删 A 后激活切到 B
        let removed = book.removeTemplate(id: aID)
        #expect(removed)
        #expect(book.templates.map(\.name) == ["B", "C"])
        #expect(book.templates.map(\.sortIndex) == [0, 1])
        #expect(book.activeTemplateID == bID)
    }

    @Test("removeTemplate 删空后 active=nil")
    func removeAllTemplatesNilsActive() {
        var book = makeBook(templateNames: ["A"])
        let aID = book.templates[0].id
        let r = book.removeTemplate(id: aID)
        #expect(r)
        #expect(book.activeTemplateID == nil)
    }

    @Test("duplicateTemplate 深拷贝 windows + 不复制快捷键 + 默认副本名")
    func duplicateTemplate() {
        var book = WorkspaceBook()
        let original = book.addTemplate(
            name: "盘中",
            kind: .inMarket,
            windows: [makeWindow("rb2510"), makeWindow("hc2510")],
            shortcut: WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)
        )

        let copy = book.duplicateTemplate(id: original.id)
        let c = try! #require(copy)
        #expect(c.id != original.id)
        #expect(c.name == "盘中 副本")
        #expect(c.kind == original.kind)
        #expect(c.windows.count == 2)
        #expect(c.windows[0].id != original.windows[0].id)
        #expect(c.windows[0].instrumentID == "rb2510")
        #expect(c.shortcut == nil)
    }

    @Test("duplicateTemplate 自定义副本名 + 不存在返回 nil")
    func duplicateTemplateCustomName() {
        var book = makeBook(templateNames: ["A"])
        let id = book.templates[0].id

        let copy = book.duplicateTemplate(id: id, newName: "AA")
        #expect(copy?.name == "AA")
        #expect(book.duplicateTemplate(id: UUID()) == nil)
    }

    @Test("moveTemplate 拖拽排序")
    func moveTemplate() {
        var book = makeBook(templateNames: ["A", "B", "C", "D"])
        let r = book.moveTemplate(from: 0, to: 3)
        #expect(r)
        #expect(book.templates.map(\.name) == ["B", "C", "A", "D"])
        #expect(book.templates.map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test("moveTemplate 边界")
    func moveTemplateEdge() {
        var book = makeBook(templateNames: ["A", "B"])
        let same = book.moveTemplate(from: 0, to: 0)
        let oob = book.moveTemplate(from: 5, to: 0)
        #expect(!same)
        #expect(!oob)
    }

    @Test("updateTemplate 整模板覆盖：保留 sortIndex/createdAt，刷新 updatedAt")
    func updateTemplate() {
        var book = makeBook(templateNames: ["A"])
        let original = book.templates[0]
        let originalCreated = original.createdAt
        let originalSort = original.sortIndex

        let later = originalCreated.addingTimeInterval(60)
        let modified = WorkspaceTemplate(
            id: original.id,
            name: "覆盖",
            kind: .inMarket,
            windows: [makeWindow()],
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast
        )
        let r = book.updateTemplate(modified, now: later)
        #expect(r)
        #expect(book.templates[0].name == "覆盖")
        #expect(book.templates[0].kind == .inMarket)
        #expect(book.templates[0].windows.count == 1)
        #expect(book.templates[0].sortIndex == originalSort)
        #expect(book.templates[0].createdAt == originalCreated)
        #expect(book.templates[0].updatedAt == later)
    }
}

// MARK: - 5. WorkspaceBook · 切换激活

@Suite("WorkspaceBook · 激活切换")
struct WorkspaceActiveSwitchTests {

    @Test("setActive 命中、清除、不存在")
    func setActive() {
        var book = makeBook(templateNames: ["A", "B"])
        let bID = book.templates[1].id

        let toB = book.setActive(id: bID)
        let toMiss = book.setActive(id: UUID())
        let toNil = book.setActive(id: nil)

        #expect(toB)
        #expect(!toMiss)
        #expect(toNil)
        #expect(book.activeTemplateID == nil)
    }

    @Test("activeTemplate 计算属性跟踪 activeTemplateID")
    func activeTemplateProperty() {
        var book = makeBook(templateNames: ["A", "B"])
        let bID = book.templates[1].id

        // 默认 active 是首个 A
        #expect(book.activeTemplate?.name == "A")

        let _ = book.setActive(id: bID)
        #expect(book.activeTemplate?.id == bID)
        #expect(book.activeTemplate?.name == "B")

        let _ = book.setActive(id: nil)
        #expect(book.activeTemplate == nil)
    }

    @Test("init 时活跃 ID 不存在则置空")
    func initInvalidActiveNilsOut() {
        let invalidID = UUID()
        let t = WorkspaceTemplate(name: "A")
        let book = WorkspaceBook(templates: [t], activeTemplateID: invalidID)
        #expect(book.activeTemplateID == nil)
    }
}

// MARK: - 6. WorkspaceBook · 快捷键

@Suite("WorkspaceBook · 快捷键")
struct WorkspaceShortcutTests {

    @Test("setShortcut 设置后可按快捷键查询")
    func setShortcutAndLookup() {
        var book = makeBook(templateNames: ["A", "B"])
        let aID = book.templates[0].id
        let cmd1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)

        let r = book.setShortcut(cmd1, for: aID)
        #expect(r)
        #expect(book.template(forShortcut: cmd1)?.id == aID)
    }

    @Test("setShortcut 全局唯一：B 抢占 A 的快捷键，A 被清空")
    func setShortcutGlobalUnique() {
        var book = makeBook(templateNames: ["A", "B"])
        let aID = book.templates[0].id
        let bID = book.templates[1].id
        let cmd1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)

        let r1 = book.setShortcut(cmd1, for: aID)
        let r2 = book.setShortcut(cmd1, for: bID)
        #expect(r1)
        #expect(r2)

        #expect(book.template(id: aID)?.shortcut == nil)
        #expect(book.template(id: bID)?.shortcut == cmd1)
        #expect(book.template(forShortcut: cmd1)?.id == bID)
    }

    @Test("清除快捷键（设为 nil）")
    func clearShortcut() {
        var book = makeBook(templateNames: ["A"])
        let aID = book.templates[0].id
        let cmd1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)

        let _ = book.setShortcut(cmd1, for: aID)
        let cleared = book.setShortcut(nil, for: aID)
        #expect(cleared)
        #expect(book.template(id: aID)?.shortcut == nil)
        #expect(book.template(forShortcut: cmd1) == nil)
    }
}

// MARK: - 7. WorkspaceBook · 查询

@Suite("WorkspaceBook · 查询")
struct WorkspaceQueryTests {

    @Test("templates(of:) 按 Kind 筛选")
    func templatesOfKind() {
        var book = WorkspaceBook()
        book.addTemplate(name: "盘前1", kind: .preMarket)
        book.addTemplate(name: "盘中1", kind: .inMarket)
        book.addTemplate(name: "盘中2", kind: .inMarket)
        book.addTemplate(name: "自定义", kind: .custom)

        #expect(book.templates(of: .preMarket).count == 1)
        #expect(book.templates(of: .inMarket).count == 2)
        #expect(book.templates(of: .postMarket).isEmpty)
        #expect(book.templates(of: .custom).count == 1)
    }
}

// MARK: - 8. Codable 往返

@Suite("WorkspaceBook · Codable 往返")
struct WorkspaceCodableTests {

    @Test("WorkspaceBook JSON 编解码（含 windows + shortcut + active）")
    func bookCodableRoundTrip() throws {
        var book = WorkspaceBook()
        let t1 = book.addTemplate(
            name: "盘中",
            kind: .inMarket,
            windows: [makeWindow("rb2510"), makeWindow("hc2510", period: .hour1)],
            shortcut: WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)
        )
        book.addTemplate(name: "盘后", kind: .postMarket)
        let _ = book.setActive(id: t1.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(book)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceBook.self, from: data)

        #expect(decoded.templates.count == 2)
        #expect(decoded.templates[0].windows.count == 2)
        #expect(decoded.templates[0].windows[1].period == .hour1)
        #expect(decoded.templates[0].shortcut?.keyCode == 18)
        #expect(decoded.activeTemplateID == t1.id)
    }
}

// MARK: - 9. CloudKit 字段映射预埋

@Suite("WorkspaceTemplate · CloudKit 字段映射")
struct WorkspaceCloudKitTests {

    @Test("cloudKitRecordType 与字段名常量")
    func recordTypeAndFieldNames() {
        #expect(WorkspaceTemplate.cloudKitRecordType == "WorkspaceTemplate")
        #expect(WorkspaceTemplate.CloudKitField.name == "name")
        #expect(WorkspaceTemplate.CloudKitField.kind == "kind")
        #expect(WorkspaceTemplate.CloudKitField.windowsJSON == "windowsJSON")
    }

    @Test("cloudKitFields 输出类型符合 CKRecord 规范（含 windows JSON 嵌入）")
    func cloudKitFieldsTypes() throws {
        let now = Date()
        let template = WorkspaceTemplate(
            name: "盘中",
            kind: .inMarket,
            windows: [makeWindow("rb2510")],
            shortcut: WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000),
            sortIndex: 1,
            createdAt: now,
            updatedAt: now
        )
        let fields = try template.cloudKitFields()

        #expect(fields[WorkspaceTemplate.CloudKitField.name] as? String == "盘中")
        #expect(fields[WorkspaceTemplate.CloudKitField.kind] as? String == "inMarket")
        #expect(fields[WorkspaceTemplate.CloudKitField.sortIndex] as? Int64 == 1)
        #expect(fields[WorkspaceTemplate.CloudKitField.shortcutKeyCode] as? Int64 == 18)
        #expect(fields[WorkspaceTemplate.CloudKitField.shortcutModifiers] as? Int64 == 0x100000)
        let json = try #require(fields[WorkspaceTemplate.CloudKitField.windowsJSON] as? String)
        #expect(json.contains("rb2510"))
    }

    @Test("cloudKitFields → init?(cloudKitRecordName:fields:) 往返")
    func cloudKitRoundTrip() throws {
        let now = Date()
        let original = WorkspaceTemplate(
            name: "盘前",
            kind: .preMarket,
            windows: [makeWindow("rb2510"), makeWindow("hc2510", period: .daily)],
            shortcut: WorkspaceShortcut(keyCode: 19, modifierFlags: 0x100000),
            sortIndex: 0,
            createdAt: now,
            updatedAt: now
        )
        let recordName = original.cloudKitRecordName
        let fields = try original.cloudKitFields()

        let bridged: [String: Any] = fields.mapValues { $0 as Any }
        let restored = try #require(WorkspaceTemplate(cloudKitRecordName: recordName, fields: bridged))

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.kind == original.kind)
        #expect(restored.windows.count == 2)
        #expect(restored.windows[1].period == .daily)
        #expect(restored.shortcut?.keyCode == 19)
        #expect(restored.sortIndex == original.sortIndex)
    }

    @Test("init? 兼容 Int 类型字段（CloudKit Int64 vs 本地 Int 兜底）")
    func cloudKitIntFallback() throws {
        let now = Date()
        let id = UUID()
        let windows: [WindowLayout] = []
        let windowsData = try JSONEncoder.cloudKit.encode(windows)
        let windowsJSON = String(decoding: windowsData, as: UTF8.self)

        let fields: [String: Any] = [
            WorkspaceTemplate.CloudKitField.name: "测试",
            WorkspaceTemplate.CloudKitField.kind: "custom",
            WorkspaceTemplate.CloudKitField.sortIndex: 5,
            WorkspaceTemplate.CloudKitField.shortcutKeyCode: 18,
            WorkspaceTemplate.CloudKitField.shortcutModifiers: 0x100000,
            WorkspaceTemplate.CloudKitField.createdAt: now,
            WorkspaceTemplate.CloudKitField.updatedAt: now,
            WorkspaceTemplate.CloudKitField.windowsJSON: windowsJSON,
        ]
        let restored = try #require(WorkspaceTemplate(cloudKitRecordName: id.uuidString, fields: fields))
        #expect(restored.sortIndex == 5)
        #expect(restored.shortcut?.keyCode == 18)
    }

    @Test("init? 必填字段缺失返回 nil")
    func cloudKitInitMissingRequired() {
        let id = UUID().uuidString
        let now = Date()

        // 缺 windowsJSON
        #expect(WorkspaceTemplate(cloudKitRecordName: id, fields: [
            WorkspaceTemplate.CloudKitField.name: "X",
            WorkspaceTemplate.CloudKitField.kind: "custom",
            WorkspaceTemplate.CloudKitField.createdAt: now,
            WorkspaceTemplate.CloudKitField.updatedAt: now,
        ]) == nil)

        // kind 非法
        #expect(WorkspaceTemplate(cloudKitRecordName: id, fields: [
            WorkspaceTemplate.CloudKitField.name: "X",
            WorkspaceTemplate.CloudKitField.kind: "not-a-kind",
            WorkspaceTemplate.CloudKitField.createdAt: now,
            WorkspaceTemplate.CloudKitField.updatedAt: now,
            WorkspaceTemplate.CloudKitField.windowsJSON: "[]",
        ]) == nil)

        // recordName 非 UUID
        #expect(WorkspaceTemplate(cloudKitRecordName: "not-uuid", fields: [
            WorkspaceTemplate.CloudKitField.name: "X",
            WorkspaceTemplate.CloudKitField.kind: "custom",
            WorkspaceTemplate.CloudKitField.createdAt: now,
            WorkspaceTemplate.CloudKitField.updatedAt: now,
            WorkspaceTemplate.CloudKitField.windowsJSON: "[]",
        ]) == nil)
    }

    @Test("init? shortcut 缺失字段时回退 nil")
    func cloudKitShortcutFallback() throws {
        let now = Date()
        let id = UUID().uuidString
        let restored = try #require(WorkspaceTemplate(cloudKitRecordName: id, fields: [
            WorkspaceTemplate.CloudKitField.name: "X",
            WorkspaceTemplate.CloudKitField.kind: "custom",
            WorkspaceTemplate.CloudKitField.createdAt: now,
            WorkspaceTemplate.CloudKitField.updatedAt: now,
            WorkspaceTemplate.CloudKitField.windowsJSON: "[]",
        ]))
        #expect(restored.shortcut == nil)
        #expect(restored.windows.isEmpty)
    }
}
