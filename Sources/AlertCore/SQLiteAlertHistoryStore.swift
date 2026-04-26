// WP-19a-4 · SQLite 版预警历史 Store
// 1 表 alert_history · conditionSnapshot 用 JSON（AlertCondition 是 Codable enum with associated values）

import Foundation
import Shared

public actor SQLiteAlertHistoryStore: AlertHistoryStore {

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
            CREATE TABLE IF NOT EXISTS alert_history (
              id TEXT PRIMARY KEY,
              alert_id TEXT NOT NULL,
              alert_name TEXT NOT NULL,
              instrument_id TEXT NOT NULL,
              condition_snapshot TEXT NOT NULL,
              triggered_at INTEGER NOT NULL,
              trigger_price TEXT NOT NULL,
              message TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_alert_history_alert ON alert_history(alert_id, triggered_at);
            CREATE INDEX IF NOT EXISTS idx_alert_history_ts ON alert_history(triggered_at);
            """)
        schemaReady = true
    }

    public func append(_ entry: AlertHistoryEntry) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            """
            INSERT INTO alert_history
            (id, alert_id, alert_name, instrument_id, condition_snapshot, triggered_at, trigger_price, message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bind: [
                .text(entry.id.uuidString),
                .text(entry.alertID.uuidString),
                .text(entry.alertName),
                .text(entry.instrumentID),
                .text(encodeJSON(entry.conditionSnapshot)),
                .integer(toMs(entry.triggeredAt)),
                .text(NSDecimalNumber(decimal: entry.triggerPrice).stringValue),
                .text(entry.message)
            ]
        )
    }

    public func history(forAlertID alertID: UUID) async throws -> [AlertHistoryEntry] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(historyColumns) FROM alert_history WHERE alert_id = ? ORDER BY triggered_at DESC;",
            bind: [.text(alertID.uuidString)]
        ) { decodeEntry(from: $0) }
    }

    public func allHistory() async throws -> [AlertHistoryEntry] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(historyColumns) FROM alert_history ORDER BY triggered_at DESC;"
        ) { decodeEntry(from: $0) }
    }

    public func history(from: Date, to: Date) async throws -> [AlertHistoryEntry] {
        guard from <= to else { return [] }
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(historyColumns) FROM alert_history WHERE triggered_at BETWEEN ? AND ? ORDER BY triggered_at DESC;",
            bind: [.integer(toMs(from)), .integer(toMs(to))]
        ) { decodeEntry(from: $0) }
    }

    public func clear(alertID: UUID) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            "DELETE FROM alert_history WHERE alert_id = ?;",
            bind: [.text(alertID.uuidString)]
        )
    }

    public func clearAll() async throws {
        try await ensureSchema()
        try await connection.exec("DELETE FROM alert_history;")
    }
}

// MARK: - 私有：解码

private let historyColumns = "id, alert_id, alert_name, instrument_id, condition_snapshot, triggered_at, trigger_price, message"

private func decodeEntry(from stmt: SQLiteStatement) -> AlertHistoryEntry {
    let condition: AlertCondition = decodeJSON(stmt.string(at: 4)) ?? .priceAbove(0)
    let triggerPrice = Decimal(string: stmt.string(at: 6) ?? "0") ?? 0

    return AlertHistoryEntry(
        id: UUID(uuidString: stmt.string(at: 0) ?? "") ?? UUID(),
        alertID: UUID(uuidString: stmt.string(at: 1) ?? "") ?? UUID(),
        alertName: stmt.string(at: 2) ?? "",
        instrumentID: stmt.string(at: 3) ?? "",
        conditionSnapshot: condition,
        triggeredAt: fromMs(stmt.int64(at: 5)),
        triggerPrice: triggerPrice,
        message: stmt.string(at: 7) ?? ""
    )
}

private func toMs(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
private func fromMs(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let str = String(data: data, encoding: .utf8) else { return "{}" }
    return str
}

private func decodeJSON<T: Decodable>(_ json: String?) -> T? {
    guard let json else { return nil }
    return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
}
