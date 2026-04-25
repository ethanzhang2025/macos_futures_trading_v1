import Foundation
import Shared

/// 交易时段
public struct TradingSession: Sendable {
    public let start: (hour: Int, minute: Int)
    public let end: (hour: Int, minute: Int)
    public let isNight: Bool

    public init(start: (Int, Int), end: (Int, Int), isNight: Bool = false) {
        self.start = start
        self.end = end
        self.isNight = isNight
    }
}

/// 品种交易时段配置
public struct ProductTradingHours: Sendable {
    public let productID: String
    public let sessions: [TradingSession]

    public init(productID: String, sessions: [TradingSession]) {
        self.productID = productID
        self.sessions = sessions
    }

    public var hasNightSession: Bool {
        sessions.contains { $0.isNight }
    }
}

/// 交易日历
public struct TradingCalendar: Sendable {
    /// 夜盘时段类型
    public enum NightSessionType: Sendable {
        case none                    // 无夜盘
        case until2300               // 21:00-23:00 (有色金属等)
        case until2330               // 21:00-23:30 (天然橡胶等)
        case until0100               // 21:00-01:00 (铜/铝/锌等)
        case until0230               // 21:00-02:30 (黄金/白银/原油)
    }

    /// 日盘交易时段（所有品种通用）
    public static let daySessions: [TradingSession] = [
        TradingSession(start: (9, 0), end: (10, 15)),
        TradingSession(start: (10, 30), end: (11, 30)),
        TradingSession(start: (13, 30), end: (15, 0)),
    ]

    /// 金融期货日盘时段（中金所）
    public static let cffexDaySessions: [TradingSession] = [
        TradingSession(start: (9, 30), end: (11, 30)),
        TradingSession(start: (13, 0), end: (15, 0)),
    ]

    /// 根据品种获取夜盘类型
    public static func nightSessionType(for productID: String) -> NightSessionType {
        let upper = productID.uppercased()
        switch upper {
        // 21:00-02:30
        case "AU", "AG", "SC":
            return .until0230
        // 21:00-01:00
        case "CU", "AL", "ZN", "PB", "NI", "SN", "BC":
            return .until0100
        // 21:00-23:30
        case "RU", "FU", "BU", "SP", "RB", "HC", "SS":
            return .until2330
        // 21:00-23:00
        case "A", "B", "M", "Y", "P", "C", "CS", "JD", "LH",
             "L", "PP", "V", "EB", "EG", "PG",
             "I", "J", "JM",
             "SR", "CF", "RM", "OI", "MA", "TA", "FG", "SA",
             "ZC", "SF", "SM", "UR", "PK", "PF", "CY", "AP", "CJ":
            return .until2300
        // 无夜盘
        default:
            return .none
        }
    }

    /// 获取品种的完整交易时段
    public static func tradingHours(for productID: String, exchange: Exchange) -> ProductTradingHours {
        var sessions: [TradingSession] = []

        // 夜盘
        let nightType = nightSessionType(for: productID)
        switch nightType {
        case .none:
            break
        case .until2300:
            sessions.append(TradingSession(start: (21, 0), end: (23, 0), isNight: true))
        case .until2330:
            sessions.append(TradingSession(start: (21, 0), end: (23, 30), isNight: true))
        case .until0100:
            sessions.append(TradingSession(start: (21, 0), end: (1, 0), isNight: true))
        case .until0230:
            sessions.append(TradingSession(start: (21, 0), end: (2, 30), isNight: true))
        }

        // 日盘
        if exchange == .CFFEX {
            sessions.append(contentsOf: Self.cffexDaySessions)
        } else {
            sessions.append(contentsOf: Self.daySessions)
        }

        return ProductTradingHours(productID: productID, sessions: sessions)
    }

    /// 判断给定时间是否在交易时段内
    public static func isInTradingHours(_ hour: Int, _ minute: Int, productID: String, exchange: Exchange) -> Bool {
        let hours = tradingHours(for: productID, exchange: exchange)
        let timeInMinutes = hour * 60 + minute
        for session in hours.sessions {
            let start = session.start.hour * 60 + session.start.minute
            let end = session.end.hour * 60 + session.end.minute
            if end > start {
                if timeInMinutes >= start && timeInMinutes < end { return true }
            } else {
                // 跨午夜
                if timeInMinutes >= start || timeInMinutes < end { return true }
            }
        }
        return false
    }

    /// 判断Tick的交易日归属
    /// 夜盘的Tick属于下一个交易日
    /// - Note: 实际生产中应直接使用 CTP 提供的 tradingDay 字段（CTP 已含节假日数据）；
    ///         本函数仅供 PoC 验证 / 离线数据回放归属计算
    public static func tradingDay(actionDay: String, updateTime: String) -> String {
        guard let hour = Int(updateTime.prefix(2)) else { return actionDay }
        return expectedTradingDay(actionDay: actionDay, hour: hour)
    }

    // MARK: - WP-21a 子模块 5 · 夜盘归属 + 周末跳过

    /// 计算 Tick 的预期交易日归属（夜盘归属下一工作日）
    /// 边界规则：
    /// - actionDay 20:00 之后（夜盘开始） → tradingDay = nextWeekday(actionDay)
    /// - actionDay 03:00 之前（凌晨夜盘） → tradingDay = actionDay（CTP 在跨日时已把 actionDay 设为次日自然日，本日凌晨的 tradingDay 等于 actionDay 本身）
    /// - 其他时段（日盘） → tradingDay = actionDay
    /// - Parameters:
    ///   - actionDay: 自然日 YYYYMMDD（CTP Tick 的 actionDay 字段）
    ///   - hour: 0-23
    /// - Note: 不含节假日表（v2 接 JSON），仅跳周末
    public static func expectedTradingDay(actionDay: String, hour: Int) -> String {
        if hour < 3 { return actionDay }
        if hour >= 20 { return nextWeekday(after: actionDay) }
        return actionDay
    }

    /// 判断给定日期是否是周末
    /// - Parameter actionDay: YYYYMMDD 格式
    /// - Returns: 解析失败返回 false
    public static func isWeekend(actionDay: String) -> Bool {
        guard let date = parseDate(actionDay) else { return false }
        return isWeekendDate(date, calendar: chinaCalendar)
    }

    /// 返回 actionDay 之后下一个非周末日（不含节假日表）
    /// - Parameter actionDay: YYYYMMDD 格式
    /// - Returns: 下一个非周末的 YYYYMMDD；解析失败返回原值
    public static func nextWeekday(after actionDay: String) -> String {
        guard let date = parseDate(actionDay) else { return actionDay }
        let calendar = chinaCalendar
        guard var next = calendar.date(byAdding: .day, value: 1, to: date) else { return actionDay }
        while isWeekendDate(next, calendar: calendar) {
            guard let advanced = calendar.date(byAdding: .day, value: 1, to: next) else { break }
            next = advanced
        }
        return formatDate(next)
    }

    // MARK: - 私有：日期解析（不依赖 DateFormatter，避免 Sendable 顾虑 + 性能开销）

    private static let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let chinaCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = chinaTimeZone
        return c
    }()

    private static func parseDate(_ yyyymmdd: String) -> Date? {
        guard yyyymmdd.count == 8,
              let year = Int(yyyymmdd.prefix(4)),
              let month = Int(yyyymmdd.dropFirst(4).prefix(2)),
              let day = Int(yyyymmdd.suffix(2))
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return chinaCalendar.date(from: components)
    }

    private static func formatDate(_ date: Date) -> String {
        let c = chinaCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func isWeekendDate(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7  // 1 = Sunday, 7 = Saturday
    }
}
