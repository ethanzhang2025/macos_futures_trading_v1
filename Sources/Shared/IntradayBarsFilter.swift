// v17.171 · 盘中复盘工具（M6 卖点 · trader 每晚必复盘）
//
// 用途：
//   trader 选定某一天 · 把当日 bars 单独拎出来做回放（看自己当天判断 vs 实际走势）
//   v1 简单 · 不接 tick 数据库 · 直接用已有 bars 数组 + 日期过滤
//
// 设计：
// - filter(bars: date: warmUp:) · 过滤到目标日的 bars + 前 N 根预热（让指标有数据可计算）
// - availableDates(in:) · 返回 bars 内出现过的所有交易日（startOfDay 去重排序）· UI 用作 date picker 可选范围
//
// 注意：
// - 日期判定基于 Calendar.current 的"同一天" · 期货夜盘 21:00-02:30 跨自然日仍属"同一交易日"
//   这里 v1 用 Calendar 自然日 · v2 可加交易日历

import Foundation

public enum IntradayBarsFilter {

    /// 过滤 bars 到指定 date 的当日范围 + 前 N 根预热（用于让指标 EMA/MACD 有 warm-up 不全 nil）
    /// - Parameters:
    ///   - bars: 全部 bars（按 openTime 升序）
    ///   - date: 目标日（取 Calendar 自然日 · 期货夜盘 v2 优化）
    ///   - precedingWarmUp: 当日首根之前再往前取多少根作为预热（默认 60 · 1 小时 minute1 或 5 小时 minute5）
    ///   - calendar: 计算"同一天" 用的 calendar · 默认 .current
    public static func filter(
        bars: [KLine],
        date: Date,
        precedingWarmUp: Int = 60,
        calendar: Calendar = .current
    ) -> [KLine] {
        guard !bars.isEmpty else { return [] }
        guard let firstInDay = bars.firstIndex(where: { calendar.isDate($0.openTime, inSameDayAs: date) }) else {
            return []
        }
        guard let lastInDay = bars.lastIndex(where: { calendar.isDate($0.openTime, inSameDayAs: date) }) else {
            return []
        }
        let warmUpStart = max(0, firstInDay - max(0, precedingWarmUp))
        return Array(bars[warmUpStart...lastInDay])
    }

    /// 返回 bars 内出现过的所有交易日（startOfDay 去重 · 按时间升序）
    public static func availableDates(in bars: [KLine], calendar: Calendar = .current) -> [Date] {
        guard !bars.isEmpty else { return [] }
        var seen = Set<Date>()
        var out: [Date] = []
        for bar in bars {
            let day = calendar.startOfDay(for: bar.openTime)
            if seen.insert(day).inserted { out.append(day) }
        }
        return out.sorted()
    }

    /// 返回目标日在 bars 内的 [firstIndex, lastIndex] 区间（不算 warmUp）· 闭区间
    /// 用途：UI 在 chart 上画"今日开始"垂直线时定位 firstInDay 像素
    public static func dayRange(
        in bars: [KLine],
        date: Date,
        calendar: Calendar = .current
    ) -> (firstIndex: Int, lastIndex: Int)? {
        guard let first = bars.firstIndex(where: { calendar.isDate($0.openTime, inSameDayAs: date) }) else {
            return nil
        }
        guard let last = bars.lastIndex(where: { calendar.isDate($0.openTime, inSameDayAs: date) }) else {
            return nil
        }
        return (first, last)
    }
}
