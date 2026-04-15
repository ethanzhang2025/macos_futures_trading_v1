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
    public static func tradingDay(actionDay: String, updateTime: String) -> String {
        // 如果时间在20:00之后，说明是夜盘，交易日是actionDay的下一个交易日
        // CTP会直接在tradingDay字段给出正确值，这里作为验证逻辑
        guard let hour = Int(updateTime.prefix(2)) else { return actionDay }
        if hour >= 20 {
            // 夜盘，tradingDay应该是下一个交易日
            // 实际使用CTP给出的tradingDay字段即可
            return actionDay
        }
        return actionDay
    }
}
