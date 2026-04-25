import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("交易日历测试")
struct TradingCalendarTests {
    @Test("黄金有夜盘到02:30")
    func testGoldNightSession() {
        let type = TradingCalendar.nightSessionType(for: "AU")
        #expect(type == .until0230)
    }

    @Test("螺纹钢有夜盘到23:30")
    func testRBNightSession() {
        let type = TradingCalendar.nightSessionType(for: "RB")
        #expect(type == .until2330)
    }

    @Test("豆粕有夜盘到23:00")
    func testMNightSession() {
        let type = TradingCalendar.nightSessionType(for: "M")
        #expect(type == .until2300)
    }

    @Test("股指期货无夜盘")
    func testIFNoNight() {
        let type = TradingCalendar.nightSessionType(for: "IF")
        #expect(type == .none)
    }

    @Test("交易时段查询 - 日盘内")
    func testDaySession() {
        let inSession = TradingCalendar.isInTradingHours(10, 0, productID: "RB", exchange: .SHFE)
        #expect(inSession == true)
    }

    @Test("交易时段查询 - 日盘外")
    func testOutOfDaySession() {
        let inSession = TradingCalendar.isInTradingHours(12, 0, productID: "RB", exchange: .SHFE)
        #expect(inSession == false)
    }

    @Test("交易时段查询 - 夜盘内")
    func testNightSession() {
        let inSession = TradingCalendar.isInTradingHours(22, 0, productID: "AU", exchange: .SHFE)
        #expect(inSession == true)
    }

    @Test("中金所交易时段")
    func testCFFEXSession() {
        let hours = TradingCalendar.tradingHours(for: "IF", exchange: .CFFEX)
        #expect(hours.hasNightSession == false)
        // 中金所日盘 9:30-11:30, 13:00-15:00
        let inSession = TradingCalendar.isInTradingHours(9, 30, productID: "IF", exchange: .CFFEX)
        #expect(inSession == true)
        let outSession = TradingCalendar.isInTradingHours(9, 0, productID: "IF", exchange: .CFFEX)
        #expect(outSession == false)
    }
}

// MARK: - WP-21a 子模块 5 · 边界 case 大幅补全

@Suite("交易时段 · 跨午夜夜盘边界（AU 21:00-02:30）")
struct CrossMidnightNightSessionTests {
    private let pid = "AU"
    private let ex = Exchange.SHFE

    @Test("21:00 夜盘开始（边界 inclusive）")
    func nightStart() {
        #expect(TradingCalendar.isInTradingHours(21, 0, productID: pid, exchange: ex))
    }

    @Test("20:59 夜盘开始前一分钟（不在交易）")
    func beforeNightStart() {
        #expect(!TradingCalendar.isInTradingHours(20, 59, productID: pid, exchange: ex))
    }

    @Test("23:00 夜盘进行中（同一自然日）")
    func nightMidEvening() {
        #expect(TradingCalendar.isInTradingHours(23, 0, productID: pid, exchange: ex))
    }

    @Test("00:30 凌晨夜盘进行中（跨午夜）")
    func pastMidnight() {
        #expect(TradingCalendar.isInTradingHours(0, 30, productID: pid, exchange: ex))
    }

    @Test("02:29 夜盘结束前一分钟（仍在）")
    func beforeNightEnd() {
        #expect(TradingCalendar.isInTradingHours(2, 29, productID: pid, exchange: ex))
    }

    @Test("02:30 夜盘结束（边界 exclusive）")
    func nightEndExclusive() {
        #expect(!TradingCalendar.isInTradingHours(2, 30, productID: pid, exchange: ex))
    }

    @Test("03:00 夜盘已结束")
    func afterNightEnd() {
        #expect(!TradingCalendar.isInTradingHours(3, 0, productID: pid, exchange: ex))
    }
}

@Suite("交易时段 · 午休 + 小休 + 休市边界（RB 普通日盘）")
struct DaySessionBreakTests {
    private let pid = "RB"
    private let ex = Exchange.SHFE

    @Test("09:00 日盘开始（边界 inclusive）")
    func dayStart() {
        #expect(TradingCalendar.isInTradingHours(9, 0, productID: pid, exchange: ex))
    }

    @Test("08:59 日盘前（不在交易）")
    func beforeDayStart() {
        #expect(!TradingCalendar.isInTradingHours(8, 59, productID: pid, exchange: ex))
    }

    @Test("10:15 上午第一段结束（边界 exclusive）")
    func morningSegment1End() {
        #expect(!TradingCalendar.isInTradingHours(10, 15, productID: pid, exchange: ex))
    }

    @Test("10:20 小休中")
    func morningBreak() {
        #expect(!TradingCalendar.isInTradingHours(10, 20, productID: pid, exchange: ex))
    }

    @Test("10:30 上午第二段开始")
    func morningSegment2Start() {
        #expect(TradingCalendar.isInTradingHours(10, 30, productID: pid, exchange: ex))
    }

    @Test("11:30 上午结束（边界 exclusive）→ 进入午休")
    func morningEnd() {
        #expect(!TradingCalendar.isInTradingHours(11, 30, productID: pid, exchange: ex))
    }

    @Test("12:00 午休中")
    func lunchBreak() {
        #expect(!TradingCalendar.isInTradingHours(12, 0, productID: pid, exchange: ex))
    }

    @Test("13:30 下午开始")
    func afternoonStart() {
        #expect(TradingCalendar.isInTradingHours(13, 30, productID: pid, exchange: ex))
    }

    @Test("13:29 下午开始前（不在交易）")
    func beforeAfternoonStart() {
        #expect(!TradingCalendar.isInTradingHours(13, 29, productID: pid, exchange: ex))
    }

    @Test("15:00 日盘结束（边界 exclusive）")
    func dayEnd() {
        #expect(!TradingCalendar.isInTradingHours(15, 0, productID: pid, exchange: ex))
    }

    @Test("18:00 收盘后到夜盘前（不在交易）")
    func eveningGap() {
        #expect(!TradingCalendar.isInTradingHours(18, 0, productID: pid, exchange: ex))
    }
}

@Suite("交易时段 · 中金所边界（IF 9:30-11:30 / 13:00-15:00 · 无夜盘）")
struct CFFEXBoundaryTests {
    private let pid = "IF"
    private let ex = Exchange.CFFEX

    @Test("09:29 开盘前一分钟")
    func before() {
        #expect(!TradingCalendar.isInTradingHours(9, 29, productID: pid, exchange: ex))
    }

    @Test("09:30 开盘 inclusive")
    func openInclusive() {
        #expect(TradingCalendar.isInTradingHours(9, 30, productID: pid, exchange: ex))
    }

    @Test("11:30 上午结束 exclusive")
    func morningEndExclusive() {
        #expect(!TradingCalendar.isInTradingHours(11, 30, productID: pid, exchange: ex))
    }

    @Test("13:00 下午开始 inclusive（与上海期货所 13:30 不同）")
    func afternoonOpensEarlier() {
        #expect(TradingCalendar.isInTradingHours(13, 0, productID: pid, exchange: ex))
        // 同一时刻在 SHFE 商品期货还在午休
        #expect(!TradingCalendar.isInTradingHours(13, 0, productID: "RB", exchange: .SHFE))
    }

    @Test("21:00 中金所无夜盘（不在交易）")
    func noNightSession() {
        #expect(!TradingCalendar.isInTradingHours(21, 0, productID: pid, exchange: ex))
    }
}

// MARK: - WP-21a 子模块 5 · expectedTradingDay / 周末判断 / nextWeekday

@Suite("expectedTradingDay · Tick 交易日归属")
struct ExpectedTradingDayTests {

    @Test("日盘时段 → 当日交易日")
    func dayHourReturnsActionDay() {
        // 2026-04-27 周一 10:00
        #expect(TradingCalendar.expectedTradingDay(actionDay: "20260427", hour: 10) == "20260427")
    }

    @Test("夜盘开始（21:00）→ 下一工作日")
    func nightHourReturnsNextWeekday() {
        // 2026-04-27 周一 21:00 → 周二 04-28
        #expect(TradingCalendar.expectedTradingDay(actionDay: "20260427", hour: 21) == "20260428")
    }

    @Test("周五夜盘 → 跳过周末到下周一")
    func fridayNightSkipsWeekend() {
        // 2026-05-01 周五 21:00 → 跳到周一 05-04
        #expect(TradingCalendar.expectedTradingDay(actionDay: "20260501", hour: 21) == "20260504")
    }

    @Test("凌晨夜盘（hour < 3）→ 当日 actionDay（CTP 已对齐）")
    func midnightHourReturnsActionDay() {
        // 2026-04-28 周二 02:00 凌晨夜盘 → 仍是周二 04-28（CTP 字段 actionDay 已是次日）
        #expect(TradingCalendar.expectedTradingDay(actionDay: "20260428", hour: 2) == "20260428")
    }

    @Test("传统 tradingDay(actionDay:updateTime:) 与 expectedTradingDay 行为一致")
    func legacyAPIConsistent() {
        let actionDay = "20260427"
        let cases: [(String, Int)] = [
            ("10:00:00", 10),
            ("21:30:00", 21),
            ("02:00:00", 2),
        ]
        for (updateTime, hour) in cases {
            let legacy = TradingCalendar.tradingDay(actionDay: actionDay, updateTime: updateTime)
            let expected = TradingCalendar.expectedTradingDay(actionDay: actionDay, hour: hour)
            #expect(legacy == expected)
        }
    }
}

@Suite("isWeekend / nextWeekday")
struct WeekendUtilTests {

    @Test("isWeekend：周六/周日 true，工作日 false")
    func weekendDetection() {
        #expect(TradingCalendar.isWeekend(actionDay: "20260502") == true)   // 周六
        #expect(TradingCalendar.isWeekend(actionDay: "20260503") == true)   // 周日
        #expect(TradingCalendar.isWeekend(actionDay: "20260504") == false)  // 周一
        #expect(TradingCalendar.isWeekend(actionDay: "20260501") == false)  // 周五
    }

    @Test("isWeekend：非法日期返回 false（fail-safe）")
    func invalidDate() {
        #expect(TradingCalendar.isWeekend(actionDay: "not-a-date") == false)
        #expect(TradingCalendar.isWeekend(actionDay: "2026") == false)
    }

    @Test("nextWeekday：周一 → 周二")
    func weekdayToNextWeekday() {
        #expect(TradingCalendar.nextWeekday(after: "20260427") == "20260428")
    }

    @Test("nextWeekday：周五 → 跳过周末到下周一")
    func fridayToMonday() {
        #expect(TradingCalendar.nextWeekday(after: "20260501") == "20260504")
    }

    @Test("nextWeekday：周六 → 周一")
    func saturdayToMonday() {
        #expect(TradingCalendar.nextWeekday(after: "20260502") == "20260504")
    }

    @Test("nextWeekday：周日 → 周一")
    func sundayToMonday() {
        #expect(TradingCalendar.nextWeekday(after: "20260503") == "20260504")
    }

    @Test("nextWeekday：跨月（4 月 30 周四 → 5 月 1 周五）")
    func monthBoundary() {
        #expect(TradingCalendar.nextWeekday(after: "20260430") == "20260501")
    }

    @Test("nextWeekday：非法日期返回原值（fail-safe）")
    func invalidDateReturnsOriginal() {
        #expect(TradingCalendar.nextWeekday(after: "bad-date") == "bad-date")
    }
}
