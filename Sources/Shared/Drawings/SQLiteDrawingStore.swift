// WP-42 v13.2 · SQLite 版 Drawing 持久化（按 instrumentID + period 复合主键）
// 与 SQLiteWatchlistBookStore（id=1 单聚合根）不同 · 此处为 (instrument_id, period) 双列主键

import Foundation

public actor SQLiteDrawingStore: DrawingStore {

    private let connection: SQLiteConnection
    private var schemaReady = false

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    public init(path: String, passphrase: String?) throws {
        self.connection = try SQLiteConnection(path: path, passphrase: passphrase)
    }

    public func close() async {
        await connection.close()
    }

    private func ensureSchema() async throws {
        guard !schemaReady else { return }
        try await connection.exec("""
            CREATE TABLE IF NOT EXISTS drawings_book (
              instrument_id TEXT NOT NULL,
              period TEXT NOT NULL,
              data TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (instrument_id, period)
            );
            """)
        schemaReady = true
    }

    public func load(instrumentID: String, period: KLinePeriod) async throws -> [Drawing] {
        try await ensureSchema()
        let rows: [String?] = try await connection.query(
            "SELECT data FROM drawings_book WHERE instrument_id = ? AND period = ?;",
            bind: [.text(instrumentID), .text(period.rawValue)]
        ) { stmt in stmt.string(at: 0) }
        guard let json = rows.first.flatMap({ $0 }) else { return [] }
        guard let drawings: [Drawing] = decodeDrawingsJSON(json) else {
            throw DrawingStoreError.decodeFailed
        }
        return drawings
    }

    public func save(_ drawings: [Drawing], instrumentID: String, period: KLinePeriod) async throws {
        try await ensureSchema()
        guard let json = encodeDrawingsJSON(drawings) else {
            throw DrawingStoreError.encodeFailed
        }
        let updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        try await connection.executeReturningChanges(
            """
            INSERT INTO drawings_book (instrument_id, period, data, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(instrument_id, period) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at;
            """,
            bind: [.text(instrumentID), .text(period.rawValue), .text(json), .integer(updatedAt)]
        )
    }

    public func clear(instrumentID: String, period: KLinePeriod) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            "DELETE FROM drawings_book WHERE instrument_id = ? AND period = ?;",
            bind: [.text(instrumentID), .text(period.rawValue)]
        )
    }

    public func clearAll() async throws {
        try await ensureSchema()
        try await connection.exec("DELETE FROM drawings_book;")
    }
}

// MARK: - JSON helpers

private func encodeDrawingsJSON(_ drawings: [Drawing]) -> String? {
    guard let data = try? JSONEncoder().encode(drawings) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func decodeDrawingsJSON(_ json: String) -> [Drawing]? {
    try? JSONDecoder().decode([Drawing].self, from: Data(json.utf8))
}
