// v17.175 · CrossInstrumentLinkage 规则集合 + UserDefaults 持久化
//
// trader 配置一组联动规则（如 RB→HC / I→J→焦炭）· 主菜单"工具 → 跨合约联动" 入口管理
// v1 UserDefaults JSON · v2 可考虑迁 SQLite（大量规则时）

import Foundation

/// 规则集合（持久化用 · CRUD 接口）
public struct CrossLinkageRules: Sendable, Codable, Equatable {
    public var rules: [CrossInstrumentLinkageRule]

    public init(rules: [CrossInstrumentLinkageRule] = []) {
        self.rules = rules
    }

    public static let empty = CrossLinkageRules()

    public mutating func add(_ rule: CrossInstrumentLinkageRule) {
        rules.append(rule)
    }

    public mutating func remove(ruleID: String) {
        rules.removeAll { $0.ruleID == ruleID }
    }

    public mutating func update(_ rule: CrossInstrumentLinkageRule) {
        guard let idx = rules.firstIndex(where: { $0.ruleID == rule.ruleID }) else { return }
        rules[idx] = rule
    }

    /// 生成下一个唯一 ruleID（CL- 前缀 + 时间戳后 6 位 · 简单避免碰撞）
    public func nextID() -> String {
        let stamp = Int(Date().timeIntervalSince1970 * 1000) % 1_000_000
        return "CL-\(stamp)"
    }
}

public enum CrossLinkageRulesStore {
    public static let key = "crossLinkageRules.v1"

    public static func load(defaults: UserDefaults = .standard) -> CrossLinkageRules? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CrossLinkageRules.self, from: data)
    }

    public static func save(_ rules: CrossLinkageRules, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}
