// v15.19 batch23 · AlertHistoryFilter + Statistics 单测
// 覆盖：5 类窗口 / 应用筛选 / 统计 by 合约 / by 类型 / by 小时

import Testing
import Foundation
import Shared
@testable import AlertCore

@Suite("AlertHistoryFilter · 时间窗口 v15.19 batch23")
struct AlertHistoryFilterTests {

    private let cn = TimeZone(identifier: "Asia/Shanghai")!
    private var cnCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = cn
        return c
    }

    private func entry(at: Date, instrument: String = "RB0",
                       condition: AlertCondition = .priceAbove(100)) -> AlertHistoryEntry {
        AlertHistoryEntry(
            alertID: UUID(), alertName: "test",
            instrumentID: instrument,
            conditionSnapshot: condition,
            triggeredAt: at, triggerPrice: 100, message: "")
    }

    @Test("Window.all 返回 nil range · 不筛选")
    func allWindow() {
        #expect(AlertHistoryFilter.range(of: .all) == nil)
    }

    @Test("Window.today · range 起点 = 当日 0 点 Asia/Shanghai")
    func todayWindow() {
        // 2026-05-04 12:00:00 +0800 = 1746331200 - 12*3600 ... 实际算：
        // 2026-05-04 00:00 +0800 epoch = 1746288000
        let now = Date(timeIntervalSince1970: 1_746_331_200)   // 2026-05-04 12:00 +0800
        let r = AlertHistoryFilter.range(of: .today, now: now, timeZone: cn)
        #expect(r != nil)
        #expect(r?.from.timeIntervalSince1970 == 1_746_288_000)   // 当日 0 点
        #expect(r?.to == now)
    }

    @Test("Window.last7d · range 起点 = now - 7 天")
    func last7dWindow() {
        let now = Date(timeIntervalSince1970: 1_746_331_200)
        let r = AlertHistoryFilter.range(of: .last7d, now: now)
        #expect(r != nil)
        #expect(r!.to.timeIntervalSince(r!.from) == 7 * 86_400)
    }

    @Test("apply · all 窗口返回原数组")
    func applyAll() {
        let now = Date()
        let entries = [entry(at: now), entry(at: now.addingTimeInterval(-100))]
        let r = AlertHistoryFilter.apply(entries, window: .all, now: now)
        #expect(r.count == 2)
    }

    @Test("apply · today 窗口仅保留当日 entries")
    func applyTodayFilters() {
        let now = Date(timeIntervalSince1970: 1_746_331_200)   // 2026-05-04 12:00 +0800
        let inToday = entry(at: Date(timeIntervalSince1970: 1_746_320_000))    // 2026-05-04 09:00
        let inYesterday = entry(at: Date(timeIntervalSince1970: 1_746_280_000)) // 2026-05-03 21:53
        let entries = [inToday, inYesterday]
        let r = AlertHistoryFilter.apply(entries, window: .today, now: now, timeZone: cn)
        #expect(r.count == 1)
    }
}

@Suite("AlertHistoryStatistics · 分组统计 v15.19 batch23")
struct AlertHistoryStatisticsTests {

    private let cn = TimeZone(identifier: "Asia/Shanghai")!

    private func entry(at: Date, instrument: String = "RB0",
                       condition: AlertCondition = .priceAbove(100)) -> AlertHistoryEntry {
        AlertHistoryEntry(
            alertID: UUID(), alertName: "test",
            instrumentID: instrument,
            conditionSnapshot: condition,
            triggeredAt: at, triggerPrice: 100, message: "")
    }

    @Test("空输入 · total=0")
    func empty() {
        let s = AlertHistoryStatistics.summarize([])
        #expect(s.total == 0)
        #expect(s.byInstrument.isEmpty)
        #expect(s.byKind.isEmpty)
    }

    @Test("byInstrument 按 count 降序排列 · count 同时按 key 字典序")
    func instrumentSort() {
        let now = Date()
        let entries = [
            entry(at: now, instrument: "AU0"),
            entry(at: now, instrument: "RB0"),
            entry(at: now, instrument: "RB0"),
            entry(at: now, instrument: "RB0"),
            entry(at: now, instrument: "IF0"),
            entry(at: now, instrument: "IF0")
        ]
        let s = AlertHistoryStatistics.summarize(entries)
        #expect(s.byInstrument.map(\.key) == ["RB0", "IF0", "AU0"])
        #expect(s.byInstrument.map(\.count) == [3, 2, 1])
    }

    @Test("byKind 6 类映射 · price/cross/breakout/lineTouched/spike/indicator")
    func kindMapping() {
        let now = Date()
        let entries: [AlertHistoryEntry] = [
            entry(at: now, condition: .priceAbove(100)),
            entry(at: now, condition: .priceBelow(100)),
            entry(at: now, condition: .priceCrossAbove(100)),
            entry(at: now, condition: .priceBreakoutHigh(period: .minute15, lookback: 20)),
            entry(at: now, condition: .priceBreakoutLow(period: .minute15, lookback: 20)),
            entry(at: now, condition: .horizontalLineTouched(drawingID: UUID(), price: 100)),
            entry(at: now, condition: .volumeSpike(multiple: 3, windowBars: 20)),
            entry(at: now, condition: .openInterestSpike(multiple: 1.5, windowBars: 20)),
            entry(at: now, condition: .priceMoveSpike(percentThreshold: 1, windowSeconds: 60))
        ]
        let s = AlertHistoryStatistics.summarize(entries)
        // price: 2 / cross: 1 / breakout: 2 / lineTouched: 1 / spike: 3 / indicator: 0
        let kindMap = Dictionary(uniqueKeysWithValues: s.byKind.map { ($0.key, $0.count) })
        #expect(kindMap[.price] == 2)
        #expect(kindMap[.cross] == 1)
        #expect(kindMap[.breakout] == 2)
        #expect(kindMap[.lineTouched] == 1)
        #expect(kindMap[.spike] == 3)
        #expect(kindMap[.indicator] == nil)
        // 排序：spike 3 / breakout 2 / price 2 / cross 1 / lineTouched 1
        #expect(s.byKind.first?.key == .spike)
    }

    @Test("byHour 按 Asia/Shanghai 小时分桶")
    func hourBuckets() {
        // 2026-05-04 09:00 +0800 / 09:30 +0800 / 14:00 +0800
        let h09a = Date(timeIntervalSince1970: 1_746_320_400)   // 09:00:00 +0800
        let h09b = Date(timeIntervalSince1970: 1_746_322_200)   // 09:30:00 +0800
        let h14  = Date(timeIntervalSince1970: 1_746_338_400)   // 14:00:00 +0800
        let s = AlertHistoryStatistics.summarize(
            [entry(at: h09a), entry(at: h09b), entry(at: h14)],
            timeZone: cn
        )
        #expect(s.byHour[9] == 2)
        #expect(s.byHour[14] == 1)
    }
}
