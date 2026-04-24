import Foundation
import Testing
@testable import TradingCore
import Shared

@Suite("追踪止损测试")
struct TrailingStopTests {
    @Test("多头追踪止损 - 价格上涨时止损价跟随上移")
    func testLongTrailUp() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .long, trailAmount: 20, orderVolume: 1)
        #expect(ts.update(currentPrice: 3500) == false)
        #expect(ts.currentStopPrice == 3480)
        // 价格上涨
        #expect(ts.update(currentPrice: 3530) == false)
        #expect(ts.currentStopPrice == 3510) // 跟随上移
        #expect(ts.highestPrice == 3530)
    }

    @Test("多头追踪止损 - 回落触发")
    func testLongTrailTrigger() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .long, trailAmount: 20, orderVolume: 1)
        _ = ts.update(currentPrice: 3500)
        _ = ts.update(currentPrice: 3530) // 最高3530，止损3510
        #expect(ts.update(currentPrice: 3510) == true) // 触发
        #expect(ts.status == .triggered)
    }

    @Test("空头追踪止损 - 价格下跌时止损价跟随下移")
    func testShortTrailDown() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .short, trailAmount: 20, orderVolume: 1)
        _ = ts.update(currentPrice: 3500)
        #expect(ts.currentStopPrice == 3520)
        _ = ts.update(currentPrice: 3470) // 新低
        #expect(ts.currentStopPrice == 3490) // 跟随下移
        #expect(ts.lowestPrice == 3470)
    }

    @Test("空头追踪止损 - 反弹触发")
    func testShortTrailTrigger() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .short, trailAmount: 20, orderVolume: 1)
        _ = ts.update(currentPrice: 3500)
        _ = ts.update(currentPrice: 3470) // 最低3470，止损3490
        #expect(ts.update(currentPrice: 3490) == true) // 触发
        #expect(ts.status == .triggered)
    }

    @Test("止损价只跟随有利方向，不回退")
    func testStopPriceNoRetreat() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .long, trailAmount: 20, orderVolume: 1)
        _ = ts.update(currentPrice: 3500) // 止损3480
        _ = ts.update(currentPrice: 3530) // 止损3510
        _ = ts.update(currentPrice: 3520) // 价格回落但未触发
        #expect(ts.currentStopPrice == 3510) // 止损价不回退
        #expect(ts.update(currentPrice: 3520) == false)
    }

    @Test("生成平仓委托")
    func testMakeCloseOrder() {
        let ts = TrailingStop(instrumentID: "rb2501", direction: .long, trailAmount: 20, orderVolume: 3)
        let order = ts.makeCloseOrder()
        #expect(order.instrumentID == "rb2501")
        #expect(order.direction == .sell) // 多头持仓 → 卖出平仓
        #expect(order.offsetFlag == .close)
        #expect(order.volume == 3)
    }

    @Test("已触发不再响应")
    func testTriggeredNoResponse() {
        var ts = TrailingStop(instrumentID: "rb2501", direction: .long, trailAmount: 20, orderVolume: 1)
        _ = ts.update(currentPrice: 3500)
        _ = ts.update(currentPrice: 3480) // 触发
        #expect(ts.update(currentPrice: 3400) == false) // 已触发，不再响应
    }
}

@Suite("OCO单测试")
struct OCOOrderTests {
    private func makeOCO(stopAt: Decimal, profitAt: Decimal) -> OCOOrder {
        OCOOrder(
            instrumentID: "rb2501",
            stopLoss: .below(stopAt),
            takeProfit: .above(profitAt),
            stopLossOrder: OrderRequest(instrumentID: "rb2501", direction: .sell, offsetFlag: .close, priceType: .marketPrice, price: 0, volume: 1),
            takeProfitOrder: OrderRequest(instrumentID: "rb2501", direction: .sell, offsetFlag: .close, priceType: .limitPrice, price: profitAt, volume: 1)
        )
    }

    @Test("止损先触发")
    func testStopLossTriggers() {
        var oco = makeOCO(stopAt: 3400, profitAt: 3600)
        let order = oco.check(currentPrice: 3390, previousPrice: 3450)
        #expect(order != nil)
        #expect(oco.triggeredSide == .stopLoss)
        #expect(oco.status == .triggered)
    }

    @Test("止盈先触发")
    func testTakeProfitTriggers() {
        var oco = makeOCO(stopAt: 3400, profitAt: 3600)
        let order = oco.check(currentPrice: 3610, previousPrice: 3550)
        #expect(order != nil)
        #expect(oco.triggeredSide == .takeProfit)
        #expect(order?.priceType == .limitPrice)
    }

    @Test("未触发时返回nil")
    func testNoTrigger() {
        var oco = makeOCO(stopAt: 3400, profitAt: 3600)
        let order = oco.check(currentPrice: 3500, previousPrice: 3490)
        #expect(order == nil)
        #expect(oco.status == .active)
    }

    @Test("触发后不再响应")
    func testTriggeredNoResponse() {
        var oco = makeOCO(stopAt: 3400, profitAt: 3600)
        _ = oco.check(currentPrice: 3390, previousPrice: 3450) // 触发止损
        let order2 = oco.check(currentPrice: 3610, previousPrice: 3550) // 再检查
        #expect(order2 == nil) // 已触发，不再响应
    }
}

@Suite("括号单测试")
struct BracketOrderTests {
    @Test("开仓成交后生成OCO")
    func testEntryFilled() {
        var bracket = BracketOrder(
            instrumentID: "rb2501",
            direction: .buy,
            entryOrder: OrderRequest(instrumentID: "rb2501", direction: .buy, offsetFlag: .open, priceType: .limitPrice, price: 3500, volume: 2),
            stopLossOffset: 50,
            takeProfitOffset: 100
        )
        #expect(bracket.status == .pendingEntry)

        let oco = bracket.onEntryFilled(fillPrice: 3500)
        #expect(bracket.status == .entryFilled)
        #expect(bracket.entryPrice == 3500)
        // 止损在3450，止盈在3600
        #expect(bracket.ocoOrder != nil)

        // 验证OCO能正常工作
        var mutableOCO = oco
        let order = mutableOCO.check(currentPrice: 3440, previousPrice: 3460)
        #expect(order != nil) // 止损触发
        #expect(order?.direction == .sell) // 平多
        #expect(order?.volume == 2)
    }

    @Test("卖出开空的括号单")
    func testShortBracket() {
        var bracket = BracketOrder(
            instrumentID: "rb2501",
            direction: .sell,
            entryOrder: OrderRequest(instrumentID: "rb2501", direction: .sell, offsetFlag: .open, priceType: .limitPrice, price: 3500, volume: 1),
            stopLossOffset: 50,
            takeProfitOffset: 100
        )
        let oco = bracket.onEntryFilled(fillPrice: 3500)
        // 空头：止损在3550，止盈在3400
        var mutableOCO = oco
        let order = mutableOCO.check(currentPrice: 3390, previousPrice: 3410)
        #expect(order != nil) // 止盈触发
        #expect(mutableOCO.triggeredSide == .takeProfit)
        #expect(order?.direction == .buy) // 平空
    }
}
