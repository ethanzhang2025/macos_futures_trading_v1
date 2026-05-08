// ChartCore · WP-40 P1 · session-aware 时间轴辅助
//
// 职责：
//   - 识别 K 线序列中的 session/day 缺口（中午休市 / 夜盘日盘交替 / 跨日 / 周末）
//   - 判断单根 K 是否落在夜盘 session
//   - 算法仅基于 bar.openTime 时间戳差 + 周期 · 不依赖 ProductTradingHours（容错）
//   - ProductTradingHours 仅用于夜盘染色 / 标准开收盘标识
//
// 边界：
//   - 期望相邻 bar 时间差 = period.seconds（同 session 内）
//   - 实际差 > 2 × period 视作 session gap（中午 11:30→13:30 跨 75 分钟 / 11:30→13:00 跨 60 分钟）
//   - 实际差 > 360 分钟（6 小时）视作 day gap（昨日 15:00→今日 09:00 跨 18 小时 / 周末跨 60+ 小时）
//   - daily/weekly/monthly K 不检测（period 本身已大 · gap 无意义）
//
// 跨平台：纯 Foundation · Linux 端可参编

import Foundation
import Shared
import DataCore

/// session/day 缺口位置（在 barIndex 与 barIndex-1 之间）
public struct SessionGap: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case session  // 同日内 · 跨 session（午休 / 夜盘日盘衔接）
        case day      // 跨交易日 · 含周末 / 节假日
    }

    /// gap 位置：在 bars[barIndex - 1] 和 bars[barIndex] 之间
    public let barIndex: Int
    public let kind: Kind

    public init(barIndex: Int, kind: Kind) {
        self.barIndex = barIndex
        self.kind = kind
    }
}

public enum SessionAxisHelper {

    /// day gap 阈值：相邻 bar 间隔超过此秒数 = 跨日（含周末跨 60+ 小时）
    /// 6 小时 · 中国期货最长单 session 也仅 5h30m（21:00→02:30 夜盘）· 不会误判
    public static let dayGapThresholdSeconds: TimeInterval = 6 * 3600

    /// 检测可见范围内的 session/day 缺口
    /// - Parameters:
    ///   - bars: 全部 bars（已排序 · 升序时间戳）
    ///   - period: K 线周期（决定预期间隔 · daily 及以上不检测）
    ///   - startIndex / endIndexExclusive: 可视范围
    /// - Returns: 缺口数组（barIndex 升序 · 不含范围两端外的 gap）
    public static func detectGaps(
        bars: [KLine], period: KLinePeriod,
        startIndex: Int = 0, endIndexExclusive: Int? = nil
    ) -> [SessionGap] {
        // daily 及以上不检测（间隔 1+ 天本身就是设计良好的 · 周末缺口在数据层自然吸收）
        guard period.seconds < 86400 else { return [] }
        guard bars.count >= 2 else { return [] }

        let expected = TimeInterval(period.seconds)
        let sessionThreshold = expected * 2     // > 2 × period 即视作 session gap
        let dayThreshold = dayGapThresholdSeconds

        let lo = max(1, startIndex)
        let hi = min(endIndexExclusive ?? bars.count, bars.count)
        guard lo < hi else { return [] }

        var gaps: [SessionGap] = []
        for i in lo..<hi {
            let dt = bars[i].openTime.timeIntervalSince(bars[i - 1].openTime)
            if dt >= dayThreshold {
                gaps.append(SessionGap(barIndex: i, kind: .day))
            } else if dt > sessionThreshold {
                gaps.append(SessionGap(barIndex: i, kind: .session))
            }
        }
        return gaps
    }

    /// 给定时间是否落在某夜盘 session 内
    /// 算法：取 bar.openTime 的中国时区 (HH, MM)，遍历 hours.sessions 中 isNight=true 的区间
    /// 跨午夜的 session（如 21:00→02:30）做 endM<startM 处理
    public static func isInNightSession(
        date: Date, hours: ProductTradingHours,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let t = h * 60 + m
        for s in hours.sessions where s.isNight {
            let start = s.start.hour * 60 + s.start.minute
            let end = s.end.hour * 60 + s.end.minute
            if end > start {
                if t >= start && t < end { return true }
            } else {
                // 跨午夜（如 21:00→02:30）
                if t >= start || t < end { return true }
            }
        }
        return false
    }

    /// 把可视范围内的 bar 索引标记为夜盘/日盘段（连续段合并 · 用于背景染色）
    /// - Returns: [(startIdx, endIdxExclusive, isNight)] · 索引相对 bars 数组
    public static func nightSessionSegments(
        bars: [KLine], hours: ProductTradingHours,
        startIndex: Int, endIndexExclusive: Int
    ) -> [(start: Int, end: Int, isNight: Bool)] {
        guard startIndex < endIndexExclusive, startIndex >= 0, endIndexExclusive <= bars.count
        else { return [] }
        var segs: [(Int, Int, Bool)] = []
        var segStart = startIndex
        var segIsNight = isInNightSession(date: bars[startIndex].openTime, hours: hours)
        for i in (startIndex + 1)..<endIndexExclusive {
            let isNight = isInNightSession(date: bars[i].openTime, hours: hours)
            if isNight != segIsNight {
                segs.append((segStart, i, segIsNight))
                segStart = i
                segIsNight = isNight
            }
        }
        segs.append((segStart, endIndexExclusive, segIsNight))
        return segs
    }
}
