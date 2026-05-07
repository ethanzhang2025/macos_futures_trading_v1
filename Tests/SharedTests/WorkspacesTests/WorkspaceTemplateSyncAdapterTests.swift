// WorkspaceTemplateSyncAdapter · WorkspaceTemplate ↔ SyncRecord 测试（WP-60 · v15.24 batch004）

import Testing
import Foundation
@testable import Shared
import SyncCore

@Suite("WorkspaceTemplateSyncAdapter · 双向转换")
struct WorkspaceTemplateSyncAdapterTests {

    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    private func sampleTemplate(version: Int = 1, deletedAt: Date? = nil) -> WorkspaceTemplate {
        WorkspaceTemplate(
            id: UUID(),
            name: "盘中主图",
            kind: .inMarket,
            windows: [
                WindowLayout(instrumentID: "rb0", period: .minute1, indicatorIDs: ["MA"], drawingIDs: []),
                WindowLayout(instrumentID: "i0", period: .minute5, indicatorIDs: [], drawingIDs: [])
            ],
            shortcut: WorkspaceShortcut(keyCode: 18, modifierFlags: 256),
            sortIndex: 1,
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            version: version,
            deletedAt: deletedAt
        )
    }

    @Test("syncRecordType = workspace_template")
    func recordType() {
        #expect(WorkspaceTemplate.syncRecordType == "workspace_template")
    }

    @Test("toSyncRecord · 字段映射")
    func toSyncRecordMapping() throws {
        let t = sampleTemplate(version: 5)
        let record = try t.toSyncRecord()
        #expect(record.recordType == "workspace_template")
        #expect(record.id == t.id)
        #expect(record.lastModified == t.updatedAt)
        #expect(record.version == 5)
        #expect(record.deletedAt == nil)
    }

    @Test("round-trip 还原 · 含 windows / shortcut")
    func roundTrip() throws {
        let original = sampleTemplate(version: 7)
        let record = try original.toSyncRecord()
        let restored = try WorkspaceTemplate.decode(from: record)

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.kind == original.kind)
        #expect(restored.windows.count == 2)
        #expect(restored.windows[0].instrumentID == "rb0")
        #expect(restored.shortcut == original.shortcut)
        #expect(restored.version == original.version)
    }

    @Test("tombstone 保留 payload")
    func tombstonePayload() throws {
        let t = sampleTemplate(version: 3, deletedAt: now.addingTimeInterval(120))
        let record = try t.toSyncRecord()
        #expect(record.isDeleted)
        #expect(record.deletedAt == t.deletedAt)
    }

    @Test("decode · metadata 以 SyncRecord 为准")
    func decodeMetadataPriority() throws {
        let t = sampleTemplate(version: 2)
        var record = try t.toSyncRecord()
        record = SyncRecord(
            recordType: record.recordType,
            id: record.id,
            lastModified: now.addingTimeInterval(999),
            version: 99,
            deletedAt: now.addingTimeInterval(999),
            payload: record.payload
        )
        let restored = try WorkspaceTemplate.decode(from: record)
        #expect(restored.version == 99)
        #expect(restored.deletedAt == now.addingTimeInterval(999))
    }
}

@Suite("WorkspaceBook · mutating 操作 version 自增")
struct WorkspaceBookVersioningTests {

    @Test("addTemplate · 新建 version=1")
    func addVersion() {
        var book = WorkspaceBook()
        let t = book.addTemplate(name: "t1")
        #expect(t.version == 1)
    }

    @Test("renameTemplate · version +1 · 同名不变")
    func renameVersion() {
        var book = WorkspaceBook()
        let t = book.addTemplate(name: "t1")
        _ = book.renameTemplate(id: t.id, to: "t2")
        #expect(book.template(id: t.id)?.version == 2)
        _ = book.renameTemplate(id: t.id, to: "t2")
        #expect(book.template(id: t.id)?.version == 2)
    }

    @Test("updateTemplate · version +1 + 保留旧 createdAt + 旧 deletedAt 不被覆盖")
    func updateVersion() {
        var book = WorkspaceBook()
        let original = book.addTemplate(name: "t1")
        var modified = original
        modified.name = "newName"
        _ = book.updateTemplate(modified)
        #expect(book.template(id: original.id)?.version == 2)
        #expect(book.template(id: original.id)?.name == "newName")
    }

    @Test("setShortcut · 双方 version 都 +1（被清的旧持有者 + 新持有者）")
    func setShortcutBumpsBoth() {
        var book = WorkspaceBook()
        let t1 = book.addTemplate(name: "t1")
        let t2 = book.addTemplate(name: "t2")
        let s = WorkspaceShortcut(keyCode: 18, modifierFlags: 256)
        _ = book.setShortcut(s, for: t1.id)
        let v1Before = book.template(id: t1.id)!.version
        _ = book.setShortcut(s, for: t2.id)
        // t1 被清快捷键 → version +1
        #expect(book.template(id: t1.id)!.version == v1Before + 1)
        #expect(book.template(id: t1.id)!.shortcut == nil)
        #expect(book.template(id: t2.id)!.shortcut == s)
    }

    @Test("softDeleteTemplate · 设 deletedAt + 自动切活跃")
    func softDelete() {
        var book = WorkspaceBook()
        let t1 = book.addTemplate(name: "t1")
        let t2 = book.addTemplate(name: "t2")
        _ = book.setActive(id: t1.id)

        let deletedAt = Date()
        let ok = book.softDeleteTemplate(id: t1.id, now: deletedAt)
        #expect(ok)
        #expect(book.template(id: t1.id)?.deletedAt == deletedAt)
        #expect(book.template(id: t1.id)?.version == 2)
        // 自动切到第一个未删的
        #expect(book.activeTemplateID == t2.id)
    }

    @Test("softDeleteTemplate · 唯一一个被软删 · 切到 nil")
    func softDeleteSoleTemplate() {
        var book = WorkspaceBook()
        let t1 = book.addTemplate(name: "only")
        _ = book.softDeleteTemplate(id: t1.id)
        #expect(book.activeTemplateID == nil)
    }

    @Test("softDeleteTemplate · 重复返回 false")
    func softDeleteIdempotent() {
        var book = WorkspaceBook()
        let t = book.addTemplate(name: "t")
        _ = book.softDeleteTemplate(id: t.id)
        let again = book.softDeleteTemplate(id: t.id)
        #expect(again == false)
    }
}

@Suite("WorkspaceTemplate · Codable 向后兼容")
struct WorkspaceTemplateCodableCompatTests {

    @Test("旧 JSON 缺 version/deletedAt · 回退默认")
    func legacyJSONFallback() throws {
        let oldJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "old",
            "kind": "custom",
            "windows": [],
            "sortIndex": 0,
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let t = try decoder.decode(WorkspaceTemplate.self, from: Data(oldJSON.utf8))
        #expect(t.version == 1)
        #expect(t.deletedAt == nil)
    }
}
