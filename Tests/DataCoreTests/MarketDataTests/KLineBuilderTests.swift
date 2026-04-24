import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("K线合成测试")
struct KLineBuilderTests {
    private func makeTick(price: Decimal, volume: Int, time: String, tradingDay: String = "20250115") -> Tick {
        Tick(
            instrumentID: "rb2501", lastPrice: price, volume: volume,
            openInterest: 100000, turnover: 0,
            bidPrices: [price - 1], askPrices: [price + 1],
            bidVolumes: [10], askVolumes: [10],
            highestPrice: price + 5, lowestPrice: price - 5,
            openPrice: price, preClosePrice: price,
            preSettlementPrice: price,
            upperLimitPrice: price + 100, lowerLimitPrice: price - 100,
            updateTime: time, updateMillisec: 0,
            tradingDay: tradingDay, actionDay: tradingDay
        )
    }

    @Test("分钟K线合成")
    func testMinuteKLine() {
        let builder = KLineBuilder(instrumentID: "rb2501", period: .minute1)
        // 同一分钟内的Tick
        let _ = builder.onTick(makeTick(price: 3500, volume: 100, time: "09:01:00"))
        let _ = builder.onTick(makeTick(price: 3510, volume: 200, time: "09:01:30"))
        let _ = builder.onTick(makeTick(price: 3490, volume: 350, time: "09:01:55"))

        let bar = builder.currentKLine
        #expect(bar != nil)
        #expect(bar?.open == 3500)
        #expect(bar?.high == 3510)
        #expect(bar?.low == 3490)
        #expect(bar?.close == 3490)
    }

    @Test("跨分钟产生新K线")
    func testNewBarOnMinuteChange() {
        let builder = KLineBuilder(instrumentID: "rb2501", period: .minute1)
        let _ = builder.onTick(makeTick(price: 3500, volume: 100, time: "09:01:00"))
        let _ = builder.onTick(makeTick(price: 3510, volume: 200, time: "09:01:30"))
        // 下一分钟
        let completed = builder.onTick(makeTick(price: 3520, volume: 300, time: "09:02:00"))
        #expect(completed != nil)
        #expect(completed?.open == 3500)
        #expect(completed?.high == 3510)
        #expect(completed?.close == 3510)
    }

    @Test("过滤非本合约Tick")
    func testFilterOtherInstrument() {
        let builder = KLineBuilder(instrumentID: "rb2501", period: .minute1)
        let otherTick = Tick(
            instrumentID: "au2506", lastPrice: 500, volume: 10,
            openInterest: 0, turnover: 0,
            bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
            highestPrice: 0, lowestPrice: 0, openPrice: 0,
            preClosePrice: 0, preSettlementPrice: 0,
            upperLimitPrice: 0, lowerLimitPrice: 0,
            updateTime: "09:01:00", updateMillisec: 0,
            tradingDay: "20250115", actionDay: "20250115"
        )
        let result = builder.onTick(otherTick)
        #expect(result == nil)
        #expect(builder.currentKLine == nil)
    }

    @Test("重置")
    func testReset() {
        let builder = KLineBuilder(instrumentID: "rb2501", period: .minute1)
        let _ = builder.onTick(makeTick(price: 3500, volume: 100, time: "09:01:00"))
        #expect(builder.currentKLine != nil)
        builder.reset()
        #expect(builder.currentKLine == nil)
        #expect(builder.allBars.isEmpty)
    }
}
