// WP-54 v15.23 batch4 · 纪律规则聚合根（CRUD + Codable + 默认推荐配置）
//
// 设计模式：与 WP-43 WatchlistBook / WP-55 WorkspaceBook 一致
// - 持有 [DisciplineRule] · CRUD 操作（add/update/remove/setEnabled）
// - id 唯一性保证（addRule 同 id 覆盖 · update 保留 createdAt 刷新 updatedAt）
// - 查询 helper：rule(id:) / rules(of:) / enabledRules
// - defaultRecommended：trader 首次启用一键导入推荐配置（5 规则 · 中文注释）

import Foundation

public struct DisciplineBook: Sendable, Equatable, Codable {
    public private(set) var rules: [DisciplineRule]

    public init(rules: [DisciplineRule] = []) {
        self.rules = rules
    }

    // MARK: - CRUD

    /// 添加规则 · 同 id 已存在则覆盖（避免重复）
    public mutating func addRule(_ rule: DisciplineRule) {
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
    }

    /// 删除规则
    public mutating func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    /// 更新规则 · 保留原 createdAt · 自动刷新 updatedAt（now 可注入测试）
    @discardableResult
    public mutating func updateRule(_ rule: DisciplineRule, now: Date = Date()) -> Bool {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return false }
        let preserved = DisciplineRule(
            id: rule.id,
            kind: rule.kind,
            threshold: rule.threshold,
            enabled: rule.enabled,
            note: rule.note,
            createdAt: rules[idx].createdAt,
            updatedAt: now
        )
        rules[idx] = preserved
        return true
    }

    /// 切换启用状态（CRUD 简化路径 · UI 一键 toggle 用）
    @discardableResult
    public mutating func setEnabled(id: UUID, enabled: Bool, now: Date = Date()) -> Bool {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return false }
        rules[idx].enabled = enabled
        rules[idx].updatedAt = now
        return true
    }

    // MARK: - 查询

    public func rule(id: UUID) -> DisciplineRule? {
        rules.first { $0.id == id }
    }

    public func rules(of kind: DisciplineRuleKind) -> [DisciplineRule] {
        rules.filter { $0.kind == kind }
    }

    public var enabledRules: [DisciplineRule] {
        rules.filter { $0.enabled }
    }

    // MARK: - 默认推荐配置（v15.23 batch4）

    /// trader 首次开启训练时一键导入的 5 条推荐规则（典型期货短线纪律）
    public static var defaultRecommended: DisciplineBook {
        DisciplineBook(rules: [
            DisciplineRule(kind: .stopLossPercent,   threshold: 2.0,  note: "单笔止损 2%"),
            DisciplineRule(kind: .maxHoldingMinutes, threshold: 60,   note: "日内不过夜（60 分钟）"),
            DisciplineRule(kind: .maxAddPositions,   threshold: 3,    note: "同方向加仓不超 3 次"),
            DisciplineRule(kind: .dailyMaxLoss,      threshold: 5000, note: "单日亏损不超 5000 元"),
            DisciplineRule(kind: .maxDailyTrades,    threshold: 20,   note: "单日交易不超 20 笔"),
        ])
    }

    // MARK: - v16.43 · trader 风格规则模板（4 套预设 · 与训练 9 形态场景互补）

    /// 激进日内（高频抢反弹 · 容忍更大止损 + 更多加仓）
    public static var aggressiveIntraday: DisciplineBook {
        DisciplineBook(rules: [
            DisciplineRule(kind: .stopLossPercent,   threshold: 3.0,  note: "单笔止损 3%（容忍波动）"),
            DisciplineRule(kind: .maxHoldingMinutes, threshold: 30,   note: "持仓 30 分钟（高频）"),
            DisciplineRule(kind: .maxAddPositions,   threshold: 5,    note: "加仓不超 5 次（金字塔）"),
            DisciplineRule(kind: .dailyMaxLoss,      threshold: 8000, note: "单日亏损不超 8000 元"),
            DisciplineRule(kind: .maxDailyTrades,    threshold: 50,   note: "单日交易不超 50 笔（高频）"),
        ])
    }

    /// 波段持仓（隔夜 OK · 长持 · 严格止损）
    public static var swingHolding: DisciplineBook {
        DisciplineBook(rules: [
            DisciplineRule(kind: .stopLossPercent,   threshold: 5.0,   note: "单笔止损 5%（波段空间）"),
            DisciplineRule(kind: .maxHoldingMinutes, threshold: 4320,  note: "持仓上限 3 天（4320 分钟）"),
            DisciplineRule(kind: .maxAddPositions,   threshold: 2,     note: "加仓不超 2 次（轻仓）"),
            DisciplineRule(kind: .dailyMaxLoss,      threshold: 10000, note: "单日亏损不超 10000 元"),
            DisciplineRule(kind: .maxDailyTrades,    threshold: 5,     note: "单日交易不超 5 笔（波段精选）"),
        ])
    }

    /// 极简纪律（trader 入门 · 仅 2 条核心 · 不被规则淹没）
    public static var minimal: DisciplineBook {
        DisciplineBook(rules: [
            DisciplineRule(kind: .stopLossPercent, threshold: 2.0,  note: "单笔止损 2%（核心）"),
            DisciplineRule(kind: .dailyMaxLoss,    threshold: 5000, note: "单日亏损不超 5000 元（核心）"),
        ])
    }
}
