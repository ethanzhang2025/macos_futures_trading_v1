// WP-53 模块 3 · 交易日志数据模型
// A09 禁做项："不要让日志编辑反向污染原始成交数据" → tradeIDs 单向引用 [Trade.id]
// 用户填写：原因 / 情绪 / 偏差 / 教训 / 标签

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
        updatedAt: Date = Date()
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
    }
}
