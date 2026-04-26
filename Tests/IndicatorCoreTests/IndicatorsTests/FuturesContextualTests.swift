// FuturesContextual 单元测试（B1 Step 2 · 4 占位指标真实化）
// 验证：4 指标各 calculate · barTimes 长度校验 · 无数据 nil / 数据缺位 / 跨日夜盘

import Foundation
import Testing
@testable import IndicatorCore
import DataCore

private let dayFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return df
}()

private let dateTimeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm"
    df.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return df
}()

private func day(_ s: String) -> Date { dayFormatter.date(from: s)! }
private func dt(_ s: String) -> Date { dateTimeFormatter.date(from: s)! }

private let rbSpec = ProductSpec(
    exchange: "SHFE", productID: "RB", name: "螺纹钢", pinyin: "luowengang",
    multiple: 10, priceTick: "1", marginRatio: "0.08",
    unit: "吨", nightSession: "21:00-23:00"
)

private func makeKLine(closes: [Decimal]) -> KLineSeries {
    let n = closes.count
    return KLineSeries(
        opens: closes, highs: closes, lows: closes,
        closes: closes, volumes: Array(repeating: 100, count: n),
        openInterests: Array(repeating: 0, count: n)
    )
}

@Suite("FuturesContextual · B1 Step 2 · 4 占位指标真实化")
struct FuturesContextualTests {

    // MARK: - LimitPriceLines

    @Test("LimitPriceLines: 3 bar 跨 2 个 dailyLimit 日 · 各取 latest")
    func testLimitPriceLines() throws {
        let d1 = day("2026-04-01"), d2 = day("2026-04-02")
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            dailyLimits: [
                DailyLimit(tradingDay: d1, upperLimit: 3100, lowerLimit: 2900),
                DailyLimit(tradingDay: d2, upperLimit: 3200, lowerLimit: 2950),
            ]
        )
        let kline = makeKLine(closes: [3000, 3100, 3150])
        let times = [
            dt("2026-04-01 10:00"),  // 取 d1 limit
            dt("2026-04-02 10:00"),  // 取 d2 limit
            dt("2026-04-03 10:00"),  // 取 d2（latest <= asOf）
        ]
        let result = try LimitPriceLines.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result.count == 2)
        #expect(result[0].name == "UPPER" && result[1].name == "LOWER")
        #expect(result[0].values == [3100, 3200, 3200])
        #expect(result[1].values == [2900, 2950, 2950])
    }

    @Test("LimitPriceLines: 无 dailyLimits → 全 nil")
    func testLimitPriceLinesEmpty() throws {
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec)
        let kline = makeKLine(closes: [3000, 3100])
        let times = [dt("2026-04-01 10:00"), dt("2026-04-02 10:00")]
        let result = try LimitPriceLines.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result[0].values == [nil, nil])
        #expect(result[1].values == [nil, nil])
    }

    // MARK: - DeliveryCountdown

    @Test("DeliveryCountdown: 4-26 00:00 → 10-15 00:00 = 172 天")
    func testDeliveryCountdownBasic() throws {
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            deliveryDate: day("2026-10-15")
        )
        let kline = makeKLine(closes: [3000])
        // 用 day(...) 取 00:00 · 与 deliveryDate 同零点 · 整 172 天差
        // 若用 dt("2026-04-26 10:00") 则差 171.x 天 trunc 后 171（A1 timeIntervalSince/86400 实现）
        let times = [day("2026-04-26")]
        let result = try DeliveryCountdown.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result.count == 1)
        #expect(result[0].name == "DAYS")
        #expect(result[0].values == [172])
    }

    @Test("DeliveryCountdown: 过期 / 未设交割日 → nil")
    func testDeliveryCountdownExpiredOrUnset() throws {
        let ctxExpired = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            deliveryDate: day("2025-04-01")
        )
        let ctxUnset = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec)
        let kline = makeKLine(closes: [3000])
        let times = [dt("2026-04-26 10:00")]

        let r1 = try DeliveryCountdown.calculate(kline: kline, barTimes: times, context: ctxExpired, params: [])
        let r2 = try DeliveryCountdown.calculate(kline: kline, barTimes: times, context: ctxUnset, params: [])
        #expect(r1[0].values == [nil])
        #expect(r2[0].values == [nil])
    }

    // MARK: - SettlementPriceLine

    @Test("SettlementPriceLine: 跨 2 个结算价日各取 latest")
    func testSettlementPriceLine() throws {
        let d1 = day("2026-04-01"), d2 = day("2026-04-02")
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            dailySettlements: [
                DailySettlement(tradingDay: d1, settlementPrice: 3000),
                DailySettlement(tradingDay: d2, settlementPrice: 3050),
            ]
        )
        let kline = makeKLine(closes: [3000, 3100, 3050])
        let times = [
            dt("2026-04-01 10:00"),  // 取 d1
            dt("2026-04-02 10:00"),  // 取 d2
            dt("2026-04-03 10:00"),  // 取 d2 latest
        ]
        let result = try SettlementPriceLine.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result.count == 1)
        #expect(result[0].name == "SETTLE")
        #expect(result[0].values == [3000, 3050, 3050])
    }

    // MARK: - SessionDivider

    @Test("SessionDivider: 日盘 9:30 / 间隙 10:20 / 夜盘 22:00")
    func testSessionDivider() throws {
        let hours = ProductTradingHours(productID: "RB", sessions: [
            TradingSession(start: (9, 0), end: (10, 15)),
            TradingSession(start: (10, 30), end: (11, 30)),
            TradingSession(start: (21, 0), end: (23, 30), isNight: true),
        ])
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec, tradingHours: hours)
        let kline = makeKLine(closes: [3000, 3000, 3000, 3000])
        let times = [
            dt("2026-04-01 09:30"),  // 日盘 ✓
            dt("2026-04-01 10:20"),  // 间隙 ✗
            dt("2026-04-01 22:00"),  // 夜盘 ✓
            dt("2026-04-01 23:45"),  // 夜盘后 ✗
        ]
        let result = try SessionDivider.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result.count == 1)
        #expect(result[0].name == "IN_SESSION")
        #expect(result[0].values == [1, 0, 1, 0])
    }

    @Test("SessionDivider: 无 tradingHours → 全 0")
    func testSessionDividerNoHours() throws {
        let ctx = FuturesContext(instrumentID: "RB2510", productSpec: rbSpec)
        let kline = makeKLine(closes: [3000, 3000])
        let times = [dt("2026-04-01 09:30"), dt("2026-04-01 22:00")]
        let result = try SessionDivider.calculate(kline: kline, barTimes: times, context: ctx, params: [])
        #expect(result[0].values == [0, 0])
    }

    // MARK: - barTimes 长度校验

    @Test("barTimes 长度不匹配 → 抛 IndicatorError.invalidParameter")
    func testBarTimesLengthMismatch() throws {
        let ctx = FuturesContext(
            instrumentID: "RB2510", productSpec: rbSpec,
            deliveryDate: day("2026-10-15")
        )
        let kline = makeKLine(closes: [3000, 3100, 3200])
        let times = [dt("2026-04-26 10:00"), dt("2026-04-27 10:00")]  // 长度 2 vs 3

        // 用闭包数组而非 switch · 4 指标统一以"label + 调用"打包，避免死 default 分支
        let calls: [(String, () throws -> [IndicatorSeries])] = [
            ("LIMIT",    { try LimitPriceLines.calculate(kline: kline, barTimes: times, context: ctx, params: []) }),
            ("DELIVERY", { try DeliveryCountdown.calculate(kline: kline, barTimes: times, context: ctx, params: []) }),
            ("SETTLE",   { try SettlementPriceLine.calculate(kline: kline, barTimes: times, context: ctx, params: []) }),
            ("SESSION",  { try SessionDivider.calculate(kline: kline, barTimes: times, context: ctx, params: []) }),
        ]
        for (label, call) in calls {
            #expect(throws: IndicatorError.self, "\(label) 应在长度不匹配时抛错") {
                _ = try call()
            }
        }
    }

    // MARK: - identifier / category 元数据

    @Test("4 指标 identifier 与 category 元数据正确")
    func testMetadata() {
        #expect(LimitPriceLines.identifier == "LIMIT")
        #expect(DeliveryCountdown.identifier == "DELIVERY")
        #expect(SettlementPriceLine.identifier == "SETTLE")
        #expect(SessionDivider.identifier == "SESSION")
        #expect(LimitPriceLines.category == .futures)
        #expect(DeliveryCountdown.category == .futures)
        #expect(SettlementPriceLine.category == .futures)
        #expect(SessionDivider.category == .futures)
    }
}
