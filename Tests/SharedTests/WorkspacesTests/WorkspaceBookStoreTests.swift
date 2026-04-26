// WP-19a-6 · WorkspaceBookStore 协议合约 + InMemory + SQLite 双实现等价测试

import Testing
import Foundation
@testable import Shared

private func makeSampleBook() -> WorkspaceBook {
    var book = WorkspaceBook()
    let pre = book.addTemplate(name: "盘前", kind: .preMarket)
    let inMkt = book.addTemplate(name: "盘中", kind: .inMarket)
    book.addTemplate(name: "盘后", kind: .postMarket)
    book.setActive(id: inMkt.id)

    // 给"盘前"加一个窗口 + 快捷键
    let layout = WindowLayout(
        instrumentID: "RB0",
        period: .minute1,
        indicatorIDs: [],
        drawingIDs: [],
        frame: LayoutFrame(x: 0, y: 0, width: 1, height: 1),
        zIndex: 0
    )
    var preTpl = book.template(id: pre.id)!
    preTpl.windows = [layout]
    book.updateTemplate(preTpl)
    book.setShortcut(WorkspaceShortcut(keyCode: 18, modifierFlags: 1 << 20), for: pre.id)
    return book
}

// MARK: - InMemory 协议合约

@Suite("InMemoryWorkspaceBookStore · 协议合约")
struct InMemoryWorkspaceBookStoreTests {

    @Test("空 store load → nil")
    func emptyLoad() async throws {
        let store = InMemoryWorkspaceBookStore()
        #expect(try await store.load() == nil)
    }

    @Test("save + load 完整往返（templates + windows + shortcut + activeTemplateID）")
    func saveLoadRoundTrip() async throws {
        let store = InMemoryWorkspaceBookStore()
        let book = makeSampleBook()
        try await store.save(book)
        let loaded = try await store.load()
        #expect(loaded == book)
    }

    @Test("save 整体覆盖")
    func saveOverwrites() async throws {
        let store = InMemoryWorkspaceBookStore()
        try await store.save(makeSampleBook())

        var book2 = WorkspaceBook()
        book2.addTemplate(name: "唯一", kind: .custom)
        try await store.save(book2)

        let loaded = try await store.load()
        #expect(loaded?.templates.count == 1)
        #expect(loaded?.templates.first?.kind == .custom)
    }

    @Test("clear → load nil")
    func clearRemoves() async throws {
        let store = InMemoryWorkspaceBookStore()
        try await store.save(makeSampleBook())
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("初始注入")
    func initialInjected() async throws {
        let book = makeSampleBook()
        let store = InMemoryWorkspaceBookStore(initial: book)
        #expect(try await store.load() == book)
    }
}

// MARK: - SQLite 实现等价

@Suite("SQLiteWorkspaceBookStore · 协议合约")
struct SQLiteWorkspaceBookStoreTests {

    @Test("空 store load → nil")
    func emptyLoad() async throws {
        let store = try SQLiteWorkspaceBookStore(path: ":memory:")
        #expect(try await store.load() == nil)
        await store.close()
    }

    @Test("save + load 完整 Codable 往返（templates + windows + shortcut）")
    func saveLoadRoundTrip() async throws {
        let store = try SQLiteWorkspaceBookStore(path: ":memory:")
        let book = makeSampleBook()
        try await store.save(book)
        let loaded = try await store.load()
        #expect(loaded == book)
        // 验证 activeTemplateID 也被持久化
        #expect(loaded?.activeTemplateID == book.activeTemplateID)
        await store.close()
    }

    @Test("二次 save UPSERT id=1 覆盖")
    func saveUpsertsSingleton() async throws {
        let store = try SQLiteWorkspaceBookStore(path: ":memory:")
        try await store.save(makeSampleBook())
        var book2 = WorkspaceBook()
        book2.addTemplate(name: "唯一", kind: .custom)
        try await store.save(book2)
        let loaded = try await store.load()
        #expect(loaded?.templates.count == 1)
        await store.close()
    }

    @Test("clear → load nil")
    func clearRemoves() async throws {
        let store = try SQLiteWorkspaceBookStore(path: ":memory:")
        try await store.save(makeSampleBook())
        try await store.clear()
        #expect(try await store.load() == nil)
        await store.close()
    }

    @Test("跨进程持久化（关闭再打开同 path）")
    func persistsAcrossReopen() async throws {
        let path = NSTemporaryDirectory().appending("wp_19a_6_test_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let book = makeSampleBook()
        do {
            let s1 = try SQLiteWorkspaceBookStore(path: path)
            try await s1.save(book)
            await s1.close()
        }
        let s2 = try SQLiteWorkspaceBookStore(path: path)
        let loaded = try await s2.load()
        #expect(loaded == book)
        await s2.close()
    }

    @Test("脏 JSON 显式抛 decodeFailed（不静默吞数据）")
    func corruptJSONThrows() async throws {
        let conn = try SQLiteConnection(path: ":memory:")
        try await conn.exec("""
            CREATE TABLE IF NOT EXISTS workspace_book (
              id INTEGER PRIMARY KEY CHECK(id = 1),
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            INSERT INTO workspace_book (id, data, updated_at) VALUES (1, 'corrupt}}}', 0);
            """)
        let store = SQLiteWorkspaceBookStore(connection: conn)
        await #expect(throws: WorkspaceBookStoreError.decodeFailed) {
            _ = try await store.load()
        }
        await store.close()
    }
}
