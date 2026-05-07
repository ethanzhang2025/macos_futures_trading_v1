// SyncableRecord · 业务模型 → SyncRecord 桥接协议（WP-60）
//
// 业务模型实现本协议后即可纳入同步链路。
// 通常配合 Adapter 使用：业务模块定义 typealias + extension 即可，无需新增类型。
//
// 字段约束：
//   - id: UUID（业务记录唯一标识 · 跨端一致）
//   - lastModified / version / deletedAt 由业务模型 schema 预埋（batch003-007）
//   - encodePayload(): 把业务字段编码为 Data（不含 metadata）
//
// 注意：本协议不规定如何持久化字段（SQLite 列 / JSON blob 都可以 · 由各 Core 自行决定）。

import Foundation

public protocol SyncableRecord: Sendable {
    /// SyncRecord.recordType（如 "watchlist"）
    static var syncRecordType: String { get }

    var id: UUID { get }
    var lastModified: Date { get }
    var version: Int { get }
    var deletedAt: Date? { get }

    /// 业务字段编码为 payload（不含 metadata）
    func encodePayload() throws -> Data
}

extension SyncableRecord {
    /// 转换为 SyncRecord（默认实现 · 业务模型可重写）
    public func toSyncRecord() throws -> SyncRecord {
        try SyncRecord(
            recordType: Self.syncRecordType,
            id: id,
            lastModified: lastModified,
            version: version,
            deletedAt: deletedAt,
            payload: encodePayload()
        )
    }
}

/// 反向：SyncRecord → 业务模型 · 各 Adapter 提供静态工厂
public protocol SyncRecordDecodable: SyncableRecord {
    static func decode(from record: SyncRecord) throws -> Self
}
