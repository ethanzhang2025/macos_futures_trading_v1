// WP-19a · SQLite statement 取列封装
// 给 query rowMapper 闭包的参数；隐藏 sqlite3_column_xxx 调用

import Foundation
import CSQLite

/// 包装 sqlite3_stmt 的 typed accessor · 仅在 SQLiteConnection.query 闭包内有效
public struct SQLiteStatement {
    let stmt: OpaquePointer

    public func columnCount() -> Int32 { sqlite3_column_count(stmt) }

    public func string(at column: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cstr)
    }

    public func int(at column: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, column))
    }

    public func int64(at column: Int32) -> Int64 {
        sqlite3_column_int64(stmt, column)
    }

    public func double(at column: Int32) -> Double {
        sqlite3_column_double(stmt, column)
    }

    public func bool(at column: Int32) -> Bool {
        sqlite3_column_int64(stmt, column) != 0
    }

    public func data(at column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return nil }
        let length = Int(sqlite3_column_bytes(stmt, column))
        return Data(bytes: bytes, count: length)
    }

    public func isNull(at column: Int32) -> Bool {
        sqlite3_column_type(stmt, column) == SQLITE_NULL
    }
}
