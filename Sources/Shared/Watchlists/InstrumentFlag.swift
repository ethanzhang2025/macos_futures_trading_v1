// v17.34 C5 · 自选合约旗标 / 评级
//
// trader 场景：
// - 重点关注（star · ⭐）：高优先级 · 主图频繁打开
// - 强烈看好（strong · 🔥）：当前周期主力交易标的
// - 观察（watch · 👀）：等信号触发再行动
// - 回避（avoid · ✗）：不打算交易（流动性差 / 套牢风险等）
//
// 设计：
// - 全局存储（不挂在 Watchlist group · 同合约在多组共享同一 flag）
// - UserDefaults 持久化（轻量 · 跨窗口 didChangeNotification 联动）
// - 不参与 CloudKit 同步（v1 仅本机 · 留 v2）

import Foundation

public enum InstrumentFlag: String, Sendable, Codable, CaseIterable {
    case none           // 默认无旗标
    case watch          // 👀 观察
    case star           // ⭐ 重点关注
    case strong         // 🔥 强烈看好
    case avoid          // ✗ 回避

    public var emoji: String {
        switch self {
        case .none:    return ""
        case .watch:   return "👀"
        case .star:    return "⭐"
        case .strong:  return "🔥"
        case .avoid:   return "✗"
        }
    }

    public var displayName: String {
        switch self {
        case .none:    return "无旗标"
        case .watch:   return "观察"
        case .star:    return "重点关注"
        case .strong:  return "强烈看好"
        case .avoid:   return "回避"
        }
    }

    /// 排序权重（trader 视角：重要 → 不重要 · avoid 排末因主动忽略）
    public var sortRank: Int {
        switch self {
        case .strong:  return 0
        case .star:    return 1
        case .watch:   return 2
        case .none:    return 3
        case .avoid:   return 4
        }
    }
}

/// 全局旗标 store · UserDefaults stringDict (instrumentID → rawValue) 持久化
/// 跨窗口同步走 UserDefaults.didChangeNotification（与 ChartTheme / SimulatedTradingStore 同模式）
public struct InstrumentFlagStore {

    public static let defaultsKey = "watchlist.v1.instrumentFlags"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读 instrumentID 的 flag · 缺失返回 .none
    public func flag(for instrumentID: String) -> InstrumentFlag {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String],
              let raw = dict[instrumentID],
              let flag = InstrumentFlag(rawValue: raw) else {
            return .none
        }
        return flag
    }

    /// 设置 flag · .none 会从存储移除（保持 dict 紧凑）
    public func setFlag(_ flag: InstrumentFlag, for instrumentID: String) {
        var dict = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
        if flag == .none {
            dict.removeValue(forKey: instrumentID)
        } else {
            dict[instrumentID] = flag.rawValue
        }
        defaults.set(dict, forKey: Self.defaultsKey)
    }

    /// 全部旗标快照（测试 / 全量 export 用）
    public func allFlags() -> [String: InstrumentFlag] {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] else { return [:] }
        return dict.reduce(into: [:]) { acc, kv in
            if let flag = InstrumentFlag(rawValue: kv.value) { acc[kv.key] = flag }
        }
    }

    /// 清空全部旗标
    public func clearAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
