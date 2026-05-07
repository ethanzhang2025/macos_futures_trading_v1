// SyncRecord · 同步通信 DTO（WP-60）
//
// 设计要点：
//   - 厂商无关：不绑定 CloudKit / 阿里云 schema
//   - 业务无关：所有具体业务字段 Codable 进 payload
//   - LWW 元数据：lastModified / version / deletedAt 三字段是同步层契约
//
// version 语义：
//   - 单调递增 · 0 起步
//   - 每次本地修改 +1（push 前由 Adapter 自增）
//   - backend 不改 version（仅落盘 + 取回）
//
// deletedAt 语义（tombstone）：
//   - 非 nil 表示该记录已删除
//   - 同步时把 tombstone push 到对端
//   - 对端收到后本地软删
//   - GC 策略由 SyncEngine 实现（默认 30 天后清理）
//
// payload 语义：
//   - Adapter 用 JSONEncoder/Decoder 序列化业务对象
//   - backend 不解析 payload（只看 metadata）
//   - 跨版本兼容：业务对象自己处理 Codable 演进

import Foundation

/// 同步层标准记录 · 通信契约
public struct SyncRecord: Sendable, Codable, Equatable, Hashable {
    /// 记录类型 · 用于 backend 分表（如 "watchlist" / "workspace_template"）
    public let recordType: String

    /// 业务记录 ID · UUID 跨端唯一
    public let id: UUID

    /// 最后修改时间 · LWW 主决胜字段
    public var lastModified: Date

    /// 修改次数 · LWW 副决胜字段（同 lastModified 时比 version）
    public var version: Int

    /// 删除时间戳（tombstone）· nil 表示未删
    public var deletedAt: Date?

    /// 业务负载 · Adapter 序列化业务对象后填入
    public var payload: Data

    public init(
        recordType: String,
        id: UUID,
        lastModified: Date,
        version: Int,
        deletedAt: Date? = nil,
        payload: Data
    ) {
        self.recordType = recordType
        self.id = id
        self.lastModified = lastModified
        self.version = version
        self.deletedAt = deletedAt
        self.payload = payload
    }

    /// 是否已删除（tombstone）
    public var isDeleted: Bool { deletedAt != nil }
}
