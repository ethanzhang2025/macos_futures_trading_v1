// WP-19a-3 · SQLite 版交易日志 Store
// 2 表：trades（明文）+ journals（加密层留 WP-19b SQLCipher · 现 v1 明文）
// JSON 序列化：tradeIDs / tags 数组字段；emotion / deviation 用 enum rawValue

import Foundation
import Shared

public actor SQLiteJournalStore: JournalStore {

    private let connection: SQLiteConnection
    private var schemaReady = false

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    /// WP-19b v2 · 加密构造（passphrase 为 nil/空时行为同非加密 init · M5 实盘前 journals 加密关键）
    public init(path: String, passphrase: String?) throws {
        self.connection = try SQLiteConnection(path: path, passphrase: passphrase)
    }

    public func close() async {
        await connection.close()
    }

    private func ensureSchema() async throws {
        guard !schemaReady else { return }
        try await connection.exec("""
            CREATE TABLE IF NOT EXISTS trades (
              id TEXT PRIMARY KEY,
              trade_reference TEXT NOT NULL,
              instrument_id TEXT NOT NULL,
              direction TEXT NOT NULL,
              offset_flag TEXT NOT NULL,
              price TEXT NOT NULL,
              volume INTEGER NOT NULL,
              commission TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              source TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_trades_instrument_ts ON trades(instrument_id, timestamp);
            CREATE INDEX IF NOT EXISTS idx_trades_ts ON trades(timestamp);

            CREATE TABLE IF NOT EXISTS journals (
              id TEXT PRIMARY KEY,
              trade_ids TEXT NOT NULL,
              title TEXT NOT NULL,
              reason TEXT NOT NULL,
              emotion TEXT NOT NULL,
              deviation TEXT NOT NULL,
              lesson TEXT NOT NULL,
              tags TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_journals_created ON journals(created_at);
            """)
        schemaReady = true
    }

    // MARK: - Trade

    public func saveTrades(_ trades: [Trade]) async throws {
        try await ensureSchema()
        guard !trades.isEmpty else { return }
        try await withTransaction {
            for t in trades {
                try await self.connection.executeReturningChanges(
                    """
                    INSERT OR REPLACE INTO trades
                    (id, trade_reference, instrument_id, direction, offset_flag, price, volume, commission, timestamp, source)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bind: bindings(for: t)
                )
            }
        }
    }

    public func loadAllTrades() async throws -> [Trade] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(tradeColumns) FROM trades ORDER BY timestamp ASC;"
        ) { decodeTrade(from: $0) }
    }

    public func loadTrades(forInstrumentID instrumentID: String) async throws -> [Trade] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(tradeColumns) FROM trades WHERE instrument_id = ? ORDER BY timestamp ASC;",
            bind: [.text(instrumentID)]
        ) { decodeTrade(from: $0) }
    }

    public func loadTrades(from: Date, to: Date) async throws -> [Trade] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(tradeColumns) FROM trades WHERE timestamp >= ? AND timestamp < ? ORDER BY timestamp ASC;",
            bind: [.integer(toMs(from)), .integer(toMs(to))]
        ) { decodeTrade(from: $0) }
    }

    public func deleteTrade(id: UUID) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            "DELETE FROM trades WHERE id = ?;",
            bind: [.text(id.uuidString)]
        )
    }

    // MARK: - Journal

    public func saveJournal(_ journal: TradeJournal) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            """
            INSERT OR REPLACE INTO journals
            (id, trade_ids, title, reason, emotion, deviation, lesson, tags, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bind: bindings(for: journal)
        )
    }

    public func loadAllJournals() async throws -> [TradeJournal] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(journalColumns) FROM journals ORDER BY created_at DESC;"
        ) { decodeJournal(from: $0) }
    }

    public func loadJournal(id: UUID) async throws -> TradeJournal? {
        try await ensureSchema()
        let rows = try await connection.query(
            "SELECT \(journalColumns) FROM journals WHERE id = ?;",
            bind: [.text(id.uuidString)]
        ) { decodeJournal(from: $0) }
        return rows.first
    }

    public func loadJournals(from: Date, to: Date) async throws -> [TradeJournal] {
        try await ensureSchema()
        return try await connection.query(
            "SELECT \(journalColumns) FROM journals WHERE created_at >= ? AND created_at < ? ORDER BY created_at DESC;",
            bind: [.integer(toMs(from)), .integer(toMs(to))]
        ) { decodeJournal(from: $0) }
    }

    public func loadJournals(withAnyTag tags: Set<String>) async throws -> [TradeJournal] {
        try await ensureSchema()
        guard !tags.isEmpty else { return [] }
        // Tag 是 JSON 数组字段，无法直接 SQL 过滤 → 加载全部 + Swift 端过滤
        // 后续优化：建独立 journal_tags 关联表
        let all = try await loadAllJournals()
        return all.filter { !$0.tags.isDisjoint(with: tags) }
    }

    public func deleteJournal(id: UUID) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            "DELETE FROM journals WHERE id = ?;",
            bind: [.text(id.uuidString)]
        )
    }

    // MARK: - 私有

    /// BEGIN/COMMIT 包装；body 抛错时自动 ROLLBACK 并重抛
    private func withTransaction(_ body: () async throws -> Void) async throws {
        try await connection.exec("BEGIN TRANSACTION;")
        do {
            try await body()
            try await connection.exec("COMMIT;")
        } catch {
            try? await connection.exec("ROLLBACK;")
            throw error
        }
    }
}

// MARK: - 私有：bind / decode

private let tradeColumns = "id, trade_reference, instrument_id, direction, offset_flag, price, volume, commission, timestamp, source"
private let journalColumns = "id, trade_ids, title, reason, emotion, deviation, lesson, tags, created_at, updated_at"

private func bindings(for t: Trade) -> [SQLiteValue] {
    [
        .text(t.id.uuidString),
        .text(t.tradeReference),
        .text(t.instrumentID),
        .text(t.direction.rawValue),
        .text(t.offsetFlag.rawValue),
        .text(decimalString(t.price)),
        .integer(Int64(t.volume)),
        .text(decimalString(t.commission)),
        .integer(toMs(t.timestamp)),
        .text(t.source.rawValue)
    ]
}

private func decodeTrade(from stmt: SQLiteStatement) -> Trade {
    Trade(
        id: UUID(uuidString: stmt.string(at: 0) ?? "") ?? UUID(),
        tradeReference: stmt.string(at: 1) ?? "",
        instrumentID: stmt.string(at: 2) ?? "",
        direction: Direction(rawValue: stmt.string(at: 3) ?? "") ?? .buy,
        offsetFlag: OffsetFlag(rawValue: stmt.string(at: 4) ?? "") ?? .open,
        price: parseDecimal(stmt.string(at: 5)),
        volume: stmt.int(at: 6),
        commission: parseDecimal(stmt.string(at: 7)),
        timestamp: fromMs(stmt.int64(at: 8)),
        source: TradeSource(rawValue: stmt.string(at: 9) ?? "") ?? .manual
    )
}

private func bindings(for j: TradeJournal) -> [SQLiteValue] {
    [
        .text(j.id.uuidString),
        .text(encodeJSON(j.tradeIDs.map { $0.uuidString })),
        .text(j.title),
        .text(j.reason),
        .text(j.emotion.rawValue),
        .text(j.deviation.rawValue),
        .text(j.lesson),
        .text(encodeJSON(Array(j.tags))),
        .integer(toMs(j.createdAt)),
        .integer(toMs(j.updatedAt))
    ]
}

private func decodeJournal(from stmt: SQLiteStatement) -> TradeJournal {
    let tradeIDStrings: [String] = decodeJSON(stmt.string(at: 1)) ?? []
    let tagsArray: [String] = decodeJSON(stmt.string(at: 7)) ?? []

    return TradeJournal(
        id: UUID(uuidString: stmt.string(at: 0) ?? "") ?? UUID(),
        tradeIDs: tradeIDStrings.compactMap(UUID.init),
        title: stmt.string(at: 2) ?? "",
        reason: stmt.string(at: 3) ?? "",
        emotion: JournalEmotion(rawValue: stmt.string(at: 4) ?? "") ?? .calm,
        deviation: JournalDeviation(rawValue: stmt.string(at: 5) ?? "") ?? .asPlanned,
        lesson: stmt.string(at: 6) ?? "",
        tags: Set(tagsArray),
        createdAt: fromMs(stmt.int64(at: 8)),
        updatedAt: fromMs(stmt.int64(at: 9))
    )
}

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let str = String(data: data, encoding: .utf8) else { return "[]" }
    return str
}

private func decodeJSON<T: Decodable>(_ json: String?) -> T? {
    guard let json else { return nil }
    return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func decimalString(_ d: Decimal) -> String { NSDecimalNumber(decimal: d).stringValue }
private func parseDecimal(_ s: String?) -> Decimal { Decimal(string: s ?? "0") ?? 0 }
private func toMs(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
private func fromMs(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
