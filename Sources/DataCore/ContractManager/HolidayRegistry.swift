// WP-21a v15.18 · 中国节假日注册表（含节假日的交易日历计算）
//
// 设计取舍：
// - 协议先行 + Set<String> 数据驱动 · 业务侧 inject 节假日集合
// - 数据来源：每年国务院节假日通知（10 月份发布次年）+ 交易所春节调休补充
// - Stage A v1：空 registry（仅周末跳）· Stage B v2 接 JSON / CloudKit 同步
// - YYYYMMDD 字符串作为 key（与 TradingCalendar 现有 actionDay 格式一致）

import Foundation

public protocol HolidayRegistry: Sendable {
    /// 是否节假日（YYYYMMDD）
    func isHoliday(_ yyyymmdd: String) -> Bool

    /// 全部节假日集合（debug / UI 渲染用）
    var allHolidays: Set<String> { get }
}

/// 默认空 registry · v1 fallback · 仅 TradingCalendar 周末规则生效
public struct EmptyHolidayRegistry: HolidayRegistry {
    public init() {}
    public func isHoliday(_ yyyymmdd: String) -> Bool { false }
    public var allHolidays: Set<String> { [] }
}

/// 静态 registry · 测试 / 临时配置 · 注入 Set<String>
public struct StaticHolidayRegistry: HolidayRegistry {
    public let allHolidays: Set<String>
    public init(_ holidays: Set<String>) {
        self.allHolidays = holidays
    }
    public func isHoliday(_ yyyymmdd: String) -> Bool {
        allHolidays.contains(yyyymmdd)
    }
}

// MARK: - TradingCalendar 节假日扩展（v15.18）

public extension TradingCalendar {

    /// 判断给定日期是否非交易日（周末 OR 节假日）
    /// - Parameter actionDay: YYYYMMDD
    static func isNonTradingDay(_ actionDay: String, registry: any HolidayRegistry = EmptyHolidayRegistry()) -> Bool {
        if isWeekend(actionDay: actionDay) { return true }
        return registry.isHoliday(actionDay)
    }

    /// 返回 actionDay 之后下一个交易日（跳周末 + 跳节假日）
    /// - Parameters:
    ///   - actionDay: YYYYMMDD
    ///   - registry: 节假日注册表（默认空 = 仅跳周末）
    static func nextTradingDay(after actionDay: String, registry: any HolidayRegistry = EmptyHolidayRegistry()) -> String {
        var candidate = nextWeekday(after: actionDay)
        // 防死循环：最多跳 30 天（Stage B 春节连放 7+ 天 · 加 buffer）
        var safety = 30
        while registry.isHoliday(candidate), safety > 0 {
            candidate = nextWeekday(after: candidate)
            safety -= 1
        }
        return candidate
    }
}
