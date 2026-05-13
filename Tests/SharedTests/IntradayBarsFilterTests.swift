// v17.171 · IntradayBarsFilter 单测
//
// 覆盖：
// - filter · 完整 1 天 · 数量 + 边界
// - filter · 前 warmUp clamp 到 0
// - filter · 目标日不存在 · 返回空
// - filter · 跨多天 · 只截目标日 + 预热
// - filter · 空 bars · 空
// - availableDates · 去重 + 排序
// - availableDates · 空 bars · 空
// - dayRange · 命中 first/last
// - dayRange · 目标日不存在 · nil

import Testing
import Foundation
@testable import Shared

@Suite("v17.171 · IntradayBarsFilter 盘中复盘过滤")
struct IntradayBarsFilterTests {

    @Test("filter · 完整 1 天 · warmUp 取前 60 根 · 数量 + 边界正确")
    func filterFullDayWithWarmUp() {
        // 第一天 100 根（00:00 - 01:39 minute1）· 第二天 100 根
        var bars: [KLine] = []
        let day1Start = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        let day2Start = makeDate(year: 2024, month: 12, day: 16, hour: 0, minute: 0)
        for i in 0..<100 { bars.append(makeBar(openTime: day1Start.addingTimeInterval(TimeInterval(i * 60)))) }
        for i in 0..<100 { bars.append(makeBar(openTime: day2Start.addingTimeInterval(TimeInterval(i * 60)))) }

        let filtered = IntradayBarsFilter.filter(
            bars: bars,
            date: day2Start,
            precedingWarmUp: 60,
            calendar: utcCalendar()
        )
        // 60 warmUp + 100 (day2) = 160
        #expect(filtered.count == 160)
        // 头根 = bars[40]（100 - 60 = 40）
        #expect(filtered.first?.openTime == bars[40].openTime)
        // 末根 = bars[199]
        #expect(filtered.last?.openTime == bars[199].openTime)
    }

    @Test("filter · 前 warmUp 超出 bars 起点 · clamp 到 0")
    func filterWarmUpClampsToZero() {
        var bars: [KLine] = []
        let day1Start = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        for i in 0..<10 { bars.append(makeBar(openTime: day1Start.addingTimeInterval(TimeInterval(i * 60)))) }

        let filtered = IntradayBarsFilter.filter(
            bars: bars,
            date: day1Start,
            precedingWarmUp: 60,  // 远超 bars.count
            calendar: utcCalendar()
        )
        #expect(filtered.count == 10)
        #expect(filtered.first?.openTime == bars[0].openTime)
    }

    @Test("filter · 目标日不在 bars 中 · 返回空")
    func filterMissingDateReturnsEmpty() {
        let day1Start = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        let bars = [makeBar(openTime: day1Start)]
        let missing = makeDate(year: 2024, month: 12, day: 20, hour: 0, minute: 0)
        let filtered = IntradayBarsFilter.filter(bars: bars, date: missing, calendar: utcCalendar())
        #expect(filtered.isEmpty)
    }

    @Test("filter · 跨多天 · 只截目标日 · warmUp 取自上一天")
    func filterMiddleDay() {
        var bars: [KLine] = []
        // 3 天 · 每天 5 根
        for d in 15...17 {
            let dayStart = makeDate(year: 2024, month: 12, day: d, hour: 0, minute: 0)
            for i in 0..<5 { bars.append(makeBar(openTime: dayStart.addingTimeInterval(TimeInterval(i * 60)))) }
        }
        let day16 = makeDate(year: 2024, month: 12, day: 16, hour: 0, minute: 0)
        let filtered = IntradayBarsFilter.filter(
            bars: bars,
            date: day16,
            precedingWarmUp: 3,
            calendar: utcCalendar()
        )
        // day16 占 bars[5..9] · 前 3 根 warmUp = bars[2..4]（仍在 day15）· 总 8 根
        #expect(filtered.count == 8)
        #expect(filtered.first?.openTime == bars[2].openTime)
        #expect(filtered.last?.openTime == bars[9].openTime)
    }

    @Test("filter · 空 bars · 返回空")
    func filterEmptyBars() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 0, minute: 0)
        let filtered = IntradayBarsFilter.filter(bars: [], date: date)
        #expect(filtered.isEmpty)
    }

    @Test("availableDates · 多天 bars · 去重 + 升序")
    func availableDatesDedupedSorted() {
        let d1 = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        let d2 = makeDate(year: 2024, month: 12, day: 16, hour: 0, minute: 0)
        let d3 = makeDate(year: 2024, month: 12, day: 17, hour: 0, minute: 0)
        let bars = [
            makeBar(openTime: d2),
            makeBar(openTime: d2.addingTimeInterval(60)),
            makeBar(openTime: d1),
            makeBar(openTime: d3),
            makeBar(openTime: d1.addingTimeInterval(120))
        ]
        let dates = IntradayBarsFilter.availableDates(in: bars, calendar: utcCalendar())
        #expect(dates.count == 3)
        let cal = utcCalendar()
        #expect(cal.isDate(dates[0], inSameDayAs: d1))
        #expect(cal.isDate(dates[1], inSameDayAs: d2))
        #expect(cal.isDate(dates[2], inSameDayAs: d3))
    }

    @Test("availableDates · 空 bars · 空")
    func availableDatesEmpty() {
        #expect(IntradayBarsFilter.availableDates(in: []).isEmpty)
    }

    @Test("dayRange · 命中 · 返回 first/last 索引")
    func dayRangeHits() {
        var bars: [KLine] = []
        let d1 = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        let d2 = makeDate(year: 2024, month: 12, day: 16, hour: 0, minute: 0)
        for i in 0..<5 { bars.append(makeBar(openTime: d1.addingTimeInterval(TimeInterval(i * 60)))) }
        for i in 0..<7 { bars.append(makeBar(openTime: d2.addingTimeInterval(TimeInterval(i * 60)))) }

        let range = IntradayBarsFilter.dayRange(in: bars, date: d2, calendar: utcCalendar())
        #expect(range?.firstIndex == 5)
        #expect(range?.lastIndex == 11)
    }

    @Test("dayRange · 目标日不在 bars 中 · 返回 nil")
    func dayRangeMissing() {
        let d1 = makeDate(year: 2024, month: 12, day: 15, hour: 0, minute: 0)
        let d2 = makeDate(year: 2024, month: 12, day: 20, hour: 0, minute: 0)
        let bars = [makeBar(openTime: d1)]
        #expect(IntradayBarsFilter.dayRange(in: bars, date: d2, calendar: utcCalendar()) == nil)
    }
}

// MARK: - helpers

fileprivate func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

fileprivate func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

fileprivate func makeBar(openTime: Date) -> KLine {
    KLine(
        instrumentID: "TEST",
        period: .minute1,
        openTime: openTime,
        open: 100, high: 101, low: 99, close: 100,
        volume: 10,
        openInterest: 0,
        turnover: 0
    )
}
