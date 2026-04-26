// FuturesContext 单元测试
// 验证：dailyLimits/Settlements 自动排序 / daysUntilDelivery / 同日精确查询 /
//      latest 查询 / isInTradingSession 日盘 / 跨日夜盘 / 空 tradingHours

import Foundation
import Testing
@testable import DataCore

private let dayFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return df
}()

private func day(_ s: String) -> Date { dayFormatter.date(from: s)! }

private let rbSpec = ProductSpec(
    exchange: "SHFE", productID: "RB", name: "螺纹钢", pinyin: "luowengang",
    multiple: 10, priceTick: "1", marginRatio: "0.08",
    unit: "吨", nightSession: "21:00-23:00"
)

@Suite("FuturesContext · 期货合约+每日动态数据视图")
struct FuturesContextTests {

    @Test("init 自动按 tradingDay 升序排序 dailyLimits 与 dailySettlements")
    func testInitSortsDailyData() {
        let d1 = day("2026-04-01"), d2 = day("2026-04-02"), d3 = day("2026-04-03")
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            dailyLimits: [
                DailyLimit(tradingDay: d3, upperLimit: 3300, lowerLimit: 3000),
                DailyLimit(tradingDay: d1, upperLimit: 3100, lowerLimit: 2900),
                DailyLimit(tradingDay: d2, upperLimit: 3200, lowerLimit: 2950),
            ],
            dailySettlements: [
                DailySettlement(tradingDay: d2, settlementPrice: 3050),
                DailySettlement(tradingDay: d1, settlementPrice: 3000),
            ]
        )
        #expect(ctx.dailyLimits.map { $0.tradingDay } == [d1, d2, d3])
        #expect(ctx.dailySettlements.map { $0.tradingDay } == [d1, d2])
    }

    @Test("daysUntilDelivery: 4-26 → 10-15 = 172 天")
    func testDaysUntilDelivery() {
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            deliveryDate: day("2026-10-15")
        )
        #expect(ctx.daysUntilDelivery(asOf: day("2026-04-26")) == 172)
    }

    @Test("daysUntilDelivery: 过期返回 nil")
    func testDaysUntilDeliveryExpired() {
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            deliveryDate: day("2025-04-01")
        )
        #expect(ctx.daysUntilDelivery(asOf: day("2026-04-26")) == nil)
    }

    @Test("daysUntilDelivery: 未设交割日返回 nil")
    func testDaysUntilDeliveryUnset() {
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec)
        #expect(ctx.daysUntilDelivery(asOf: Date()) == nil)
    }

    @Test("limit/settlement 同日精确查询")
    func testLimitSettlementOnDay() {
        let d1 = day("2026-04-01")
        let limit = DailyLimit(tradingDay: d1, upperLimit: 3100, lowerLimit: 2900)
        let settle = DailySettlement(tradingDay: d1, settlementPrice: 3000)
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            dailyLimits: [limit], dailySettlements: [settle]
        )
        #expect(ctx.limit(onTradingDay: d1) == limit)
        #expect(ctx.settlement(onTradingDay: d1) == 3000)
        #expect(ctx.limit(onTradingDay: day("2026-04-02")) == nil)
        #expect(ctx.settlement(onTradingDay: day("2026-04-02")) == nil)
    }

    @Test("latestLimit/latestSettlement 取 <= asOf 的最新一条")
    func testLatestQuery() {
        let d1 = day("2026-04-01"), d2 = day("2026-04-02")
        let l1 = DailyLimit(tradingDay: d1, upperLimit: 3100, lowerLimit: 2900)
        let l2 = DailyLimit(tradingDay: d2, upperLimit: 3200, lowerLimit: 2950)
        let s1 = DailySettlement(tradingDay: d1, settlementPrice: 3000)
        let s2 = DailySettlement(tradingDay: d2, settlementPrice: 3050)
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            dailyLimits: [l1, l2], dailySettlements: [s1, s2]
        )
        // asOf 各点
        #expect(ctx.latestLimit(asOf: d1) == l1)
        #expect(ctx.latestLimit(asOf: d2) == l2)
        #expect(ctx.latestLimit(asOf: day("2026-04-03")) == l2)  // 后面用最新
        #expect(ctx.latestLimit(asOf: day("2026-03-31")) == nil)  // 前面无
        #expect(ctx.latestSettlement(asOf: day("2026-04-03")) == 3050)
    }

    @Test("isInTradingSession: 日盘 9:00-10:15 + 10:30-11:30 + 13:30-15:00")
    func testIsInTradingSessionDay() {
        let hours = ProductTradingHours(productID: "RB", sessions: [
            TradingSession(start: (9, 0), end: (10, 15)),
            TradingSession(start: (10, 30), end: (11, 30)),
            TradingSession(start: (13, 30), end: (15, 0)),
        ])
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec, tradingHours: hours)
        #expect(ctx.isInTradingSession(minuteOfDay: 9 * 60 + 30) == true)    // 9:30 ✓
        #expect(ctx.isInTradingSession(minuteOfDay: 10 * 60 + 20) == false)  // 10:20 间隙
        #expect(ctx.isInTradingSession(minuteOfDay: 14 * 60) == true)        // 14:00 ✓
        #expect(ctx.isInTradingSession(minuteOfDay: 15 * 60 + 30) == false)  // 15:30 收盘后
        #expect(ctx.isInTradingSession(minuteOfDay: 8 * 60 + 59) == false)   // 8:59 开盘前
    }

    @Test("isInTradingSession: 跨日夜盘 21:00 → 02:30")
    func testIsInTradingSessionNight() {
        let hours = ProductTradingHours(productID: "RB", sessions: [
            TradingSession(start: (21, 0), end: (2, 30), isNight: true),
        ])
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec, tradingHours: hours)
        #expect(ctx.isInTradingSession(minuteOfDay: 22 * 60) == true)    // 22:00 ✓
        #expect(ctx.isInTradingSession(minuteOfDay: 60 + 30) == true)    // 01:30 ✓
        #expect(ctx.isInTradingSession(minuteOfDay: 3 * 60) == false)    // 03:00 收盘后
        #expect(ctx.isInTradingSession(minuteOfDay: 20 * 60) == false)   // 20:00 开盘前
        #expect(ctx.isInTradingSession(minuteOfDay: 21 * 60) == true)    // 21:00 起点 ✓
    }

    @Test("isInTradingSession: 无 tradingHours 全部返回 false")
    func testIsInTradingSessionNoHours() {
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec)
        #expect(ctx.isInTradingSession(minuteOfDay: 10 * 60) == false)
        #expect(ctx.isInTradingSession(minuteOfDay: 22 * 60) == false)
    }

    @Test("Codable 往返：DailyLimit + DailySettlement")
    func testDailyDataCodable() throws {
        let d1 = day("2026-04-01")
        let limit = DailyLimit(tradingDay: d1, upperLimit: 3100, lowerLimit: 2900)
        let settle = DailySettlement(tradingDay: d1, settlementPrice: 3000)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let limitRT = try decoder.decode(DailyLimit.self, from: encoder.encode(limit))
        let settleRT = try decoder.decode(DailySettlement.self, from: encoder.encode(settle))
        #expect(limitRT == limit)
        #expect(settleRT == settle)
    }
}
