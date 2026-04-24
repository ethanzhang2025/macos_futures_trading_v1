import Foundation
import Testing
@testable import TradingCore
import Shared

@Suite("条件单测试")
struct ConditionalOrderTests {
    private func makeOrder(condition: PriceCondition, type: ConditionalOrderType = .stopLoss) -> ConditionalOrder {
        ConditionalOrder(
            instrumentID: "rb2501",
            type: type,
            condition: condition,
            orderRequest: OrderRequest(
                instrumentID: "rb2501",
                direction: .sell,
                offsetFlag: .close,
                priceType: .marketPrice,
                price: 0,
                volume: 1
            )
        )
    }

    @Test("止损单 - 价格低于触发")
    func testStopLossBelow() {
        let order = makeOrder(condition: .below(3400))
        #expect(order.shouldTrigger(currentPrice: 3400, previousPrice: 3450) == true)
        #expect(order.shouldTrigger(currentPrice: 3350, previousPrice: 3450) == true)
        #expect(order.shouldTrigger(currentPrice: 3450, previousPrice: 3500) == false)
    }

    @Test("止盈单 - 价格高于触发")
    func testTakeProfitAbove() {
        let order = makeOrder(condition: .above(3600), type: .takeProfit)
        #expect(order.shouldTrigger(currentPrice: 3600, previousPrice: 3550) == true)
        #expect(order.shouldTrigger(currentPrice: 3550, previousPrice: 3500) == false)
    }

    @Test("上穿触发")
    func testCrossAbove() {
        let order = makeOrder(condition: .crossAbove(3500))
        #expect(order.shouldTrigger(currentPrice: 3510, previousPrice: 3490) == true)
        #expect(order.shouldTrigger(currentPrice: 3510, previousPrice: 3510) == false)
        // 无前值不触发
        #expect(order.shouldTrigger(currentPrice: 3510, previousPrice: nil) == false)
    }

    @Test("管理器 - 添加和触发")
    func testManagerTrigger() {
        let mgr = ConditionalOrderManager()
        let order = makeOrder(condition: .below(3400))
        mgr.add(order)
        #expect(mgr.activeOrders.count == 1)

        // 价格未触及
        let t1 = mgr.checkTrigger(instrumentID: "rb2501", currentPrice: 3450)
        #expect(t1.isEmpty)

        // 价格触及
        let t2 = mgr.checkTrigger(instrumentID: "rb2501", currentPrice: 3390)
        #expect(t2.count == 1)

        // 触发后不再是活跃
        #expect(mgr.activeOrders.isEmpty)
    }

    @Test("管理器 - 取消")
    func testCancel() {
        let mgr = ConditionalOrderManager()
        let order = makeOrder(condition: .below(3400))
        mgr.add(order)
        mgr.cancel(order.id)
        #expect(mgr.activeOrders.isEmpty)
    }

    @Test("管理器 - 暂停恢复")
    func testPauseResume() {
        let mgr = ConditionalOrderManager()
        mgr.add(makeOrder(condition: .below(3400)))
        mgr.pauseAll()
        #expect(mgr.activeOrders.isEmpty)
        mgr.resumeAll()
        #expect(mgr.activeOrders.count == 1)
    }

    @Test("已取消的条件单不触发")
    func testCancelledNotTrigger() {
        let order = ConditionalOrder(
            instrumentID: "rb2501", type: .stopLoss,
            condition: .below(3400),
            orderRequest: OrderRequest(instrumentID: "rb2501", direction: .sell, offsetFlag: .close, priceType: .marketPrice, price: 0, volume: 1),
            status: .cancelled
        )
        #expect(order.shouldTrigger(currentPrice: 3300, previousPrice: 3500) == false)
    }
}
