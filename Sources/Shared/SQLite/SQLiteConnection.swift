// WP-19a · SQLite 连接 actor
// 单连接 · actor 隔离 · 串行操作 · 不需要外部锁
//
// 设计取舍：
// - 不抽 ORM；仅暴露 exec / query / executeReturningRowID 三个原语
// - prepare → bind → step 流程内联在 actor 方法内（避免 Statement 对象逃出 actor）
// - 写操作返回 lastInsertRowID OR changes count（Store 自行选择）
// - 错误用 SQLiteError 抛出，含 sqlite3_errmsg 上下文

import Foundation
import CSQLite

public actor SQLiteConnection {

    private var db: OpaquePointer?

    /// 打开 / 创建数据库文件 · 自动创建上级目录
    /// - Parameter path: 文件路径；":memory:" 表示内存数据库（测试用）
    public init(path: String) throws {
        if path != ":memory:" {
            let url = URL(fileURLWithPath: path).deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        let code = sqlite3_open(path, &handle)
        guard code == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "(no handle)"
            sqlite3_close(handle)
            throw SQLiteError.openFailed(path: path, code: code, message: msg)
        }
        self.db = handle
    }

    // 注意：Swift 6 严格并发禁止 nonisolated deinit 访问 actor 状态
    // → 资源释放必须显式 close()；进程退出时 SQLite 文件句柄由 OS 回收
    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - exec：执行无返回的 SQL（DDL / 多语句）

    public func exec(_ sql: String) throws {
        guard let db else { throw SQLiteError.closed }
        var errmsg: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if code != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "(no message)"
            sqlite3_free(errmsg)
            throw SQLiteError.execFailed(sql: sql, code: code, message: msg)
        }
    }

    // MARK: - query：执行 SELECT，rowMapper 返回每行结果

    public func query<T>(
        _ sql: String,
        bind values: [SQLiteValue] = [],
        rowMapper: (SQLiteStatement) -> T
    ) throws -> [T] {
        guard let db else { throw SQLiteError.closed }
        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let stmt else {
            throw SQLiteError.prepareFailed(sql: sql, code: prepCode, message: errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        try bind(values, to: stmt, sql: sql)

        var rows: [T] = []
        let wrapper = SQLiteStatement(stmt: stmt)
        while true {
            let stepCode = sqlite3_step(stmt)
            if stepCode == SQLITE_ROW {
                rows.append(rowMapper(wrapper))
            } else if stepCode == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.stepFailed(sql: sql, code: stepCode, message: errorMessage(db))
            }
        }
        return rows
    }

    // MARK: - 写操作

    /// 执行 INSERT 并返回 lastInsertRowID
    @discardableResult
    public func executeReturningRowID(
        _ sql: String,
        bind values: [SQLiteValue] = []
    ) throws -> Int64 {
        guard let db else { throw SQLiteError.closed }
        try execute(sql, bind: values)
        return sqlite3_last_insert_rowid(db)
    }

    /// 执行 UPDATE / DELETE 并返回受影响行数
    @discardableResult
    public func executeReturningChanges(
        _ sql: String,
        bind values: [SQLiteValue] = []
    ) throws -> Int {
        guard let db else { throw SQLiteError.closed }
        try execute(sql, bind: values)
        return Int(sqlite3_changes(db))
    }

    private func execute(_ sql: String, bind values: [SQLiteValue]) throws {
        guard let db else { throw SQLiteError.closed }
        var stmt: OpaquePointer?
        let prepCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepCode == SQLITE_OK, let stmt else {
            throw SQLiteError.prepareFailed(sql: sql, code: prepCode, message: errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        try bind(values, to: stmt, sql: sql)

        let stepCode = sqlite3_step(stmt)
        guard stepCode == SQLITE_DONE || stepCode == SQLITE_ROW else {
            throw SQLiteError.stepFailed(sql: sql, code: stepCode, message: errorMessage(db))
        }
    }

    // MARK: - 私有：bind / errmsg

    private func bind(_ values: [SQLiteValue], to stmt: OpaquePointer, sql: String) throws {
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)  // SQLite 参数 index 从 1 开始
            let code = bindValue(value, to: stmt, at: idx)
            if code != SQLITE_OK {
                throw SQLiteError.bindFailed(sql: sql, paramIndex: i + 1, code: code, message: errorMessage(db))
            }
        }
    }

    private func bindValue(_ value: SQLiteValue, to stmt: OpaquePointer, at idx: Int32) -> Int32 {
        switch value {
        case .null:
            return sqlite3_bind_null(stmt, idx)
        case .integer(let n):
            return sqlite3_bind_int64(stmt, idx, n)
        case .real(let d):
            return sqlite3_bind_double(stmt, idx, d)
        case .text(let s):
            // SQLITE_TRANSIENT (Int(-1)) 让 SQLite 自己拷贝字符串
            return sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT_HANDLE)
        case .blob(let data):
            return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                let count = Int32(raw.count)
                return sqlite3_bind_blob(stmt, idx, raw.baseAddress, count, SQLITE_TRANSIENT_HANDLE)
            }
        }
    }

    private func errorMessage(_ db: OpaquePointer?) -> String {
        guard let db else { return "(closed)" }
        return String(cString: sqlite3_errmsg(db))
    }
}

// MARK: - SQLITE_TRANSIENT 常量

/// SQLite 的 SQLITE_TRANSIENT 在 C 头里是 ((sqlite3_destructor_type)-1)
/// Swift 不能直接表达，手动重新声明
@usableFromInline
let SQLITE_TRANSIENT_HANDLE = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
