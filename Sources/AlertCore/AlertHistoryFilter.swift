// v15.19 batch23 · AlertHistory 时间区间筛选 + 统计（trader 模式分析 / 频次复盘）
//
// 设计取舍：
// - 纯函数 · 不动 store · UI 只过滤展示
// - dateRange 接 Calendar + TimeZone 注入便于测试
// - 统计：by 合约 / by 条件类型 / by 小时 → trader 看自己什么时段触发多

import Foundation

public enum AlertHistoryFilter {

    /// 5 类时间窗口（自定义留 UI 自己组装 from/to · 这里只覆盖常用预设）
    public enum Window: String, Sendable, CaseIterable, Identifiable {
        case today    = "今日"
        case week     = "本周"
        case month    = "本月"
        case last7d   = "近 7 天"
        case all      = "全部"
        public var id: String { rawValue }
    }

    /// 计算窗口的 (from, to] 区间 · all 返回 nil 表示不筛选
    public static func range(of window: Window, now: Date = Date(),
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current,
                             calendar: Calendar = Calendar(identifier: .gregorian)) -> (from: Date, to: Date)? {
        var cal = calendar
        cal.timeZone = timeZone
        switch window {
        case .all:
            return nil
        case .today:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .week:
            // 周一作为周起（中国习惯 · 与 ChinaFuturesHolidays 一致）
            cal.firstWeekday = 2
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let weekStart = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return (weekStart, now)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let monthStart = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return (monthStart, now)
        case .last7d:
            let from = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return (from, now)
        }
    }

    /// 应用窗口筛选
    public static func apply(_ entries: [AlertHistoryEntry], window: Window,
                             now: Date = Date(),
                             timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current) -> [AlertHistoryEntry] {
        guard let r = range(of: window, now: now, timeZone: timeZone) else { return entries }
        return entries.filter { $0.triggeredAt >= r.from && $0.triggeredAt <= r.to }
    }
}

// MARK: - AlertHistoryStatistics

public enum AlertHistoryStatistics {

    /// 6 类条件大类（CSV 同样使用 · 简化 trader 视角）
    public enum ConditionKind: String, Sendable, CaseIterable {
        case price        = "价格"
        case cross        = "上下穿"
        case breakout     = "突破"
        case lineTouched  = "画线触及"
        case spike        = "异动"
        case indicator    = "指标"

        public static func of(_ c: AlertCondition) -> ConditionKind {
            switch c {
            case .priceAbove, .priceBelow:                 return .price
            case .priceCrossAbove, .priceCrossBelow:       return .cross
            case .priceBreakoutHigh, .priceBreakoutLow:    return .breakout
            case .horizontalLineTouched:                   return .lineTouched
            case .volumeSpike, .openInterestSpike, .priceMoveSpike: return .spike
            case .indicator:                               return .indicator
            }
        }
    }

    /// v15.20 batch58 · 通用计数桶（替代 v15.19 batch23 的 (key, count) tuple · Equatable + Identifiable）
    /// SwiftUI ForEach 直接 ForEach(buckets) {...} 不再需要 .id(\.key)
    /// 测试可以 #expect(buckets == [Bucket(key:..., count:...)])
    public struct Bucket<K: Hashable & Sendable>: Sendable, Equatable, Identifiable {
        public let key: K
        public let count: Int
        public init(key: K, count: Int) {
            self.key = key
            self.count = count
        }
        public var id: K { key }
    }

    public struct Summary: Sendable, Equatable {
        public let total: Int
        public let byInstrument: [Bucket<String>]          // count 降序 · 同 count 按 key 升序
        public let byKind: [Bucket<ConditionKind>]         // count 降序
        public let byHour: [Int: Int]                       // hour(0-23) → count（Asia/Shanghai）

        public init(total: Int, byInstrument: [Bucket<String>], byKind: [Bucket<ConditionKind>], byHour: [Int: Int]) {
            self.total = total
            self.byInstrument = byInstrument
            self.byKind = byKind
            self.byHour = byHour
        }
    }

    public static func summarize(_ entries: [AlertHistoryEntry],
                                 timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current) -> Summary {
        var byInstrument: [String: Int] = [:]
        var byKind: [ConditionKind: Int] = [:]
        var byHour: [Int: Int] = [:]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        for e in entries {
            byInstrument[e.instrumentID, default: 0] += 1
            byKind[ConditionKind.of(e.conditionSnapshot), default: 0] += 1
            let h = cal.component(.hour, from: e.triggeredAt)
            byHour[h, default: 0] += 1
        }
        let sortedInst = byInstrument.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { Bucket(key: $0.key, count: $0.value) }
        let sortedKind = byKind.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }
            .map { Bucket(key: $0.key, count: $0.value) }
        return Summary(total: entries.count, byInstrument: sortedInst, byKind: sortedKind, byHour: byHour)
    }
}
