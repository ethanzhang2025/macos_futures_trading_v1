// WP-21a · SimulatedMarketDataProvider 测试
// 协议合约 / 多合约隔离 / connect+disconnect / 故障注入 + 状态机集成 / 批量推送

import Testing
import Foundation
import Shared
@testable import DataCore

// MARK: - 测试辅助

private func makeTick(_ instrumentID: String, price: Decimal = 0) -> Tick {
    Tick(
        instrumentID: instrumentID,
        lastPrice: price, volume: 0, openInterest: 0, turnover: 0,
        bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
        highestPrice: 0, lowestPrice: 0, openPrice: 0,
        preClosePrice: 0, preSettlementPrice: 0,
        upperLimitPrice: 0, lowerLimitPrice: 0,
        updateTime: "00:00:00", updateMillisec: 0,
        tradingDay: "20260425", actionDay: "20260425"
    )
}

/// 收集器：actor 收尾把 handler 输入塞进数组（避免跨任务共享可变状态）
private actor TickCollector {
    private(set) var ticks: [Tick] = []
    func append(_ t: Tick) { ticks.append(t) }
    func count() -> Int { ticks.count }
}

// MARK: - 1. 连接生命周期

@Suite("SimulatedMarketDataProvider · 连接生命周期")
struct LifecycleTests {

    @Test("初始 disconnected · connect → connected · disconnect → disconnected")
    func basicLifecycle() async {
        let provider = SimulatedMarketDataProvider()
        #expect(await provider.connectionState() == .disconnected)

        await provider.connect()
        #expect(await provider.connectionState() == .connected)

        await provider.disconnect()
        #expect(await provider.connectionState() == .disconnected)
    }

    @Test("disconnect 清空所有订阅")
    func disconnectClearsSubscriptions() async {
        let provider = SimulatedMarketDataProvider()
        await provider.connect()
        await provider.subscribe("rb2510") { _ in }
        await provider.subscribe("hc2510") { _ in }
        #expect(await provider.subscriberCount() == 2)

        await provider.disconnect()
        #expect(await provider.subscriberCount() == 0)
    }
}

// MARK: - 2. 订阅与多合约隔离

@Suite("SimulatedMarketDataProvider · 订阅与多合约隔离")
struct SubscribeTests {

    @Test("push 推送到对应订阅 handler")
    func pushDispatchesToHandler() async {
        let provider = SimulatedMarketDataProvider()
        let collector = TickCollector()
        await provider.subscribe("rb2510") { tick in
            Task { await collector.append(tick) }
        }

        let pushed = await provider.push(makeTick("rb2510", price: 3500))
        #expect(pushed)

        // 等待异步 collector 完成（actor 内 task 调度）
        await Task.yield()
        await Task.yield()
        let count = await collector.count()
        #expect(count == 1)
    }

    @Test("多合约严格隔离：rb 推 rb，hc 推 hc，互不串线")
    func multiInstrumentIsolation() async {
        let provider = SimulatedMarketDataProvider()
        let collectorRB = TickCollector()
        let collectorHC = TickCollector()

        await provider.subscribe("rb2510") { tick in
            Task { await collectorRB.append(tick) }
        }
        await provider.subscribe("hc2510") { tick in
            Task { await collectorHC.append(tick) }
        }

        await provider.push(makeTick("rb2510"))
        await provider.push(makeTick("rb2510"))
        await provider.push(makeTick("hc2510"))

        for _ in 0..<5 { await Task.yield() }

        let rbCount = await collectorRB.count()
        let hcCount = await collectorHC.count()
        #expect(rbCount == 2)
        #expect(hcCount == 1)
    }

    @Test("未订阅的 push 静默丢弃")
    func unsubscribedPushSilentlyDropped() async {
        let provider = SimulatedMarketDataProvider()
        let pushed = await provider.push(makeTick("rb2510"))
        #expect(!pushed)
    }

    @Test("unsubscribe 后不再收 tick")
    func unsubscribeStopsDelivery() async {
        let provider = SimulatedMarketDataProvider()
        let collector = TickCollector()
        await provider.subscribe("rb2510") { tick in
            Task { await collector.append(tick) }
        }
        await provider.push(makeTick("rb2510"))

        await provider.unsubscribe("rb2510")
        let pushed = await provider.push(makeTick("rb2510"))
        #expect(!pushed)
        #expect(await provider.isSubscribed("rb2510") == false)
    }

    @Test("unsubscribeAll 清空所有订阅")
    func unsubscribeAllClears() async {
        let provider = SimulatedMarketDataProvider()
        await provider.subscribe("rb2510") { _ in }
        await provider.subscribe("hc2510") { _ in }
        await provider.unsubscribeAll()
        #expect(await provider.subscriberCount() == 0)
    }
}

// MARK: - 3. 批量推送

@Suite("SimulatedMarketDataProvider · 批量推送")
struct BatchPushTests {

    @Test("pushBatch 返回成功推送数（仅订阅的命中）")
    func pushBatchCount() async {
        let provider = SimulatedMarketDataProvider()
        await provider.subscribe("rb2510") { _ in }

        let ticks = [
            makeTick("rb2510"),
            makeTick("hc2510"),  // 未订阅，丢弃
            makeTick("rb2510"),
            makeTick("ag2510"),  // 未订阅，丢弃
        ]
        let delivered = await provider.pushBatch(ticks)
        #expect(delivered == 2)
    }
}

// MARK: - 4. 故障注入与状态机集成

@Suite("SimulatedMarketDataProvider · 故障注入 + 状态机集成")
struct FaultInjectionTests {

    @Test("simulateConnectionLost 转入 reconnecting + 返回退避秒数")
    func simulateConnectionLost() async {
        let backoff = ExponentialBackoff(baseDelay: 1, factor: 2, maxDelay: 100, jitterRatio: 0)
        let provider = SimulatedMarketDataProvider(backoff: backoff)
        await provider.connect()

        let delay1 = await provider.simulateConnectionLost()
        #expect(delay1 == 1)
        #expect(await provider.connectionState() == .reconnecting(attempt: 1))
        #expect(await provider.stateMachine.attemptCount == 1)

        let delay2 = await provider.simulateConnectionLost()
        #expect(delay2 == 2)
        #expect(await provider.connectionState() == .reconnecting(attempt: 2))
    }

    @Test("重连成功后 attempt 归零")
    func reconnectResetAttempt() async {
        let provider = SimulatedMarketDataProvider(backoff: NoBackoff())
        await provider.connect()
        _ = await provider.simulateConnectionLost()
        _ = await provider.simulateConnectionLost()
        #expect(await provider.stateMachine.attemptCount == 2)

        await provider.connect()  // 重新成功
        #expect(await provider.connectionState() == .connected)
        #expect(await provider.stateMachine.attemptCount == 0)
    }

    @Test("simulateError 进入 error 终态 + 不影响订阅 handler")
    func simulateErrorKeepsHandlers() async {
        let provider = SimulatedMarketDataProvider()
        await provider.connect()
        await provider.subscribe("rb2510") { _ in }

        await provider.simulateError("CTP 鉴权失败")
        #expect(await provider.connectionState() == .error("CTP 鉴权失败"))
        // handler 仍在（caller 可决定是否清理）
        #expect(await provider.subscriberCount() == 1)
    }

    @Test("AsyncStream 状态推送：connect → connected → simulateConnectionLost → reconnecting(1)")
    func observeStateSequence() async {
        let provider = SimulatedMarketDataProvider(backoff: NoBackoff())
        let stream = await provider.stateMachine.observe()

        let collectTask = Task<[ConnectionState], Never> {
            var collected: [ConnectionState] = []
            var iter = stream.makeAsyncIterator()
            for _ in 0..<4 {
                if let s = await iter.next() { collected.append(s) }
            }
            return collected
        }

        await provider.connect()
        _ = await provider.simulateConnectionLost()

        let result = await collectTask.value
        #expect(result == [
            .disconnected,
            .connecting,
            .connected,
            .reconnecting(attempt: 1),
        ])
    }
}
