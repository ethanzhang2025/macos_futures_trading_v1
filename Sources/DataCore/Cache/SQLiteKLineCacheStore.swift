// WP-19a-2 · SQLite 版 K 线缓存
// 表 schema：复合主键 (instrument_id, period, open_time) → 自然去重 + 增量 append
// Decimal 字段以 TEXT 存（保留精度；SQLite 无原生 Decimal）

import Foundation
import Shared

public actor SQLiteKLineCacheStore: KLineCacheStore {

    private let connection: SQLiteConnection
    private var schemaReady = false

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    /// WP-19b v2 · 加密构造（passphrase 为 nil/空时行为同非加密 init）
    public init(path: String, passphrase: String?) throws {
        self.connection = try SQLiteConnection(path: path, passphrase: passphrase)
    }

    public func close() async {
        await connection.close()
    }

    private func ensureSchema() async throws {
        guard !schemaReady else { return }
        try await connection.exec("""
            CREATE TABLE IF NOT EXISTS klines (
              instrument_id TEXT NOT NULL,
              period TEXT NOT NULL,
              open_time INTEGER NOT NULL,
              open TEXT NOT NULL,
              high TEXT NOT NULL,
              low TEXT NOT NULL,
              close TEXT NOT NULL,
              volume INTEGER NOT NULL,
              open_interest TEXT NOT NULL,
              turnover TEXT NOT NULL,
              PRIMARY KEY (instrument_id, period, open_time)
            );
            CREATE INDEX IF NOT EXISTS idx_klines_query ON klines(instrument_id, period, open_time);
            """)
        schemaReady = true
    }

    // MARK: - KLineCacheStore 协议

    public func load(instrumentID: String, period: KLinePeriod) async throws -> [KLine] {
        try await ensureSchema()
        return try await connection.query(
            """
            SELECT open_time, open, high, low, close, volume, open_interest, turnover
            FROM klines WHERE instrument_id = ? AND period = ?
            ORDER BY open_time ASC;
            """,
            bind: [.text(instrumentID), .text(period.rawValue)]
        ) { stmt in
            decodeKLine(from: stmt, instrumentID: instrumentID, period: period)
        }
    }

    public func save(_ klines: [KLine], instrumentID: String, period: KLinePeriod) async throws {
        try await ensureSchema()
        try await withTransaction {
            try await self.connection.executeReturningChanges(
                "DELETE FROM klines WHERE instrument_id = ? AND period = ?;",
                bind: [.text(instrumentID), .text(period.rawValue)]
            )
            for k in klines {
                try await self.insertKLine(k, instrumentID: instrumentID, period: period)
            }
        }
    }

    public func append(_ klines: [KLine], instrumentID: String, period: KLinePeriod, maxBars: Int) async throws {
        try await ensureSchema()
        guard !klines.isEmpty else { return }
        try await withTransaction {
            for k in klines {
                try await self.insertKLine(k, instrumentID: instrumentID, period: period)
            }
        }
        if maxBars > 0 {
            try await trimToRecent(instrumentID: instrumentID, period: period, maxBars: maxBars)
        }
    }

    public func clear(instrumentID: String, period: KLinePeriod) async throws {
        try await ensureSchema()
        try await connection.executeReturningChanges(
            "DELETE FROM klines WHERE instrument_id = ? AND period = ?;",
            bind: [.text(instrumentID), .text(period.rawValue)]
        )
    }

    public func clearAll() async throws {
        try await ensureSchema()
        try await connection.exec("DELETE FROM klines;")
    }

    // MARK: - 私有

    /// INSERT OR REPLACE：openTime 重复时覆盖（与 InMemoryStore 去重语义一致）
    private func insertKLine(_ k: KLine, instrumentID: String, period: KLinePeriod) async throws {
        try await connection.executeReturningChanges(
            """
            INSERT OR REPLACE INTO klines
            (instrument_id, period, open_time, open, high, low, close, volume, open_interest, turnover)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bind: bindings(for: k, instrumentID: instrumentID, period: period)
        )
    }

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

    /// 截尾：仅保留最近 maxBars 根（按 open_time 降序，删多余）
    private func trimToRecent(instrumentID: String, period: KLinePeriod, maxBars: Int) async throws {
        try await connection.executeReturningChanges(
            """
            DELETE FROM klines
            WHERE instrument_id = ? AND period = ?
              AND open_time NOT IN (
                SELECT open_time FROM klines
                WHERE instrument_id = ? AND period = ?
                ORDER BY open_time DESC LIMIT ?
              );
            """,
            bind: [
                .text(instrumentID), .text(period.rawValue),
                .text(instrumentID), .text(period.rawValue),
                .integer(Int64(maxBars))
            ]
        )
    }
}

// MARK: - 私有：绑定 / 解码

/// 使用方法参数 instrumentID + period 而非 KLine 自身字段（与 InMemoryKLineCacheStore 行为一致：存储 key 由 caller 决定）
private func bindings(for k: KLine, instrumentID: String, period: KLinePeriod) -> [SQLiteValue] {
    [
        .text(instrumentID),
        .text(period.rawValue),
        .integer(Int64(k.openTime.timeIntervalSince1970 * 1000)),
        .text(decimalString(k.open)),
        .text(decimalString(k.high)),
        .text(decimalString(k.low)),
        .text(decimalString(k.close)),
        .integer(Int64(k.volume)),
        .text(decimalString(k.openInterest)),
        .text(decimalString(k.turnover))
    ]
}

private func decodeKLine(from stmt: SQLiteStatement, instrumentID: String, period: KLinePeriod) -> KLine {
    let openTimeMs = stmt.int64(at: 0)
    return KLine(
        instrumentID: instrumentID,
        period: period,
        openTime: Date(timeIntervalSince1970: TimeInterval(openTimeMs) / 1000),
        open: parseDecimal(stmt.string(at: 1)),
        high: parseDecimal(stmt.string(at: 2)),
        low: parseDecimal(stmt.string(at: 3)),
        close: parseDecimal(stmt.string(at: 4)),
        volume: stmt.int(at: 5),
        openInterest: parseDecimal(stmt.string(at: 6)),
        turnover: parseDecimal(stmt.string(at: 7))
    )
}

private func decimalString(_ d: Decimal) -> String {
    NSDecimalNumber(decimal: d).stringValue
}

private func parseDecimal(_ s: String?) -> Decimal {
    Decimal(string: s ?? "0") ?? 0
}
