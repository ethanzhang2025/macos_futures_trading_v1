// WP-31a · SinaQuoteToTick 转换测试
// 字段映射 + 5 档补 0 + 缺失字段兜底 + tradingDay 时间注入

import Testing
import Foundation
import Shared
@testable import DataCore

@Suite("SinaQuoteToTick · 转换正确性")
struct SinaQuoteToTickTests {

    private func makeSampleQuote(symbol: String = "RB0") -> SinaQuote {
        SinaQuote(
            symbol: symbol, name: "螺纹钢",
            open: 3500, high: 3550, low: 3480, close: 3490,
            bidPrice: 3520, askPrice: 3521, lastPrice: 3520,
            settlementPrice: 3510, preSettlement: 3490,
            bidVolume: 100, askVolume: 200,
            openInterest: 12345, volume: 67890,
            timestamp: "2026-04-25 09:30:00"
        )
    }

    @Test("基本字段直接映射")
    func basicFieldsMapped() {
        let quote = makeSampleQuote()
        let tick = SinaQuoteToTick.convert(quote, instrumentID: "RB0")

        #expect(tick.instrumentID == "RB0")
        #expect(tick.lastPrice == 3520)
        #expect(tick.openPrice == 3500)
        #expect(tick.highestPrice == 3550)
        #expect(tick.lowestPrice == 3480)
        #expect(tick.preClosePrice == 3490)
        #expect(tick.preSettlementPrice == 3490)
        #expect(tick.volume == 67890)
        #expect(tick.openInterest == Decimal(12345))
    }

    @Test("Sina 仅 1 档盘口 → 5 档其余补 0")
    func depthPaddedToFive() {
        let quote = makeSampleQuote()
        let tick = SinaQuoteToTick.convert(quote, instrumentID: "RB0")

        #expect(tick.bidPrices == [3520, 0, 0, 0, 0])
        #expect(tick.askPrices == [3521, 0, 0, 0, 0])
        #expect(tick.bidVolumes == [100, 0, 0, 0, 0])
        #expect(tick.askVolumes == [200, 0, 0, 0, 0])
    }

    @Test("Sina 缺失字段补 0：turnover / 涨跌停")
    func missingFieldsZeroFilled() {
        let quote = makeSampleQuote()
        let tick = SinaQuoteToTick.convert(quote, instrumentID: "RB0")

        #expect(tick.turnover == 0)
        #expect(tick.upperLimitPrice == 0)
        #expect(tick.lowerLimitPrice == 0)
    }

    @Test("instrumentID 与 quote.symbol 解耦，由 caller 决定")
    func instrumentIDFromCaller() {
        let quote = makeSampleQuote(symbol: "rb0")  // 小写
        let tick = SinaQuoteToTick.convert(quote, instrumentID: "RB0")  // 业务侧大写
        #expect(tick.instrumentID == "RB0")
    }

    @Test("tradingDay / updateTime 由注入时间生成（YYYYMMDD / HH:mm:ss · 上海时区）")
    func tradingDayFromInjectedTime() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        components.year = 2026; components.month = 4; components.day = 25
        components.hour = 9; components.minute = 30; components.second = 0
        let fixed = components.date!

        let quote = makeSampleQuote()
        let tick = SinaQuoteToTick.convert(quote, instrumentID: "RB0", now: fixed)

        #expect(tick.tradingDay == "20260425")
        #expect(tick.actionDay == "20260425")
        #expect(tick.updateTime == "09:30:00")
    }
}
