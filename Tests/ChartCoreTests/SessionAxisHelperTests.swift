// SessionAxisHelper 单测（v15.33 · WP-40 P1 · session-aware 时间轴）

import Foundation
import Testing
@testable import ChartCore
@testable import DataCore
import Shared

@Suite("SessionAxisHelper · K 线 session/day gap 检测 + 夜盘判定")
struct SessionAxisHelperTests {

    // MARK: - 测试辅助

    /// 构造 1m K 线序列 · 起始时间 + N 根 + 每根间隔（秒）
    /// gaps：在第 i 根后插入额外 dt 秒（仿造 session/day 缺口）
    private func makeBars(
        period: KLinePeriod = .minute1,
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        count: Int,
        gaps: [(afterIndex: Int, extraSeconds: TimeInterval)] = []
    ) -> [KLine] {
        var bars: [KLine] = []
        var t = startTime
        let step = TimeInterval(period.seconds)
        for i in 0..<count {
            bars.append(KLine(
                instrumentID: "TEST", period: period, openTime: t,
                open: 100, high: 101, low: 99, close: 100,
                volume: 0, openInterest: 0, turnover: 0
            ))
            t = t.addingTimeInterval(step)
            // 检查这根之后是否有 gap
            if let g = gaps.first(where: { $0.afterIndex == i }) {
                t = t.addingTimeInterval(g.extraSeconds)
            }
        }
        return bars
    }

    // MARK: - 基础正确性

    @Test("空 bars · 无 gap")
    func emptyBars() {
        let bars: [KLine] = []
        #expect(SessionAxisHelper.detectGaps(bars: bars, period: .minute1).isEmpty)
    }

    @Test("单根 bar · 无 gap")
    func singleBar() {
        let bars = makeBars(count: 1)
        #expect(SessionAxisHelper.detectGaps(bars: bars, period: .minute1).isEmpty)
    }

    @Test("无缺口连续 bars · 0 gap")
    func continuousBarsNoGap() {
        let bars = makeBars(count: 100)
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: .minute1)
        #expect(gaps.isEmpty)
    }

    @Test("daily 周期 · 不检测 gap（设计良好的日 K 自然不需要）")
    func dailyPeriodSkipped() {
        let bars = makeBars(period: .daily, count: 30)
        #expect(SessionAxisHelper.detectGaps(bars: bars, period: .daily).isEmpty)
    }

    // MARK: - session gap 检测

    @Test("中午午休（1m K · 11:30→13:00 缺 90 分钟）→ session gap")
    func lunchBreakSessionGap() {
        // gap = 90 分钟 = 5400 秒 · 期望 step = 60 秒 · sessionThreshold = 120 秒 · 远超
        // dayThreshold = 6h = 21600 秒 · 5400 < · 不算 day
        let bars = makeBars(count: 10, gaps: [(afterIndex: 4, extraSeconds: 5400 - 60)])
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: .minute1)
        #expect(gaps.count == 1)
        #expect(gaps[0].kind == .session)
        #expect(gaps[0].barIndex == 5)  // 缺口在 bar[4] 和 bar[5] 之间 · index = 5
    }

    @Test("夜盘 → 日盘衔接（02:30→09:00 缺 6h30m）→ day gap")
    func nightToDayGap() {
        // gap = 6h30m = 23400 秒 · 超过 dayThreshold 6h
        let bars = makeBars(count: 10, gaps: [(afterIndex: 4, extraSeconds: 23400 - 60)])
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: .minute1)
        #expect(gaps.count == 1)
        #expect(gaps[0].kind == .day)
    }

    @Test("周末缺口（周五 15:00 → 周一 09:00 缺 66h）→ day gap")
    func weekendGap() {
        // gap = 66 小时 · 远超 dayThreshold
        let bars = makeBars(count: 10, gaps: [(afterIndex: 4, extraSeconds: 66 * 3600 - 60)])
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: .minute1)
        #expect(gaps.count == 1)
        #expect(gaps[0].kind == .day)
    }

    @Test("多个 gap · 1 天内含 2 session gap + 1 day gap")
    func multipleGaps() {
        // 中午午休 + 下午收盘 → 夜盘开盘（15:00→21:00 = 6h · 在 day 阈值边界）
        // 改用 5h59m 还是 session · 6h 才是 day · 我们用 5.5h = 19800s 算 session
        let bars = makeBars(count: 30, gaps: [
            (afterIndex: 4, extraSeconds: 5400),   // 午休 90 分
            (afterIndex: 9, extraSeconds: 19800),  // 下午收盘 → 夜盘 5.5h（session）
            (afterIndex: 14, extraSeconds: 25200), // 跨日 7h（day）
        ])
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: .minute1)
        #expect(gaps.count == 3)
        #expect(gaps[0].kind == .session)
        #expect(gaps[1].kind == .session)
        #expect(gaps[2].kind == .day)
    }

    // MARK: - 范围限制

    @Test("startIndex / endIndexExclusive · 只检测可视范围内 gap")
    func rangeFilter() {
        let bars = makeBars(count: 30, gaps: [
            (afterIndex: 4, extraSeconds: 5400),   // gap@5
            (afterIndex: 19, extraSeconds: 5400),  // gap@20
        ])
        // 只看 [10, 25) 范围 → 仅 gap@20 命中
        let gaps = SessionAxisHelper.detectGaps(
            bars: bars, period: .minute1,
            startIndex: 10, endIndexExclusive: 25
        )
        #expect(gaps.count == 1)
        #expect(gaps[0].barIndex == 20)
    }

    // MARK: - 夜盘判定

    @Test("夜盘判定 · 21:30 在 21:00→23:00 夜盘内")
    func nightSession2200() {
        let hours = TradingCalendar.tradingHours(for: "M", exchange: .DCE)
        // M 豆粕 · 夜盘 21:00-23:00
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 21; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(SessionAxisHelper.isInNightSession(date: date, hours: hours) == true)
    }

    @Test("夜盘判定 · 02:00 在黄金 21:00→02:30 夜盘内（跨午夜）")
    func nightSessionCrossMidnight() {
        let hours = TradingCalendar.tradingHours(for: "AU", exchange: .SHFE)
        // AU 黄金 · 夜盘 21:00-02:30
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 2; comps.minute = 0
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(SessionAxisHelper.isInNightSession(date: date, hours: hours) == true)
    }

    @Test("夜盘判定 · 10:00 不在夜盘（在日盘）")
    func nightSessionNegative() {
        let hours = TradingCalendar.tradingHours(for: "M", exchange: .DCE)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 10; comps.minute = 0
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(SessionAxisHelper.isInNightSession(date: date, hours: hours) == false)
    }

    @Test("夜盘判定 · 无夜盘品种（如 IF 股指）任何时间都返 false")
    func nightSessionForCFFEX() {
        let hours = TradingCalendar.tradingHours(for: "IF", exchange: .CFFEX)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 22; comps.minute = 0
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        #expect(SessionAxisHelper.isInNightSession(date: date, hours: hours) == false)
    }

    // MARK: - 夜盘段落合并

    @Test("nightSessionSegments · 全日盘 · 1 个 isNight=false 段")
    func segmentsAllDay() {
        // 构造 9:30-10:00 之间的 30 根 bar · 全在日盘
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 9; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let start = cal.date(from: comps)!
        let bars = makeBars(startTime: start, count: 30)
        let hours = TradingCalendar.tradingHours(for: "IF", exchange: .CFFEX)
        let segs = SessionAxisHelper.nightSessionSegments(
            bars: bars, hours: hours,
            startIndex: 0, endIndexExclusive: 30
        )
        #expect(segs.count == 1)
        #expect(segs[0].isNight == false)
    }

    @Test("nightSessionSegments · 跨夜盘日盘 · 多段切换")
    func segmentsAcrossSessions() {
        // 构造从 20:55 起 · 5 根日盘 + 5 根夜盘（21:00 后）
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 8
        comps.hour = 20; comps.minute = 55
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let start = cal.date(from: comps)!
        let bars = makeBars(startTime: start, count: 10)
        let hours = TradingCalendar.tradingHours(for: "M", exchange: .DCE)
        let segs = SessionAxisHelper.nightSessionSegments(
            bars: bars, hours: hours,
            startIndex: 0, endIndexExclusive: 10
        )
        // 前 5 根（20:55-20:59）非夜盘 · 后 5 根（21:00-21:04）夜盘
        #expect(segs.count == 2)
        #expect(segs[0].isNight == false)
        #expect(segs[1].isNight == true)
        #expect(segs[1].start == 5)  // 切换点应该在 idx=5（21:00）
    }
}
