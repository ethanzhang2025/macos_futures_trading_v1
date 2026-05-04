// v15.20 batch56 · 复盘区间筛选枚举（替代 v15.19 batch44 的 selectedMonth: String）
//
// trader 复盘需求：
// - 月度（保留 v15.19 行为）
// - 季度（看趋势）
// - 近 7 天（短期复盘）
// - 近 30 天（滚动月度）
// - 当月（快速跳到本月）
// - 全部（默认）
//
// 设计要点：
// - 所有 case 自包含（不依赖外部 Date · 仅 currentMonth/last*Days 在 filter 时取 reference now）
// - filter 是纯函数 · reference 通过参数传入便于测试
// - 与 v15.19 monthString="" / "yyyy-MM" 兼容（month / all 两 case 行为一致）

import Foundation

public enum ReviewDateFilter: Hashable, Sendable {
    case all
    case last7Days
    case last30Days
    case currentMonth
    case month(String)      // "yyyy-MM"
    case quarter(String)    // "yyyy-Qn"  n ∈ 1...4

    /// trader 看到的中文标签（Picker label 用）
    public var displayName: String {
        switch self {
        case .all:           return "全部"
        case .last7Days:     return "近 7 天"
        case .last30Days:    return "近 30 天"
        case .currentMonth:  return "当月"
        case .month(let m):  return m
        case .quarter(let q): return q
        }
    }

    /// 稳定排序 key（Picker tag · 用 String 而非 enum 自身 · SwiftUI Picker tag 友好）
    public var rawTag: String {
        switch self {
        case .all:            return "all"
        case .last7Days:      return "last7"
        case .last30Days:     return "last30"
        case .currentMonth:   return "currentMonth"
        case .month(let m):   return "month:\(m)"
        case .quarter(let q): return "quarter:\(q)"
        }
    }
}

public enum ReviewDateFilterEngine {

    /// 根据 filter 过滤 closedPositions（按 closeTime）
    /// - reference: 当前时间（last7Days/last30Days/currentMonth 的参考点 · 测试时传固定值）
    /// - timeZone: 月/季计算时区（默认 Asia/Shanghai · 中国期货语境）
    public static func filter(
        _ positions: [ClosedPosition],
        by filter: ReviewDateFilter,
        reference: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> [ClosedPosition] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        switch filter {
        case .all:
            return positions

        case .last7Days:
            let cutoff = cal.date(byAdding: .day, value: -7, to: reference) ?? reference
            return positions.filter { $0.closeTime >= cutoff }

        case .last30Days:
            let cutoff = cal.date(byAdding: .day, value: -30, to: reference) ?? reference
            return positions.filter { $0.closeTime >= cutoff }

        case .currentMonth:
            return filterByMonth(positions, monthString: monthKey(reference, calendar: cal))

        case .month(let m):
            return filterByMonth(positions, monthString: m, calendar: cal)

        case .quarter(let q):
            return positions.filter { quarterKey($0.closeTime, calendar: cal) == q }
        }
    }

    /// 当前 positions 涵盖的月份 set（升序 · "yyyy-MM"）
    public static func availableMonths(
        _ positions: [ClosedPosition],
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return Array(Set(positions.map { monthKey($0.closeTime, calendar: cal) })).sorted()
    }

    /// 当前 positions 涵盖的季度 set（升序 · "yyyy-Qn"）
    public static func availableQuarters(
        _ positions: [ClosedPosition],
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return Array(Set(positions.map { quarterKey($0.closeTime, calendar: cal) })).sorted()
    }

    // MARK: - 内部 helper

    private static func filterByMonth(
        _ positions: [ClosedPosition],
        monthString: String,
        calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
            return c
        }()
    ) -> [ClosedPosition] {
        guard !monthString.isEmpty else { return positions }
        return positions.filter { monthKey($0.closeTime, calendar: calendar) == monthString }
    }

    private static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    private static func quarterKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let month = comps.month ?? 1
        let quarter = (month - 1) / 3 + 1   // 1-3 → Q1 · 4-6 → Q2 · 7-9 → Q3 · 10-12 → Q4
        return String(format: "%04d-Q%d", comps.year ?? 0, quarter)
    }
}
