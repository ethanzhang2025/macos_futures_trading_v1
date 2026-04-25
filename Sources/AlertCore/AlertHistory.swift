// WP-52 模块 2 · 预警触发历史记录
// 复盘场景：用户能追溯触发时间 + 触发条件 + 触发价格
//
// 协议优先（与 KLineCacheStore 同形）便于多实现：
// - InMemoryAlertHistoryStore：测试 / 临时
// - 后续可加 SQLiteAlertHistoryStore（WP-19 数据持久化）

import Foundation

/// 单条触发历史记录
public struct AlertHistoryEntry: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var alertID: UUID
    public var alertName: String
    public var instrumentID: String
    /// 触发时的条件快照（条件可能在触发后被修改，所以历史里存快照）
    public var conditionSnapshot: AlertCondition
    public var triggeredAt: Date
    /// 触发瞬间的价格（用于复盘）
    public var triggerPrice: Decimal
    /// 人类可读的触发说明（"价格上穿 3500" 等）
    public var message: String

    public init(
        id: UUID = UUID(),
        alertID: UUID,
        alertName: String,
        instrumentID: String,
        conditionSnapshot: AlertCondition,
        triggeredAt: Date,
        triggerPrice: Decimal,
        message: String
    ) {
        self.id = id
        self.alertID = alertID
        self.alertName = alertName
        self.instrumentID = instrumentID
        self.conditionSnapshot = conditionSnapshot
        self.triggeredAt = triggeredAt
        self.triggerPrice = triggerPrice
        self.message = message
    }
}

/// 预警历史 store 协议
public protocol AlertHistoryStore: Sendable {
    /// 追加新的触发记录
    func append(_ entry: AlertHistoryEntry) async throws

    /// 加载指定 alertID 的所有历史（按 triggeredAt 降序，最近在前）
    func history(forAlertID alertID: UUID) async throws -> [AlertHistoryEntry]

    /// 加载所有 alert 的全量历史（按 triggeredAt 降序）
    func allHistory() async throws -> [AlertHistoryEntry]

    /// 清除指定 alertID 的历史（用户删除 alert 时联动）
    func clear(alertID: UUID) async throws

    /// 清除全部历史
    func clearAll() async throws
}

/// 内存实现 · 测试 / 临时场景
public actor InMemoryAlertHistoryStore: AlertHistoryStore {

    private var entries: [AlertHistoryEntry] = []

    public init() {}

    public func append(_ entry: AlertHistoryEntry) async throws {
        entries.append(entry)
    }

    public func history(forAlertID alertID: UUID) async throws -> [AlertHistoryEntry] {
        entries.filter { $0.alertID == alertID }
            .sorted { $0.triggeredAt > $1.triggeredAt }
    }

    public func allHistory() async throws -> [AlertHistoryEntry] {
        entries.sorted { $0.triggeredAt > $1.triggeredAt }
    }

    public func clear(alertID: UUID) async throws {
        entries.removeAll { $0.alertID == alertID }
    }

    public func clearAll() async throws {
        entries.removeAll()
    }
}
