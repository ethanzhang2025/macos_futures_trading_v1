// 自选合约高级筛选（v15.38 · 行情列表 V2）
//
// 设计：
//   - 内置 6 种 preset filter（trader 高频扫盘需求）
//   - 自定义涨跌幅区间过滤
//   - 关键词模糊匹配（合约 ID lowercase contains）
//   - 多个 filter 可组合（preset + 关键词同时生效）
//   - 输入：[String] · 输出：[String]（保序）

import Foundation

public enum WatchlistFilterPreset: String, CaseIterable, Sendable, Codable {
    case all              // 全部（不过滤）
    case gainers2pct      // 涨幅 ≥ 2%
    case gainers5pct      // 涨幅 ≥ 5%
    case losers2pct       // 跌幅 ≥ 2%
    case losers5pct       // 跌幅 ≥ 5%
    case limitUp          // 涨停（≥ 9.5% 接近 / ≥ 涨停板按品种取值）
    case limitDown        // 跌停（≤ -9.5%）
    case extreme          // 极端波动（|涨跌幅| ≥ 5%）
    case active           // 活跃（成交量 > 阈值）

    public var displayName: String {
        switch self {
        case .all:          return "全部"
        case .gainers2pct:  return "涨 ≥ 2%"
        case .gainers5pct:  return "涨 ≥ 5%"
        case .losers2pct:   return "跌 ≥ 2%"
        case .losers5pct:   return "跌 ≥ 5%"
        case .limitUp:      return "涨停板"
        case .limitDown:    return "跌停板"
        case .extreme:      return "极端 ≥5%"
        case .active:       return "活跃"
        }
    }

    /// 该 preset 是否需要 changePct
    public var needsChangePct: Bool {
        switch self {
        case .all, .active: return false
        default:            return true
        }
    }

    /// 该 preset 是否需要 volume
    public var needsVolume: Bool {
        self == .active
    }
}

public enum WatchlistFilter {

    /// 按 preset + 关键词过滤合约 ID
    /// - Parameters:
    ///   - ids: 输入合约 ID（保序）
    ///   - preset: 内置过滤模式
    ///   - keyword: 关键词（空 = 不过滤 · 非空 = lowercase contains）
    ///   - changePctForID: closure · 取合约涨跌幅 · nil 视为不过的（数据未到时跳过）
    ///   - volumeForID: closure · 取合约成交量 · nil 视为不过
    ///   - activeVolumeThreshold: .active 阈值（默认 100000）
    /// - Returns: 通过过滤的 ID 列表（保序 · 不去重 · 输入若有重复保留）
    public static func filter(
        ids: [String],
        preset: WatchlistFilterPreset = .all,
        keyword: String = "",
        changePctForID: (String) -> Double? = { _ in nil },
        volumeForID: (String) -> Double? = { _ in nil },
        activeVolumeThreshold: Double = 100_000
    ) -> [String] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ids.filter { id in
            // 关键词过滤
            if !kw.isEmpty && !id.lowercased().contains(kw) { return false }
            // preset 过滤
            return matchesPreset(id, preset: preset,
                                 changePctForID: changePctForID,
                                 volumeForID: volumeForID,
                                 activeVolumeThreshold: activeVolumeThreshold)
        }
    }

    private static func matchesPreset(
        _ id: String, preset: WatchlistFilterPreset,
        changePctForID: (String) -> Double?,
        volumeForID: (String) -> Double?,
        activeVolumeThreshold: Double
    ) -> Bool {
        switch preset {
        case .all:
            return true
        case .gainers2pct:
            guard let p = changePctForID(id) else { return false }
            return p >= 2
        case .gainers5pct:
            guard let p = changePctForID(id) else { return false }
            return p >= 5
        case .losers2pct:
            guard let p = changePctForID(id) else { return false }
            return p <= -2
        case .losers5pct:
            guard let p = changePctForID(id) else { return false }
            return p <= -5
        case .limitUp:
            guard let p = changePctForID(id) else { return false }
            return p >= 9.5     // 中国期货大部分品种 ±10%（贵金属 ±15%）· 9.5 接近涨停
        case .limitDown:
            guard let p = changePctForID(id) else { return false }
            return p <= -9.5
        case .extreme:
            guard let p = changePctForID(id) else { return false }
            return abs(p) >= 5
        case .active:
            guard let v = volumeForID(id) else { return false }
            return v >= activeVolumeThreshold
        }
    }
}
