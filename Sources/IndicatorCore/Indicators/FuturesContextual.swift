// FuturesContextual.swift · 期货特有占位指标真实化（B1 Step 2 · 配 FuturesContext）
//
// 4 指标实现（IndicatorCore 期货指标 2/12 → 6/12）：
// - LimitPriceLines        · 涨跌停板线（输出 UPPER + LOWER · 用 dailyLimits）
// - DeliveryCountdown       · 交割日倒计时（输出 DAYS · 用 deliveryDate）
// - SettlementPriceLine     · 结算价线（输出 SETTLE · 用 dailySettlements）
// - SessionDivider          · 日盘/夜盘分界（输出 IN_SESSION 1/0 · 用 isInTradingSession）
//
// 设计取舍：
// - 全部 enum 实现（无状态 · 与 Indicators/MA.swift 等一致 · 单例语义）
// - barTimes 长度校验提取 fileprivate helper（4 指标共用）
// - 无对应数据点输出 nil（不抛错 · 让上层决定是否绘制）
// - SessionDivider 用 Asia/Shanghai 时区取 hour/minute（中国期货市场固定时区 · 与 TradingCalendar.chinaTimeZone 一致）

import Foundation
import Shared
import DataCore

/// 涨跌停板线（输出 UPPER + LOWER 两条 series）
public enum LimitPriceLines: ContextualIndicator {
    public static let identifier = "LIMIT"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(
        kline: KLineSeries,
        barTimes: [Date],
        context: FuturesContext,
        params: [Decimal]
    ) throws -> [IndicatorSeries] {
        try requireSameLength(kline: kline, barTimes: barTimes, label: "LIMIT")
        let count = kline.count
        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let limit = context.latestLimit(asOf: barTimes[i]) else { continue }
            upper[i] = limit.upperLimit
            lower[i] = limit.lowerLimit
        }
        return [
            IndicatorSeries(name: "UPPER", values: upper),
            IndicatorSeries(name: "LOWER", values: lower),
        ]
    }
}

/// 交割日倒计时（输出 DAYS 一条 · 距交割剩余整天数）
public enum DeliveryCountdown: ContextualIndicator {
    public static let identifier = "DELIVERY"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(
        kline: KLineSeries,
        barTimes: [Date],
        context: FuturesContext,
        params: [Decimal]
    ) throws -> [IndicatorSeries] {
        try requireSameLength(kline: kline, barTimes: barTimes, label: "DELIVERY")
        let count = kline.count
        var days = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let remaining = context.daysUntilDelivery(asOf: barTimes[i]) {
                days[i] = Decimal(remaining)
            }
        }
        return [IndicatorSeries(name: "DAYS", values: days)]
    }
}

/// 结算价线（输出 SETTLE 一条 · 取 <= 当前 bar 时间的最近结算价）
public enum SettlementPriceLine: ContextualIndicator {
    public static let identifier = "SETTLE"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(
        kline: KLineSeries,
        barTimes: [Date],
        context: FuturesContext,
        params: [Decimal]
    ) throws -> [IndicatorSeries] {
        try requireSameLength(kline: kline, barTimes: barTimes, label: "SETTLE")
        let settle: [Decimal?] = barTimes.map { context.latestSettlement(asOf: $0) }
        return [IndicatorSeries(name: "SETTLE", values: settle)]
    }
}

/// 日盘/夜盘分界（输出 IN_SESSION · 1=在交易时段，0=间隙）
public enum SessionDivider: ContextualIndicator {
    public static let identifier = "SESSION"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }()

    public static func calculate(
        kline: KLineSeries,
        barTimes: [Date],
        context: FuturesContext,
        params: [Decimal]
    ) throws -> [IndicatorSeries] {
        try requireSameLength(kline: kline, barTimes: barTimes, label: "SESSION")
        let inSession: [Decimal?] = barTimes.map { time in
            let comps = calendar.dateComponents([.hour, .minute], from: time)
            let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            return context.isInTradingSession(minuteOfDay: minuteOfDay) ? 1 : 0
        }
        return [IndicatorSeries(name: "IN_SESSION", values: inSession)]
    }
}

// MARK: - 共用 helper

private func requireSameLength(kline: KLineSeries, barTimes: [Date], label: String) throws {
    guard barTimes.count == kline.count else {
        throw IndicatorError.invalidParameter(
            "\(label): barTimes 长度（\(barTimes.count)）需等于 kline.count（\(kline.count)）"
        )
    }
}
