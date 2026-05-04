// WP-62 · 时间函数真实化单测（v15.18）
//
// 覆盖：DATE / TIME / HOUR / MINUTE 4 函数 timestamp 有/无 行为

import Testing
import Foundation
@testable import IndicatorCore

@Suite("TimeFunctions · DATE / TIME / HOUR / MINUTE 真实化")
struct TimeFunctionsRealTests {

    private func makeBar(_ ts: Date?) -> BarData {
        BarData(open: 1, high: 1, low: 1, close: 1, volume: 0, timestamp: ts)
    }

    private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.timeZone = TimeZone(identifier: "UTC")
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi; c.second = s
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("DATE · 通达信格式 = (年-1900)*10000 + 月*100 + 日")
    func dateFormat() throws {
        let bars = [makeBar(utcDate(2026, 5, 3))]
        let result = try DATEFunction().execute(args: [], bars: bars)
        // (2026-1900)*10000 + 5*100 + 3 = 126*10000 + 503 = 1_260_503
        #expect(result[0] == Decimal(1_260_503))
    }

    @Test("DATE · timestamp == nil 回退占位（bar 序号）")
    func dateFallbackToIndex() throws {
        let bars = [makeBar(nil), makeBar(nil), makeBar(nil)]
        let result = try DATEFunction().execute(args: [], bars: bars)
        #expect(result == [Decimal(0), Decimal(1), Decimal(2)] as [Decimal?])
    }

    @Test("TIME · HHMMSS 格式 = HH*10000 + MM*100 + SS")
    func timeFormat() throws {
        let bars = [makeBar(utcDate(2026, 5, 3, 14, 35, 27))]
        let result = try TIMEFunction().execute(args: [], bars: bars)
        // 14*10000 + 35*100 + 27 = 143_527
        #expect(result[0] == Decimal(143_527))
    }

    @Test("HOUR · UTC 0-23")
    func hourValue() throws {
        let bars = [
            makeBar(utcDate(2026, 5, 3, 0, 0, 0)),
            makeBar(utcDate(2026, 5, 3, 9, 30, 0)),
            makeBar(utcDate(2026, 5, 3, 23, 59, 59))
        ]
        let result = try HOURFunction().execute(args: [], bars: bars)
        #expect(result == [Decimal(0), Decimal(9), Decimal(23)] as [Decimal?])
    }

    @Test("MINUTE · 0-59")
    func minuteValue() throws {
        let bars = [
            makeBar(utcDate(2026, 5, 3, 9, 0, 0)),
            makeBar(utcDate(2026, 5, 3, 9, 30, 0)),
            makeBar(utcDate(2026, 5, 3, 9, 59, 0))
        ]
        let result = try MINUTEFunction().execute(args: [], bars: bars)
        #expect(result == [Decimal(0), Decimal(30), Decimal(59)] as [Decimal?])
    }

    @Test("ISLASTBAR · 末根 1 其余 0（沿用旧实现 · 防回归）")
    func isLastBarStable() throws {
        let bars = (0..<5).map { _ in makeBar(nil) }
        let result = try ISLASTBARFunction().execute(args: [], bars: bars)
        #expect(result == [Decimal(0), Decimal(0), Decimal(0), Decimal(0), Decimal(1)] as [Decimal?])
    }

    @Test("BARPOS · 从 1 开始（沿用旧实现 · 防回归）")
    func barposStable() throws {
        let bars = (0..<3).map { _ in makeBar(nil) }
        let result = try BARPOSFunction().execute(args: [], bars: bars)
        #expect(result == [Decimal(1), Decimal(2), Decimal(3)] as [Decimal?])
    }

    @Test("混合 · 部分 bar 有 timestamp 部分无 · 各按规则返回")
    func mixedTimestamps() throws {
        let bars = [
            makeBar(utcDate(2026, 1, 1, 10, 0, 0)),
            makeBar(nil),
            makeBar(utcDate(2026, 12, 31, 23, 0, 0))
        ]
        let result = try HOURFunction().execute(args: [], bars: bars)
        // [10（真）, 1（idx=1 占位）, 23（真）]
        #expect(result == [Decimal(10), Decimal(1), Decimal(23)] as [Decimal?])
    }
}
