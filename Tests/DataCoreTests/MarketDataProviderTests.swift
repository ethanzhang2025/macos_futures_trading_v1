// WP-31 · MarketDataProvider 协议合约测试
// 验证：订阅路由、取消订阅、清空、状态转换 — 用 MockMarketDataProvider 作为合约验证载体

import Testing
import Foundation
@testable import DataCore
import Shared

@Suite("MarketDataProvider 协议合约")
struct MarketDataProviderContractTests {

    @Test("初始状态为 disconnected")
    func initialStateIsDisconnected() async {
        let provider = MockMarketDataProvider()
        let state = await provider.connectionState()
        #expect(state == .disconnected)
    }

    @Test("状态可转换为 connected")
    func stateCanTransitionToConnected() async {
        let provider = MockMarketDataProvider()
        await provider.setState(.connected)
        let state = await provider.connectionState()
        #expect(state == .connected)
    }

    @Test("订阅后 Tick 推送到对应 handler")
    func subscribeRoutesTickToHandler() async {
        let provider = MockMarketDataProvider()
        let recv = TickBox()

        await provider.subscribe("rb2505") { tick in
            Task { await recv.set(tick.instrumentID) }
        }
        await provider.push(makeTick("rb2505"))

        // 等 Task 执行完
        try? await Task.sleep(nanoseconds: 10_000_000)
        let got = await recv.value
        #expect(got == "rb2505")
    }

    @Test("未订阅合约的 Tick 不触发任何 handler")
    func unsubscribedInstrumentIsSilent() async {
        let provider = MockMarketDataProvider()
        let recv = TickBox()

        await provider.subscribe("rb2505") { tick in
            Task { await recv.set(tick.instrumentID) }
        }
        await provider.push(makeTick("ag2506"))

        try? await Task.sleep(nanoseconds: 10_000_000)
        let got = await recv.value
        #expect(got == nil)
    }

    @Test("unsubscribe 后不再收到 Tick")
    func unsubscribeStopsDelivery() async {
        let provider = MockMarketDataProvider()
        let recv = TickBox()

        await provider.subscribe("rb2505") { tick in
            Task { await recv.set(tick.instrumentID) }
        }
        await provider.unsubscribe("rb2505")
        await provider.push(makeTick("rb2505"))

        try? await Task.sleep(nanoseconds: 10_000_000)
        let got = await recv.value
        #expect(got == nil)
    }

    @Test("unsubscribeAll 清空所有订阅")
    func unsubscribeAllClears() async {
        let provider = MockMarketDataProvider()
        await provider.subscribe("rb2505") { _ in }
        await provider.subscribe("ag2506") { _ in }

        let before = await provider.subscriberCount()
        #expect(before == 2)

        await provider.unsubscribeAll()
        let after = await provider.subscriberCount()
        #expect(after == 0)
    }
}

// MARK: - 测试辅助

/// 接收单个 Tick 合约 ID 的线程安全容器
private actor TickBox {
    private(set) var value: String?
    func set(_ v: String) { value = v }
}

/// 构造最小可用 Tick · 只填 instrumentID 关键字段，其他用 0 / 空
private func makeTick(_ instrumentID: String) -> Tick {
    Tick(
        instrumentID: instrumentID,
        lastPrice: 0, volume: 0, openInterest: 0, turnover: 0,
        bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
        highestPrice: 0, lowestPrice: 0, openPrice: 0,
        preClosePrice: 0, preSettlementPrice: 0,
        upperLimitPrice: 0, lowerLimitPrice: 0,
        updateTime: "00:00:00", updateMillisec: 0,
        tradingDay: "20260424", actionDay: "20260424"
    )
}
