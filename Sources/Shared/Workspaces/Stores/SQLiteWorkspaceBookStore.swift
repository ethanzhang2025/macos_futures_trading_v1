// WP-19a-6 · SQLite 版 WorkspaceBook 持久化
// 单表 workspace_book · 固定 id=1 单例 · 整本 Book 序列化为 JSON 存 TEXT 列
// templates / windows / shortcut 全部随 Codable 链路嵌入

import Foundation

public actor SQLiteWorkspaceBookStore: WorkspaceBookStore {

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
            CREATE TABLE IF NOT EXISTS workspace_book (
              id INTEGER PRIMARY KEY CHECK(id = 1),
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            );
            """)
        schemaReady = true
    }

    public func load() async throws -> WorkspaceBook? {
        try await ensureSchema()
        let rows: [String?] = try await connection.query(
            "SELECT data FROM workspace_book WHERE id = 1;"
        ) { stmt in stmt.string(at: 0) }
        // 没数据 → nil；数据损坏 → 显式抛 decodeFailed（不静默吞数据，UI 层须感知）
        guard let json = rows.first.flatMap({ $0 }) else { return nil }
        guard let book: WorkspaceBook = decodeJSON(json) else {
            throw WorkspaceBookStoreError.decodeFailed
        }
        return book
    }

    public func save(_ book: WorkspaceBook) async throws {
        try await ensureSchema()
        guard let json = encodeJSON(book) else {
            throw WorkspaceBookStoreError.encodeFailed
        }
        let updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try await connection.executeReturningChanges(
            """
            INSERT INTO workspace_book (id, data, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at;
            """,
            bind: [.text(json), .integer(updatedAt)]
        )
    }

    public func clear() async throws {
        try await ensureSchema()
        try await connection.exec("DELETE FROM workspace_book;")
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
