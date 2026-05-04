// WP-21a v15.18 · 中国期货节假日数据单测

import Testing
import Foundation
@testable import DataCore

@Suite("ChinaFuturesHolidays · 2026/2027 节假日数据")
struct ChinaFuturesHolidaysTests {

    @Test("2026 元旦 / 春节 / 国庆 在册")
    func keyHolidays2026Present() {
        let holidays = ChinaFuturesHolidays.yyyyHolidays2026
        #expect(holidays.contains("20260101"))    // 元旦
        #expect(holidays.contains("20260216"))    // 春节首日
        #expect(holidays.contains("20261001"))    // 国庆首日
        #expect(holidays.contains("20260501"))    // 劳动节
    }

    @Test("普通工作日不在节假日列表（如 2026-03-15 周日 · 实为周末但不算 holiday）")
    func ordinaryWorkdayNotInList() {
        let holidays = ChinaFuturesHolidays.allKnown
        #expect(!holidays.contains("20260301"))   // 周日 · 周末由 isWeekend 处理
        #expect(!holidays.contains("20260615"))   // 普通工作日
    }

    @Test("shared registry 是 StaticHolidayRegistry 包装 allKnown")
    func sharedRegistryWiredCorrectly() {
        let registry = ChinaFuturesHolidays.shared
        #expect(registry.isHoliday("20260101"))
        #expect(registry.isHoliday("20260615") == false)
        #expect(registry.allHolidays == ChinaFuturesHolidays.allKnown)
    }

    @Test("nextTradingDay 用 ChinaFuturesHolidays · 春节连放跳到节后")
    func nextTradingDaySkipsSpringFestival() {
        // 2026-02-13 周五 · 假期 02-16 ~ 02-22 · 02-23 周一恢复
        let next = TradingCalendar.nextTradingDay(after: "20260213", registry: ChinaFuturesHolidays.shared)
        #expect(next == "20260223")
    }

    @Test("isNonTradingDay · 2026-10-01 国庆 = true")
    func nationalDayIsNonTrading() {
        #expect(TradingCalendar.isNonTradingDay("20261001", registry: ChinaFuturesHolidays.shared))
    }

    @Test("allKnown 跨 2026 + 2027 合并（数量 > 30）")
    func allKnownCoversTwoYears() {
        #expect(ChinaFuturesHolidays.allKnown.count > 30)
    }
}
