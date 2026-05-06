// WP-50 v15.23 batch48 · 日历盈亏热力图测试

import Testing
import Foundation
import Shared
@testable import JournalCore

@Suite("ReviewAnalytics · 日历盈亏热力图（第 11 图）")
struct DailyPnLTests {

    private let tz = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = h; dc.minute = min
        return c.date(from: dc)!
    }

    private func position(pnl: Decimal, closeTime: Date) -> ClosedPosition {
        ClosedPosition(
            instrumentID: "rb2510",
            side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: closeTime.addingTimeInterval(-3600),
            closeTime: closeTime,
            openPrice: 3500, closePrice: 3500,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空输入 → 空 buckets · maxAbs = 0")
    func empty() {
        let r = ReviewAnalytics.dailyPnL(from: [])
        #expect(r.buckets.isEmpty)
        #expect(r.maxAbsPnL == 0)
        #expect(r.totalPnL == 0)
        #expect(r.tradingDays == 0)
    }

    @Test("同一天多笔聚合到同 bucket")
    func sameDayAggregate() {
        let positions = [
            position(pnl: 100, closeTime: date(2026, 3, 15, 10)),
            position(pnl: 50, closeTime: date(2026, 3, 15, 14)),
            position(pnl: -30, closeTime: date(2026, 3, 15, 21)),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.buckets.count == 1)
        #expect(r.buckets[0].realizedPnL == 120)
        #expect(r.buckets[0].tradeCount == 3)
    }

    @Test("不同天分桶 + 升序排列")
    func multipleDaysSorted() {
        let positions = [
            position(pnl: 200, closeTime: date(2026, 3, 20)),
            position(pnl: -50, closeTime: date(2026, 3, 18)),
            position(pnl: 100, closeTime: date(2026, 3, 19)),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.buckets.count == 3)
        // 升序：3-18 → 3-19 → 3-20
        #expect(r.buckets[0].realizedPnL == -50)
        #expect(r.buckets[1].realizedPnL == 100)
        #expect(r.buckets[2].realizedPnL == 200)
    }

    @Test("maxAbsPnL 正确归一化（取绝对值最大）")
    func maxAbsCalc() {
        let positions = [
            position(pnl: 100, closeTime: date(2026, 3, 1)),
            position(pnl: -500, closeTime: date(2026, 3, 2)),
            position(pnl: 200, closeTime: date(2026, 3, 3)),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.maxAbsPnL == 500)
    }

    @Test("winningDays / losingDays / tradingDays 统计")
    func dayStats() {
        let positions = [
            position(pnl: 100, closeTime: date(2026, 3, 1)),   // win
            position(pnl: -50, closeTime: date(2026, 3, 2)),   // loss
            position(pnl: 200, closeTime: date(2026, 3, 3)),   // win
            position(pnl: 0, closeTime: date(2026, 3, 4)),     // 平
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.tradingDays == 4)
        #expect(r.winningDays == 2)
        #expect(r.losingDays == 1)
    }

    @Test("totalPnL 等于所有 buckets pnl 之和")
    func totalPnLSum() {
        let positions = [
            position(pnl: 100, closeTime: date(2026, 3, 1)),
            position(pnl: -30, closeTime: date(2026, 3, 2)),
            position(pnl: 70, closeTime: date(2026, 3, 3)),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.totalPnL == 140)
    }

    @Test("跨时区聚合：UTC vs Beijing 跨日边界")
    func timeZoneBoundary() {
        // 在 UTC 23:00 = Beijing 次日 07:00 · 北京时区下应聚合到次日
        let utcLate = Date(timeIntervalSince1970: 1742505600 + 23 * 3600)  // 2025-03-21 23:00 UTC
        let utcNext = Date(timeIntervalSince1970: 1742505600 + 25 * 3600)  // 2025-03-22 01:00 UTC
        let positions = [
            position(pnl: 100, closeTime: utcLate),
            position(pnl: 50, closeTime: utcNext),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        // 在北京时区 · utcLate (07:00) 与 utcNext (09:00) 同一天 → 1 bucket
        #expect(r.buckets.count == 1)
        #expect(r.buckets[0].realizedPnL == 150)
    }

    @Test("isWin / isLoss 单元 flag")
    func bucketFlags() {
        let positions = [
            position(pnl: 100, closeTime: date(2026, 3, 1)),
            position(pnl: -50, closeTime: date(2026, 3, 2)),
        ]
        let r = ReviewAnalytics.dailyPnL(from: positions, timeZone: tz)
        #expect(r.buckets[0].isWin == true)
        #expect(r.buckets[0].isLoss == false)
        #expect(r.buckets[1].isWin == false)
        #expect(r.buckets[1].isLoss == true)
    }
}
