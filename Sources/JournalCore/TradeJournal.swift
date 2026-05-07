// WP-53 模块 3 · 交易日志数据模型
// A09 禁做项："不要让日志编辑反向污染原始成交数据" → tradeIDs 单向引用 [Trade.id]
// 用户填写：原因 / 情绪 / 偏差 / 教训 / 标签
//
// WP-60 同步预埋（v15.24 batch006 · 敏感数据 · 阿里云通道留 Stage B）：
//   - version / deletedAt 字段预埋（schema 兼容 · 不接 backend）
//   - 启用同步（阿里云自建）由 Stage B WP-84 合规方案落地后接入
//   - D4 G1 方案 A：日志是 PII · 不走 CloudKit

import Foundation

/// 情绪标签 · 5 类常见交易情绪
public enum JournalEmotion: String, Sendable, Codable, CaseIterable {
    case confident   // 自信
    case hesitant    // 犹豫
    case fearful     // 恐惧
    case greedy      // 贪婪
    case calm        // 平静
}

/// 偏差类型 · 实际行为 vs 计划 的偏离类型
public enum JournalDeviation: String, Sendable, Codable, CaseIterable {
    case asPlanned          // 按计划执行
    case breakStopLoss      // 超出止损未止
    case chaseRebound       // 抢反弹
    case chaseHigh          // 追高
    case catchFalling       // 抄底
    case earlyExit          // 过早离场
    case overTrade          // 超额交易
    case other              // 其他
}

/// 交易日志条目 · 一篇日志可关联多笔成交（一对多 + 单向）
public struct TradeJournal: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    /// 关联的 Trade.id 列表（单向：日志改不影响 trades；删 trade 不级联删日志）
    public var tradeIDs: [UUID]
    public var title: String
    /// 交易理由（开仓 / 持仓决策的依据）
    public var reason: String
    public var emotion: JournalEmotion
    public var deviation: JournalDeviation
    /// 教训 / 复盘结论（事后填）
    public var lesson: String
    /// 标签集合（用于分类与搜索；Set 保证去重）
    public var tags: Set<String>
    public var createdAt: Date
    public var updatedAt: Date
    /// WP-60 · 修改次数（敏感数据 · 阿里云自建通道 · Stage B 启用）
    public var version: Int
    /// WP-60 · 软删除时间戳
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        tradeIDs: [UUID] = [],
        title: String,
        reason: String = "",
        emotion: JournalEmotion = .calm,
        deviation: JournalDeviation = .asPlanned,
        lesson: String = "",
        tags: Set<String> = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        version: Int = 1,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.tradeIDs = tradeIDs
        self.title = title
        self.reason = reason
        self.emotion = emotion
        self.deviation = deviation
        self.lesson = lesson
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.deletedAt = deletedAt
    }

    // MARK: - Codable（兼容旧 JSON · 缺 version/deletedAt 时回退）

    private enum CodingKeys: String, CodingKey {
        case id, tradeIDs, title, reason, emotion, deviation, lesson, tags
        case createdAt, updatedAt, version, deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.tradeIDs = try c.decode([UUID].self, forKey: .tradeIDs)
        self.title = try c.decode(String.self, forKey: .title)
        self.reason = try c.decode(String.self, forKey: .reason)
        self.emotion = try c.decode(JournalEmotion.self, forKey: .emotion)
        self.deviation = try c.decode(JournalDeviation.self, forKey: .deviation)
        self.lesson = try c.decode(String.self, forKey: .lesson)
        self.tags = try c.decode(Set<String>.self, forKey: .tags)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tradeIDs, forKey: .tradeIDs)
        try c.encode(title, forKey: .title)
        try c.encode(reason, forKey: .reason)
        try c.encode(emotion, forKey: .emotion)
        try c.encode(deviation, forKey: .deviation)
        try c.encode(lesson, forKey: .lesson)
        try c.encode(tags, forKey: .tags)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    /// 软删除（同步友好 · 不物理删 · 由调用方持久化）
    public mutating func markDeleted(now: Date = Date()) {
        guard deletedAt == nil else { return }
        deletedAt = now
        updatedAt = now
        version += 1
    }
}
