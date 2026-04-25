// WP-19a · SQLite 错误类型
// 包装 sqlite3 C API 错误码 + 错误消息

import Foundation

public enum SQLiteError: Error, CustomStringConvertible, Equatable {
    case openFailed(path: String, code: Int32, message: String)
    case prepareFailed(sql: String, code: Int32, message: String)
    case stepFailed(sql: String, code: Int32, message: String)
    case bindFailed(sql: String, paramIndex: Int, code: Int32, message: String)
    case execFailed(sql: String, code: Int32, message: String)
    case closed

    public var description: String {
        switch self {
        case .openFailed(let path, let code, let msg):
            return "SQLite open 失败 [\(code)] path=\(path) · \(msg)"
        case .prepareFailed(let sql, let code, let msg):
            return "SQLite prepare 失败 [\(code)] sql=\(sql) · \(msg)"
        case .stepFailed(let sql, let code, let msg):
            return "SQLite step 失败 [\(code)] sql=\(sql) · \(msg)"
        case .bindFailed(let sql, let idx, let code, let msg):
            return "SQLite bind 失败 [\(code)] sql=\(sql) param=\(idx) · \(msg)"
        case .execFailed(let sql, let code, let msg):
            return "SQLite exec 失败 [\(code)] sql=\(sql) · \(msg)"
        case .closed:
            return "SQLite 连接已关闭"
        }
    }
}
