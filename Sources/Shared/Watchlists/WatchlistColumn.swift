// v17.42 C1 · 自选列表列自定义 v2（toggle 显示/隐藏可选列）
//
// 设计：
// - 必显列（合约 ID / 最新价 / 涨跌幅）= core · 不在此 enum 内
// - 可选列（持仓量 / 成交量 / 买卖价差%）= 用户可 toggle
// - UserDefaults stringSet 持久化 visible set（key = "watchlist.columns.visible.v1"）
// - 默认仅 .openInterest 可见（与历史 row 一致）· 升级零侵入

import Foundation

/// 自选列表可选列 · v2 范围（v3 留：列顺序 drag · 列宽自定义）
public enum WatchlistColumn: String, Sendable, Codable, CaseIterable, Identifiable {
    case openInterest
    case volume
    case spread

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openInterest: return "持仓量"
        case .volume:       return "成交量"
        case .spread:       return "买卖价差%"
        }
    }

    /// 表头列宽（与 instrumentRow 内 frame width 一致 · 改动需双向同步）
    public var width: CGFloat {
        switch self {
        case .openInterest: return 80
        case .volume:       return 80
        case .spread:       return 90
        }
    }
}

/// UserDefaults 持久化 helper（key 与默认值集中此处 · 测试可注入自定义 defaults）
public enum WatchlistColumnPreferences {

    public static let userDefaultsKey = "watchlist.columns.visible.v1"

    /// 默认仅持仓量可见（与 v1 行为一致）
    public static let defaultVisible: Set<WatchlistColumn> = [.openInterest]

    public static func load(_ defaults: UserDefaults = .standard) -> Set<WatchlistColumn> {
        guard let raws = defaults.array(forKey: userDefaultsKey) as? [String] else {
            return defaultVisible
        }
        return Set(raws.compactMap { WatchlistColumn(rawValue: $0) })
    }

    public static func save(_ visible: Set<WatchlistColumn>,
                            to defaults: UserDefaults = .standard) {
        defaults.set(visible.map { $0.rawValue }, forKey: userDefaultsKey)
    }

    public static func toggle(_ column: WatchlistColumn,
                              in defaults: UserDefaults = .standard) -> Set<WatchlistColumn> {
        var visible = load(defaults)
        if visible.contains(column) {
            visible.remove(column)
        } else {
            visible.insert(column)
        }
        save(visible, to: defaults)
        return visible
    }
}
