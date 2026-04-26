// WP-19a-5 · WatchlistBookStore 协议合约 + InMemory + SQLite 双实现等价测试

import Testing
import Foundation
@testable import Shared

private func makeSampleBook() -> WatchlistBook {
    var book = WatchlistBook()
    let core = book.addGroup(name: "核心持仓")
    let alt = book.addGroup(name: "备选")
    book.addInstrument("RB0", to: core.id)
    book.addInstrument("IF0", to: core.id)
    book.addInstrument("AU0", to: core.id)
    book.addInstrument("CU0", to: alt.id)
    return book
}

// MARK: - InMemory 协议合约

@Suite("InMemoryWatchlistBookStore · 协议合约")
struct InMemoryWatchlistBookStoreTests {

    @Test("空 store load → nil")
    func emptyLoad() async throws {
        let store = InMemoryWatchlistBookStore()
        #expect(try await store.load() == nil)
    }

    @Test("save 后 load 完整往返（多分组多合约）")
    func saveLoadRoundTrip() async throws {
        let store = InMemoryWatchlistBookStore()
        let book = makeSampleBook()
        try await store.save(book)
        let loaded = try await store.load()
        #expect(loaded == book)
    }

    @Test("二次 save 整体覆盖")
    func saveOverwrites() async throws {
        let store = InMemoryWatchlistBookStore()
        try await store.save(makeSampleBook())

        var book2 = WatchlistBook()
        book2.addGroup(name: "新主簿")
        try await store.save(book2)

        let loaded = try await store.load()
        #expect(loaded?.groups.count == 1)
        #expect(loaded?.groups.first?.name == "新主簿")
    }

    @Test("clear 后 load → nil")
    func clearRemoves() async throws {
        let store = InMemoryWatchlistBookStore()
        try await store.save(makeSampleBook())
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("初始注入：构造时设 initial")
    func initialInjected() async throws {
        let book = makeSampleBook()
        let store = InMemoryWatchlistBookStore(initial: book)
        #expect(try await store.load() == book)
    }
}

// MARK: - SQLite 实现等价

@Suite("SQLiteWatchlistBookStore · 协议合约")
struct SQLiteWatchlistBookStoreTests {

    @Test("空 store load → nil")
    func emptyLoad() async throws {
        let store = try SQLiteWatchlistBookStore(path: ":memory:")
        #expect(try await store.load() == nil)
        await store.close()
    }

    @Test("save + load 完整 Codable 往返")
    func saveLoadRoundTrip() async throws {
        let store = try SQLiteWatchlistBookStore(path: ":memory:")
        let book = makeSampleBook()
        try await store.save(book)
        let loaded = try await store.load()
        #expect(loaded == book)
        await store.close()
    }

    @Test("二次 save UPSERT id=1 覆盖")
    func saveUpsertsSingleton() async throws {
        let store = try SQLiteWatchlistBookStore(path: ":memory:")
        try await store.save(makeSampleBook())
        var book2 = WatchlistBook()
        book2.addGroup(name: "唯一簿")
        book2.addGroup(name: "第二簿")
        try await store.save(book2)
        let loaded = try await store.load()
        #expect(loaded?.groups.count == 2)
        #expect(loaded?.groups.first?.name == "唯一簿")
        await store.close()
    }

    @Test("clear → load nil")
    func clearRemoves() async throws {
        let store = try SQLiteWatchlistBookStore(path: ":memory:")
        try await store.save(makeSampleBook())
        try await store.clear()
        #expect(try await store.load() == nil)
        await store.close()
    }

    @Test("跨进程持久化（关闭再打开同 path）")
    func persistsAcrossReopen() async throws {
        let path = NSTemporaryDirectory().appending("wp_19a_5_test_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let book = makeSampleBook()
        do {
            let s1 = try SQLiteWatchlistBookStore(path: path)
            try await s1.save(book)
            await s1.close()
        }
        let s2 = try SQLiteWatchlistBookStore(path: path)
        let loaded = try await s2.load()
        #expect(loaded == book)
        await s2.close()
    }

    @Test("同 connection 注入构造")
    func initWithConnection() async throws {
        let conn = try SQLiteConnection(path: ":memory:")
        let store = SQLiteWatchlistBookStore(connection: conn)
        try await store.save(makeSampleBook())
        #expect(try await store.load() != nil)
        await store.close()
    }

    @Test("脏 JSON 显式抛 decodeFailed（不静默吞数据）")
    func corruptJSONThrows() async throws {
        let conn = try SQLiteConnection(path: ":memory:")
        // 直接写入脏 JSON 模拟磁盘损坏 / 旧 schema
        try await conn.exec("""
            CREATE TABLE IF NOT EXISTS watchlist_book (
              id INTEGER PRIMARY KEY CHECK(id = 1),
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            INSERT INTO watchlist_book (id, data, updated_at) VALUES (1, 'not-valid-json{{{', 0);
            """)
        let store = SQLiteWatchlistBookStore(connection: conn)
        await #expect(throws: WatchlistBookStoreError.decodeFailed) {
            _ = try await store.load()
        }
        await store.close()
    }
}
