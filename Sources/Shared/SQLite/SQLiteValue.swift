// WP-19a · SQLite 类型化值（绑定参数用）

import Foundation

/// 绑定到 SQL prepare 语句的参数值
public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

public extension SQLiteValue {
    init(_ v: Int)     { self = .integer(Int64(v)) }
    init(_ v: Int64)   { self = .integer(v) }
    init(_ v: Double)  { self = .real(v) }
    init(_ v: String)  { self = .text(v) }
    init(_ v: Bool)    { self = .integer(v ? 1 : 0) }
    init(_ v: Data)    { self = .blob(v) }

    /// nil-aware 工厂：可空字符串 → null OR text
    init(_ v: String?) { self = v.map { .text($0) } ?? .null }
    init(_ v: Int?)    { self = v.map { .integer(Int64($0)) } ?? .null }
    init(_ v: Int64?)  { self = v.map(SQLiteValue.integer) ?? .null }
}
