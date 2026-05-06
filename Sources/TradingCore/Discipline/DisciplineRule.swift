// WP-54 v15.23 batch1 · 模拟训练纪律检查规则数据模型（M5 节点）
//
// 设计：
// - 5 种规则覆盖期货短线常见纪律（止损 / 持仓时长 / 加仓 / 单日亏损 / 单日交易次数）
// - threshold 用 Decimal 统一表达 · 各 kind 自定义语义（百分比 / 分钟 / 次 / 元 / 笔）
// - DisciplineViolation 记录每次违规（含 severity warning/error · 关联订单 · 上下文 JSON）
// - evaluator 留 batch2+ 实现（输入 trades + positions + 当前时间 → 输出 violations）

import Foundation

/// 纪律规则类型（5 种 · trader 自定义启用任意组合）
public enum DisciplineRuleKind: String, Sendable, Equatable, CaseIterable, Codable {
    case stopLossPercent      // 单笔最大亏损百分比（threshold = 2.0 即 -2% 触发）
    case maxHoldingMinutes    // 单笔最大持仓分钟数
    case maxAddPositions      // 单合约同方向最大加仓次数
    case dailyMaxLoss         // 单日最大亏损金额（元 · 正数表达上限 · 实际亏损为负）
    case maxDailyTrades       // 单日最大交易次数（笔 · 防过度交易）

    public var displayName: String {
        switch self {
        case .stopLossPercent:    return "单笔止损百分比"
        case .maxHoldingMinutes:  return "持仓时长上限"
        case .maxAddPositions:    return "加仓次数上限"
        case .dailyMaxLoss:       return "单日亏损上限"
        case .maxDailyTrades:     return "单日交易次数上限"
        }
    }

    /// 阈值显示单位（UI 渲染时拼在 threshold 数值后）
    public var thresholdUnit: String {
        switch self {
        case .stopLossPercent:    return "%"
        case .maxHoldingMinutes:  return "分钟"
        case .maxAddPositions:    return "次"
        case .dailyMaxLoss:       return "元"
        case .maxDailyTrades:     return "笔"
        }
    }
}

/// 纪律规则（trader 自定义 · CRUD 单元）
public struct DisciplineRule: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var kind: DisciplineRuleKind
    public var threshold: Decimal
    public var enabled: Bool
    public var note: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), kind: DisciplineRuleKind, threshold: Decimal,
                enabled: Bool = true, note: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.threshold = threshold
        self.enabled = enabled
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 纪律违规记录（evaluator 输出 · 训练复盘呈现）
public struct DisciplineViolation: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let ruleID: UUID
    public let ruleKind: DisciplineRuleKind
    public let occurredAt: Date
    public let severity: Severity
    public let message: String
    public let relatedOrderRefs: [String]
    public let context: String?

    public enum Severity: String, Sendable, Equatable, Codable, CaseIterable {
        case warning   // 软警告（接近阈值）
        case error     // 硬违规（已超阈值）

        public var displayName: String {
            switch self {
            case .warning: return "警告"
            case .error:   return "违规"
            }
        }
    }

    public init(id: UUID = UUID(), ruleID: UUID, ruleKind: DisciplineRuleKind,
                occurredAt: Date, severity: Severity, message: String,
                relatedOrderRefs: [String] = [], context: String? = nil) {
        self.id = id
        self.ruleID = ruleID
        self.ruleKind = ruleKind
        self.occurredAt = occurredAt
        self.severity = severity
        self.message = message
        self.relatedOrderRefs = relatedOrderRefs
        self.context = context
    }
}
