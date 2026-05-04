// v15.20 batch56 · ReviewDateFilter 单测
// 覆盖：all / last7Days / last30Days / currentMonth / month / quarter
// timeZone 固定 Asia/Shanghai · reference 固定 2026-05-04 12:00 CST

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("ReviewDateFilter · 复盘区间筛选")
struct ReviewDateFilterTests {

    private let cst = TimeZone(identifier: "Asia/Shanghai")!

    /// 2026-05-04 12:00 CST
    private var reference: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = cst
        return cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 12))!
    }

    /// 在 reference 前 N 天的 12:00 CST 平仓
    private func position(daysAgo: Int, pnl: Decimal = 100) -> ClosedPosition {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = cst
        let close = cal.date(byAdding: .day, value: -daysAgo, to: reference)!
        return ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: close.addingTimeInterval(-3600),
            closeTime: close,
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    /// 指定日期 12:00 CST 平仓
    private func positionOn(year: Int, month: Int, day: Int, pnl: Decimal = 100) -> ClosedPosition {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = cst
        let close = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: close.addingTimeInterval(-3600),
            closeTime: close,
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test(".all 不过滤 · 原样返回")
    func all() {
        let positions = (0..<10).map { position(daysAgo: $0 * 5) }
        let result = ReviewDateFilterEngine.filter(positions, by: .all, reference: reference, timeZone: cst)
        #expect(result.count == 10)
    }

    @Test(".last7Days 仅保留 7 天内")
    func last7Days() {
        let positions = [
            position(daysAgo: 0),    // 今天 → 保留
            position(daysAgo: 3),    // 3 天前 → 保留
            position(daysAgo: 7),    // 边界（≥cutoff 即正好 7 天前）→ 保留
            position(daysAgo: 8),    // 8 天前 → 排除
            position(daysAgo: 30),   // 30 天前 → 排除
        ]
        let result = ReviewDateFilterEngine.filter(positions, by: .last7Days, reference: reference, timeZone: cst)
        #expect(result.count == 3)
    }

    @Test(".last30Days 仅保留 30 天内")
    func last30Days() {
        let positions = [
            position(daysAgo: 0),
            position(daysAgo: 15),
            position(daysAgo: 30),    // 边界 → 保留
            position(daysAgo: 31),    // 排除
            position(daysAgo: 60),
        ]
        let result = ReviewDateFilterEngine.filter(positions, by: .last30Days, reference: reference, timeZone: cst)
        #expect(result.count == 3)
    }

    @Test(".currentMonth 仅保留 reference 所在月（2026-05）")
    func currentMonth() {
        let positions = [
            positionOn(year: 2026, month: 5, day: 1),
            positionOn(year: 2026, month: 5, day: 15),
            positionOn(year: 2026, month: 5, day: 31),
            positionOn(year: 2026, month: 4, day: 30),   // 上月 → 排除
            positionOn(year: 2026, month: 6, day: 1),    // 下月 → 排除
        ]
        let result = ReviewDateFilterEngine.filter(positions, by: .currentMonth, reference: reference, timeZone: cst)
        #expect(result.count == 3)
    }

    @Test(".month(2026-05) 仅保留 yyyy-MM 字符串匹配")
    func specificMonth() {
        let positions = [
            positionOn(year: 2026, month: 5, day: 1),
            positionOn(year: 2026, month: 5, day: 31),
            positionOn(year: 2026, month: 4, day: 30),
            positionOn(year: 2025, month: 5, day: 15),
        ]
        let result = ReviewDateFilterEngine.filter(positions, by: .month("2026-05"), reference: reference, timeZone: cst)
        #expect(result.count == 2)
    }

    @Test(".quarter(2026-Q2) 4-6 月覆盖")
    func quarter() {
        let positions = [
            positionOn(year: 2026, month: 4, day: 1),    // Q2 → 保留
            positionOn(year: 2026, month: 5, day: 15),   // Q2 → 保留
            positionOn(year: 2026, month: 6, day: 30),   // Q2 → 保留
            positionOn(year: 2026, month: 3, day: 31),   // Q1 → 排除
            positionOn(year: 2026, month: 7, day: 1),    // Q3 → 排除
        ]
        let result = ReviewDateFilterEngine.filter(positions, by: .quarter("2026-Q2"), reference: reference, timeZone: cst)
        #expect(result.count == 3)
    }

    @Test(".quarter 跨 Q1/Q3/Q4 覆盖月份正确")
    func quarterAll() {
        // 1/2/3 → Q1 · 7/8/9 → Q3 · 10/11/12 → Q4
        for (month, expectedQ) in [(1, "Q1"), (2, "Q1"), (3, "Q1"), (7, "Q3"), (10, "Q4"), (12, "Q4")] {
            let positions = [positionOn(year: 2026, month: month, day: 15)]
            let result = ReviewDateFilterEngine.filter(positions, by: .quarter("2026-\(expectedQ)"), reference: reference, timeZone: cst)
            #expect(result.count == 1, "month \(month) 应映射 \(expectedQ)")
        }
    }

    @Test("availableMonths 升序去重")
    func availableMonths() {
        let positions = [
            positionOn(year: 2026, month: 5, day: 1),
            positionOn(year: 2026, month: 4, day: 30),
            positionOn(year: 2026, month: 5, day: 15),    // 重复 2026-05
            positionOn(year: 2025, month: 12, day: 1),
        ]
        let months = ReviewDateFilterEngine.availableMonths(positions, timeZone: cst)
        #expect(months == ["2025-12", "2026-04", "2026-05"])
    }

    @Test("availableQuarters 升序去重")
    func availableQuarters() {
        let positions = [
            positionOn(year: 2026, month: 5, day: 1),       // 2026-Q2
            positionOn(year: 2026, month: 6, day: 30),      // 2026-Q2 重复
            positionOn(year: 2026, month: 1, day: 15),      // 2026-Q1
            positionOn(year: 2025, month: 11, day: 1),      // 2025-Q4
        ]
        let qs = ReviewDateFilterEngine.availableQuarters(positions, timeZone: cst)
        #expect(qs == ["2025-Q4", "2026-Q1", "2026-Q2"])
    }

    @Test("v15.20 batch60 · fromRawTag 反解析（持久化往返）")
    func fromRawTag() {
        // 全部 6 case · rawTag 往返
        let allCases: [ReviewDateFilter] = [
            .all, .last7Days, .last30Days, .currentMonth,
            .month("2026-05"), .quarter("2026-Q2")
        ]
        for filter in allCases {
            let parsed = ReviewDateFilter.fromRawTag(filter.rawTag)
            #expect(parsed == filter, "rawTag round-trip 失败：\(filter)")
        }

        // 边界
        #expect(ReviewDateFilter.fromRawTag("invalid") == nil)
        #expect(ReviewDateFilter.fromRawTag("month:") == nil)         // 空 month
        #expect(ReviewDateFilter.fromRawTag("quarter:") == nil)       // 空 quarter
        #expect(ReviewDateFilter.fromRawTag("month:2026-12") == .month("2026-12"))
        #expect(ReviewDateFilter.fromRawTag("quarter:2026-Q3") == .quarter("2026-Q3"))
    }

    @Test("displayName / rawTag 稳定")
    func labels() {
        #expect(ReviewDateFilter.all.displayName == "全部")
        #expect(ReviewDateFilter.last7Days.displayName == "近 7 天")
        #expect(ReviewDateFilter.last30Days.displayName == "近 30 天")
        #expect(ReviewDateFilter.currentMonth.displayName == "当月")
        #expect(ReviewDateFilter.month("2026-05").displayName == "2026-05")
        #expect(ReviewDateFilter.quarter("2026-Q2").displayName == "2026-Q2")

        #expect(ReviewDateFilter.all.rawTag == "all")
        #expect(ReviewDateFilter.month("2026-05").rawTag == "month:2026-05")
        #expect(ReviewDateFilter.quarter("2026-Q2").rawTag == "quarter:2026-Q2")
    }
}
