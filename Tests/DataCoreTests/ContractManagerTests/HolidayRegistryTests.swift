// WP-21a v15.18 · HolidayRegistry + TradingCalendar 节假日扩展单测

import Testing
import Foundation
@testable import DataCore
import Shared

@Suite("HolidayRegistry · 节假日跳跃")
struct HolidayRegistryTests {

    @Test("EmptyRegistry · 全部 false")
    func emptyRegistry() {
        let r = EmptyHolidayRegistry()
        #expect(r.isHoliday("20260101") == false)
        #expect(r.isHoliday("20260501") == false)
        #expect(r.allHolidays.isEmpty)
    }

    @Test("StaticRegistry · Set 注入 · 命中返回 true")
    func staticRegistry() {
        let r = StaticHolidayRegistry(["20260101", "20260202", "20260203"])
        #expect(r.isHoliday("20260101"))
        #expect(r.isHoliday("20260202"))
        #expect(r.isHoliday("20260100") == false)
        #expect(r.allHolidays.count == 3)
    }

    @Test("isNonTradingDay · 周末 OR 节假日（OR 关系）")
    func isNonTradingDayCovers() {
        // 2026-01-01 是周四 · 不是周末 · 但是元旦节假日
        let r = StaticHolidayRegistry(["20260101"])
        #expect(TradingCalendar.isNonTradingDay("20260101", registry: r))
        // 2026-05-09 是周六 · 周末 · 不在 registry
        #expect(TradingCalendar.isNonTradingDay("20260509", registry: r))
        // 2026-05-04 是周一 · 不在 registry · 工作日
        #expect(!TradingCalendar.isNonTradingDay("20260504", registry: r))
    }

    @Test("nextTradingDay · 跳周末 + 跳节假日")
    func nextTradingDaySkipsHolidays() {
        // 2026-04-30 周四 · 假设 5/1 5/2 5/3 都放假 · 5/4 周一
        let r = StaticHolidayRegistry(["20260501", "20260502", "20260503"])
        let next = TradingCalendar.nextTradingDay(after: "20260430", registry: r)
        #expect(next == "20260504")
    }

    @Test("nextTradingDay · 默认空 registry · 仅跳周末（与 nextWeekday 一致）")
    func defaultRegistryOnlySkipsWeekend() {
        // 2026-05-08 周五 · next = 5/11 周一（跳过 9 周六 / 10 周日）
        let next = TradingCalendar.nextTradingDay(after: "20260508")
        #expect(next == "20260511")
    }

    @Test("nextTradingDay · 长连假场景（春节模拟 7 天连放）")
    func longHolidayBlock() {
        // 2026 春节假设 02-16 ~ 02-22 连放 7 天
        let r = StaticHolidayRegistry([
            "20260216", "20260217", "20260218", "20260219",
            "20260220"   // 5 个工作日 · 周末自然跳
        ])
        // 02-13 周五 → 跳到 02-23 周一
        let next = TradingCalendar.nextTradingDay(after: "20260213", registry: r)
        #expect(next == "20260223")
    }
}
