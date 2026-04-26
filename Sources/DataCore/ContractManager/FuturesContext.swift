// FuturesContext · 期货合约 + 每日动态数据视图
//
// 用途：
// - 为 IndicatorCore 占位指标提供真实数据输入（A1 骨架支持 4 项指标真实化）：
//   · LimitPriceLines      （涨跌停板线 · 用 dailyLimits）
//   · DeliveryCountdown     （交割日倒计时 · 用 deliveryDate）
//   · SettlementPriceLine   （结算价线 · 用 dailySettlements）
//   · SessionDivider        （日盘/夜盘分界 · 用 tradingHours · isInTradingSession）
// - 平级 KLineSeries · 后续作为指标第二输入（IndicatorCore 调用方式：
//   `LimitPriceLines.calculate(kline:, context:)`）
//
// 设计取舍：
// - 复用 DataCore 已有 ProductSpec + ProductTradingHours · 不重复字段
// - 新增 DailyLimit / DailySettlement 表达每日动态数据
// - dailyLimits / dailySettlements init 时按 tradingDay 升序排序（latest 查询 O(N) 反向扫）
// - 跨日夜盘：endMinute < startMinute 表达（如 21:00 → 02:30 · isInTradingSession 已处理）
// - A1 骨架：只定义类型 + 简单查询；不接 CTP / 不实际拉数据 · Step 2/3 接 IndicatorCore

import Foundation

/// 单日涨跌停（按交易日聚合）
public struct DailyLimit: Sendable, Equatable, Codable, Hashable {
    /// 交易日（建议传 Asia/Shanghai 当天 00:00:00）
    public let tradingDay: Date
    public let upperLimit: Decimal
    public let lowerLimit: Decimal

    public init(tradingDay: Date, upperLimit: Decimal, lowerLimit: Decimal) {
        self.tradingDay = tradingDay
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
    }
}

/// 单日结算价（按交易日聚合）
public struct DailySettlement: Sendable, Equatable, Codable, Hashable {
    public let tradingDay: Date
    public let settlementPrice: Decimal

    public init(tradingDay: Date, settlementPrice: Decimal) {
        self.tradingDay = tradingDay
        self.settlementPrice = settlementPrice
    }
}

/// 期货合约 + 每日动态数据视图（指标计算上下文）
/// - Note: 不做 Equatable · ProductSpec/ProductTradingHours 在另一文件不可跨文件合成；
///   测试需要时按 dailyLimits/dailySettlements/instrumentID 等字段单独比较
public struct FuturesContext: Sendable {
    /// 合约 ID（如 "RB2510"）
    public let instrumentID: String
    /// 品种规格（复用 ProductSpec · 含 multiple/priceTick 等）
    public let productSpec: ProductSpec
    /// 交易时段（复用 ProductTradingHours · 含 sessions/夜盘）
    public let tradingHours: ProductTradingHours?
    /// 上市日（合约级 · 不在 ProductSpec）
    public let listingDate: Date?
    /// 交割日
    public let deliveryDate: Date?
    /// 每日涨跌停（init 时按 tradingDay 升序）
    public let dailyLimits: [DailyLimit]
    /// 每日结算价（init 时按 tradingDay 升序）
    public let dailySettlements: [DailySettlement]

    public init(
        instrumentID: String,
        productSpec: ProductSpec,
        tradingHours: ProductTradingHours? = nil,
        listingDate: Date? = nil,
        deliveryDate: Date? = nil,
        dailyLimits: [DailyLimit] = [],
        dailySettlements: [DailySettlement] = []
    ) {
        self.instrumentID = instrumentID
        self.productSpec = productSpec
        self.tradingHours = tradingHours
        self.listingDate = listingDate
        self.deliveryDate = deliveryDate
        self.dailyLimits = dailyLimits.sorted { $0.tradingDay < $1.tradingDay }
        self.dailySettlements = dailySettlements.sorted { $0.tradingDay < $1.tradingDay }
    }

    // MARK: - 查询 helper

    /// 距交割剩余整天数（>=0）；过期或未设交割日返回 nil
    /// - Note: A1 简单实现 · 用 timeIntervalSince / 86400 trunc 向 0 · 不做 Asia/Shanghai 日历跨天
    public func daysUntilDelivery(asOf date: Date) -> Int? {
        guard let deliveryDate else { return nil }
        let interval = deliveryDate.timeIntervalSince(date)
        guard interval >= 0 else { return nil }
        return Int(interval / 86_400)
    }

    /// 给定交易日精确查询当日涨跌停（同日判定 · 默认 Calendar 时区）
    public func limit(onTradingDay day: Date) -> DailyLimit? {
        dailyLimits.first { Self.sameDayCalendar.isDate($0.tradingDay, inSameDayAs: day) }
    }

    /// 最近一个交易日 <= asOf 的涨跌停（用于实时取最新已发布的）
    public func latestLimit(asOf date: Date) -> DailyLimit? {
        dailyLimits.last { $0.tradingDay <= date }
    }

    /// 给定交易日精确查询当日结算价
    public func settlement(onTradingDay day: Date) -> Decimal? {
        dailySettlements.first { Self.sameDayCalendar.isDate($0.tradingDay, inSameDayAs: day) }?.settlementPrice
    }

    /// 最近一个交易日 <= asOf 的结算价
    public func latestSettlement(asOf date: Date) -> Decimal? {
        dailySettlements.last { $0.tradingDay <= date }?.settlementPrice
    }

    /// 给定一日内分钟数（0-1439），判断是否在任何交易时段内
    /// - Note: 跨日 session（如夜盘 21:00 → 02:30）以 endM < startM 表达
    public func isInTradingSession(minuteOfDay: Int) -> Bool {
        guard let tradingHours else { return false }
        for session in tradingHours.sessions {
            let startM = session.start.hour * 60 + session.start.minute
            let endM = session.end.hour * 60 + session.end.minute
            if endM > startM {
                if minuteOfDay >= startM && minuteOfDay < endM { return true }
            } else {
                // 跨日：minuteOfDay 落在 [startM, 1440) 或 [0, endM) 之内
                if minuteOfDay >= startM || minuteOfDay < endM { return true }
            }
        }
        return false
    }

    // MARK: - 私有
    /// 同日判定共享 Calendar（默认时区 · 与字段注释 "建议传 Asia/Shanghai 00:00:00" 配合使用）
    private static let sameDayCalendar = Calendar(identifier: .gregorian)
}
