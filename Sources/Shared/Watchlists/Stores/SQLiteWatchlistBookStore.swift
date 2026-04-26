// WP-19a-5 · SQLite 版 WatchlistBook 持久化
// 单表 watchlist_book · 固定 id=1 单例 · 整本 Book 序列化为 JSON 存 TEXT 列

import Foundation

public actor SQLiteWatchlistBookStore: WatchlistBookStore {

    private let connection: SQLiteConnection
    private var schemaReady = false

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    public func close() async {
        await connection.close()
    }

    private func ensureSchema() async throws {
        guard !schemaReady else { return }
        try await connection.exec("""
            CREATE TABLE IF NOT EXISTS watchlist_book (
              id INTEGER PRIMARY KEY CHECK(id = 1),
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            """)
        schemaReady = true
    }

    public func load() async throws -> WatchlistBook? {
        try await ensureSchema()
        let rows: [String?] = try await connection.query(
            "SELECT data FROM watchlist_book WHERE id = 1;"
        ) { stmt in stmt.string(at: 0) }
        // 没数据 → nil；数据损坏 → 显式抛 decodeFailed（不静默吞数据，UI 层须感知）
        guard let json = rows.first.flatMap({ $0 }) else { return nil }
        guard let book: WatchlistBook = decodeJSON(json) else {
            throw WatchlistBookStoreError.decodeFailed
        }
        return book
    }

    public func save(_ book: WatchlistBook) async throws {
        try await ensureSchema()
        guard let json = encodeJSON(book) else {
            throw WatchlistBookStoreError.encodeFailed
        }
        let updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try await connection.executeReturningChanges(
            """
            INSERT INTO watchlist_book (id, data, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at;
            """,
            bind: [.text(json), .integer(updatedAt)]
        )
    }

    public func clear() async throws {
        try await ensureSchema()
        try await connection.exec("DELETE FROM watchlist_book;")
    }
}

// MARK: - 私有 JSON helpers

private func encodeJSON<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeJSON<T: Decodable>(_ json: String?) -> T? {
    guard let json else { return nil }
    return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
}
