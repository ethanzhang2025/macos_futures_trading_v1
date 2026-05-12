// v17.138 · 主图时间范围预设（trader 复盘 / 回顾常用快捷范围）
//
// trader 场景：
// - 复盘上周走势：1W 一键切到最近 1 周
// - 月度回顾：1M 切月范围
// - 季度趋势：3M 看更长 swing
// - 长线判断：6M / 1Y 看大周期格局
//
// 设计：
// - 纯数据 · 不依赖 SwiftUI
// - 按当前 period 计算所需 bars 数（向上取整 · 至少 10）
// - UI 层负责切 viewport（startIndex = bars.count - barCount · visibleCount = barCount）
// - 不考虑交易时段（按 24h 日历日近似 · trader 一眼可知）

import Foundation

/// 主图时间范围预设
public enum ChartTimeRangePreset: String, Sendable, CaseIterable, Identifiable {
    case oneDay      // 1D
    case oneWeek     // 1W
    case oneMonth    // 1M
    case threeMonths // 3M
    case sixMonths   // 6M
    case oneYear     // 1Y

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oneDay:      return "1D"
        case .oneWeek:     return "1W"
        case .oneMonth:    return "1M"
        case .threeMonths: return "3M"
        case .sixMonths:   return "6M"
        case .oneYear:     return "1Y"
        }
    }

    /// 时间范围的秒数（按日历日近似 · 月=30天 · 年=365天）
    public var seconds: Int {
        switch self {
        case .oneDay:      return 86400
        case .oneWeek:     return 604800
        case .oneMonth:    return 2592000          // 30 天
        case .threeMonths: return 7776000          // 90 天
        case .sixMonths:   return 15552000         // 180 天
        case .oneYear:     return 31536000         // 365 天
        }
    }

    /// 在指定 period 下显示该时间范围所需的 bars 数（向上取整 · 最少 10）
    /// - 超长周期（period.seconds > 范围秒数）返回 10（基本最小可读 viewport）
    /// - 短周期场景按 ceil 计算（如 1Y / daily = 365 bars · 1W / 1h = 168 bars）
    public func barCount(for period: KLinePeriod) -> Int {
        let per = period.seconds
        guard per > 0 else { return 120 }
        let raw = (seconds + per - 1) / per   // ceil division
        return max(10, raw)
    }
}
