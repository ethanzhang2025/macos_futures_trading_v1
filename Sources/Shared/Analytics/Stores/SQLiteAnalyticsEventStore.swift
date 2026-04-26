// WP-19a · SQLite 版埋点 Store
// 表 schema 与 StageA-补遗 G2 §SQLite 表结构一致
// 优于 JSONFile：增量写入 / 索引查询 / 容量大（10w+ 条）/ 后续 SQLCipher 加密替换

import Foundation

public actor SQLiteAnalyticsEventStore: AnalyticsEventStore {

    private let connection: SQLiteConnection
    private var schemaReady = false

    /// - Parameter connection: 已打开的 SQLite 连接（caller 负责 close 生命周期）
    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// 便利构造：自建连接（caller 不复用 db file）
    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    /// WP-19b v2 · 加密构造（passphrase 为 nil/空时行为同非加密 init）
    public init(path: String, passphrase: String?) throws {
        self.connection = try SQLiteConnection(path: path, passphrase: passphrase)
    }

    /// 关闭底层连接 · Swift 6 deinit 不能访问 actor 状态，需显式 close
    public func close() async {
        await connection.close()
    }

    // MARK: - schema migration（懒初始化）

    private func ensureSchema() async throws {
        guard !schemaReady else { return }
        try await connection.exec("""
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              session_id TEXT,
              event_name TEXT NOT NULL,
              event_ts INTEGER NOT NULL,
              props_json TEXT,
              app_version TEXT,
              uploaded INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_events_uploaded_ts ON events(uploaded, event_ts);
            """)
        schemaReady = true
    }

    // MARK: - AnalyticsEventStore 协议

    @discardableResult
    public func append(_ event: AnalyticsEvent) async throws -> Int64 {
        try await ensureSchema()
        return try await connection.executeReturningRowID(
            """
            INSERT INTO events (user_id, device_id, session_id, event_name, event_ts, props_json, app_version, uploaded)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bind: bindings(for: event)
        )
    }

    @discardableResult
    public func appendBatch(_ events: [AnalyticsEvent]) async throws -> [Int64] {
        try await ensureSchema()
        guard !events.isEmpty else { return [] }
        try await connection.exec("BEGIN TRANSACTION;")
        var ids: [Int64] = []
        ids.reserveCapacity(events.count)
        do {
            for event in events {
                let id = try await connection.executeReturningRowID(
                    """
                    INSERT INTO events (user_id, device_id, session_id, event_name, event_ts, props_json, app_version, uploaded)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bind: bindings(for: event)
                )
                ids.append(id)
            }
            try await connection.exec("COMMIT;")
            return ids
        } catch {
            try? await connection.exec("ROLLBACK;")
            throw error
        }
    }

    public func queryPending(limit: Int) async throws -> [AnalyticsEvent] {
        try await ensureSchema()
        let sql = limit > 0
            ? "SELECT id, user_id, device_id, session_id, event_name, event_ts, props_json, app_version, uploaded FROM events WHERE uploaded = 0 ORDER BY event_ts ASC LIMIT ?;"
            : "SELECT id, user_id, device_id, session_id, event_name, event_ts, props_json, app_version, uploaded FROM events WHERE uploaded = 0 ORDER BY event_ts ASC;"
        let bindValues: [SQLiteValue] = limit > 0 ? [.integer(Int64(limit))] : []
        return try await connection.query(sql, bind: bindValues) { stmt in
            decodeEvent(from: stmt)
        }
    }

    public func markUploaded(ids: [Int64]) async throws {
        try await ensureSchema()
        guard !ids.isEmpty else { return }
        // SQLite 不支持 IN 数组绑定 → 拼 placeholder
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "UPDATE events SET uploaded = 1 WHERE id IN (\(placeholders));"
        let bindValues = ids.map { SQLiteValue.integer($0) }
        try await connection.executeReturningChanges(sql, bind: bindValues)
    }

    @discardableResult
    public func cleanupUploaded(beforeTimestampMs: Int64) async throws -> Int {
        try await ensureSchema()
        return try await connection.executeReturningChanges(
            "DELETE FROM events WHERE uploaded = 1 AND event_ts < ?;",
            bind: [.integer(beforeTimestampMs)]
        )
    }

    public func count() async throws -> Int {
        try await ensureSchema()
        let rows = try await connection.query("SELECT COUNT(*) FROM events;") { stmt in
            stmt.int(at: 0)
        }
        return rows.first ?? 0
    }
}

// MARK: - 私有：绑定 / 解码

private func bindings(for event: AnalyticsEvent) -> [SQLiteValue] {
    [
        .text(event.userID),
        .text(event.deviceID),
        SQLiteValue(event.sessionID),
        .text(event.eventName.rawValue),
        .integer(event.eventTimestampMs),
        .text(event.propertiesJSON()),
        .text(event.appVersion),
        .integer(event.uploaded ? 1 : 0)
    ]
}

private func decodeEvent(from stmt: SQLiteStatement) -> AnalyticsEvent {
    let id = stmt.int64(at: 0)
    let userID = stmt.string(at: 1) ?? ""
    let deviceID = stmt.string(at: 2) ?? ""
    let sessionID = stmt.isNull(at: 3) ? nil : stmt.string(at: 3)
    let eventNameRaw = stmt.string(at: 4) ?? ""
    let eventName = AnalyticsEventName(rawValue: eventNameRaw) ?? .appLaunch
    let eventTs = stmt.int64(at: 5)
    let propsJson = stmt.string(at: 6) ?? "{}"
    let appVersion = stmt.string(at: 7) ?? ""
    let uploaded = stmt.bool(at: 8)

    let props = (try? JSONDecoder().decode([String: String].self, from: Data(propsJson.utf8))) ?? [:]

    return AnalyticsEvent(
        id: id, userID: userID, deviceID: deviceID, sessionID: sessionID,
        eventName: eventName, eventTimestampMs: eventTs,
        properties: props, appVersion: appVersion, uploaded: uploaded
    )
}
