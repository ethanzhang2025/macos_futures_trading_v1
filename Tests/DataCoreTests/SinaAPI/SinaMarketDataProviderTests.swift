// WP-31a · SinaMarketDataProvider 测试
// 注入 stub fetcher（不打真网络）；覆盖订阅 / pollOnce 分发 / 多合约隔离 / 网络失败状态机 / 连接生命周期

import Testing
import Foundation
import Shared
@testable import DataCore

// MARK: - 测试 stub

/// 注入式 fetcher：可预设返回结果队列；记录每次调用的 symbols
private actor StubQuoteFetcher: SinaQuoteFetching {
    private var queued: [Result<[SinaQuote], Error>] = []
    private(set) var calls: [[String]] = []

    func enqueue(_ result: Result<[SinaQuote], Error>) {
        queued.append(result)
    }

    func recordedCalls() -> [[String]] { calls }

    func fetchQuotes(symbols: [String]) async throws -> [SinaQuote] {
        calls.append(symbols)
        guard !queued.isEmpty else { return [] }
        let result = queued.removeFirst()
        switch result {
        case .success(let quotes): return quotes
        case .failure(let error): throw error
        }
    }
}

/// Tick 收集器（按合约分桶）
private actor TickCollector {
    private(set) var buckets: [String: [Tick]] = [:]
    func append(_ tick: Tick) {
        buckets[tick.instrumentID, default: []].append(tick)
    }
    func count(_ instrumentID: String) -> Int { buckets[instrumentID]?.count ?? 0 }
    func ticks(_ instrumentID: String) -> [Tick] { buckets[instrumentID] ?? [] }
    func totalCount() -> Int { buckets.values.reduce(0) { $0 + $1.count } }
}

private func sampleQuote(symbol: String, lastPrice: Decimal) -> SinaQuote {
    SinaQuote(
        symbol: symbol, name: symbol,
        open: lastPrice, high: lastPrice, low: lastPrice, close: lastPrice,
        bidPrice: lastPrice - 1, askPrice: lastPrice + 1, lastPrice: lastPrice,
        settlementPrice: lastPrice, preSettlement: lastPrice,
        bidVolume: 10, askVolume: 10, openInterest: 100, volume: 1000,
        timestamp: "2026-04-25 09:30:00"
    )
}

// MARK: - 1. 协议合约 · 订阅管理

@Suite("SinaMarketDataProvider · 订阅管理")
struct SinaProviderSubscriptionTests {

    @Test("初始无订阅")
    func initialEmpty() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        #expect(await provider.subscriberCount() == 0)
        #expect(await provider.isSubscribed("RB0") == false)
    }

    @Test("subscribe 注册 handler")
    func subscribeRegisters() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        await provider.subscribe("RB0") { _ in }
        #expect(await provider.subscriberCount() == 1)
        #expect(await provider.isSubscribed("RB0"))
    }

    @Test("unsubscribe 移除 handler")
    func unsubscribeRemoves() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        await provider.subscribe("RB0") { _ in }
        await provider.unsubscribe("RB0")
        #expect(await provider.subscriberCount() == 0)
    }

    @Test("unsubscribeAll 清空")
    func unsubscribeAllClears() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        await provider.subscribe("RB0") { _ in }
        await provider.subscribe("IF0") { _ in }
        await provider.unsubscribeAll()
        #expect(await provider.subscriberCount() == 0)
    }

    @Test("重复 subscribe 同一合约 → 后者覆盖前者")
    func subscribeReplaces() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        let collector = TickCollector()
        await provider.subscribe("RB0") { _ in /* 不会被调用 */ }
        await provider.subscribe("RB0") { tick in
            Task { await collector.append(tick) }
        }
        #expect(await provider.subscriberCount() == 1)
    }
}

// MARK: - 2. pollOnce 分发

@Suite("SinaMarketDataProvider · pollOnce 分发")
struct SinaProviderPollTests {

    @Test("无订阅时 pollOnce 不调 fetcher")
    func emptyPollSkipsFetcher() async {
        let fetcher = StubQuoteFetcher()
        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let count = await provider.pollOnce()
        #expect(count == 0)
        #expect(await fetcher.recordedCalls().isEmpty)
    }

    @Test("单合约：handler 收到对应 Tick")
    func singleSymbolDispatch() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.success([sampleQuote(symbol: "RB0", lastPrice: 3520)]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let collector = TickCollector()
        await provider.subscribe("RB0") { tick in
            Task { await collector.append(tick) }
        }

        let dispatched = await provider.pollOnce()
        // 异步 Task 入桶，等微秒级 yield 完成
        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(dispatched == 1)
        #expect(await collector.count("RB0") == 1)
        let ticks = await collector.ticks("RB0")
        #expect(ticks.first?.lastPrice == 3520)
    }

    @Test("多合约一次拉取 → 按 instrumentID 精确分发")
    func multiSymbolDispatch() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.success([
            sampleQuote(symbol: "RB0", lastPrice: 3520),
            sampleQuote(symbol: "IF0", lastPrice: 4100),
            sampleQuote(symbol: "AU0", lastPrice: 580)
        ]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let collector = TickCollector()
        for sym in ["RB0", "IF0", "AU0"] {
            await provider.subscribe(sym) { tick in
                Task { await collector.append(tick) }
            }
        }

        _ = await provider.pollOnce()
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(await collector.count("RB0") == 1)
        #expect(await collector.count("IF0") == 1)
        #expect(await collector.count("AU0") == 1)
        #expect(await collector.totalCount() == 3)
    }

    @Test("未订阅合约的 quote 静默丢弃")
    func unknownSymbolDropped() async {
        let fetcher = StubQuoteFetcher()
        // fetcher 返回 RB0 + IF0；但 provider 仅订阅 RB0
        await fetcher.enqueue(.success([
            sampleQuote(symbol: "RB0", lastPrice: 3520),
            sampleQuote(symbol: "IF0", lastPrice: 4100)
        ]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let collector = TickCollector()
        await provider.subscribe("RB0") { tick in
            Task { await collector.append(tick) }
        }

        let dispatched = await provider.pollOnce()
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(dispatched == 1)
        #expect(await collector.count("IF0") == 0)
    }

    @Test("部分合约解析失败：fetcher 返回少于订阅数 → 仅成功的分发")
    func partialFailure() async {
        let fetcher = StubQuoteFetcher()
        // 订阅 3 个，fetcher 仅返回 RB0
        await fetcher.enqueue(.success([sampleQuote(symbol: "RB0", lastPrice: 3520)]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let collector = TickCollector()
        for sym in ["RB0", "IF0", "AU0"] {
            await provider.subscribe(sym) { tick in
                Task { await collector.append(tick) }
            }
        }

        let dispatched = await provider.pollOnce()
        try? await Task.sleep(nanoseconds: 10_000_000)

        #expect(dispatched == 1)
        #expect(await collector.count("RB0") == 1)
        #expect(await collector.count("IF0") == 0)
        #expect(await collector.count("AU0") == 0)
    }

    @Test("fetcher 拉取所有订阅合约（call symbols 与订阅集合一致）")
    func fetcherReceivesAllSubscribedSymbols() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.success([]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        for sym in ["RB0", "IF0"] {
            await provider.subscribe(sym) { _ in }
        }

        _ = await provider.pollOnce()
        let calls = await fetcher.recordedCalls()
        #expect(calls.count == 1)
        #expect(Set(calls[0]) == Set(["RB0", "IF0"]))
    }
}

// MARK: - 3. 网络失败 → 状态机

private struct StubError: Error {}

@Suite("SinaMarketDataProvider · 网络失败状态机")
struct SinaProviderFailureTests {

    @Test("fetcher 抛错 → reportConnectionLost · 状态变 reconnecting")
    func networkFailureTransitionsToReconnecting() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.failure(StubError()))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        await provider.connect()
        await provider.subscribe("RB0") { _ in }

        let dispatched = await provider.pollOnce()
        #expect(dispatched == 0)

        let state = await provider.connectionState()
        switch state {
        case .reconnecting(let attempt):
            #expect(attempt == 1)
        default:
            Issue.record("期望 reconnecting，实得 \(state)")
        }
    }

    @Test("连续失败：attempt 计数递增")
    func attemptCountIncrements() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.failure(StubError()))
        await fetcher.enqueue(.failure(StubError()))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        await provider.connect()
        await provider.subscribe("RB0") { _ in }

        _ = await provider.pollOnce()
        _ = await provider.pollOnce()

        let state = await provider.connectionState()
        switch state {
        case .reconnecting(let attempt):
            #expect(attempt == 2)
        default:
            Issue.record("期望 reconnecting(attempt: 2)")
        }
    }

    @Test("失败后再成功：状态机能复原 connected（先 reset 再 connect）")
    func recoveryFromFailure() async {
        let fetcher = StubQuoteFetcher()
        await fetcher.enqueue(.failure(StubError()))
        await fetcher.enqueue(.success([sampleQuote(symbol: "RB0", lastPrice: 3520)]))

        let provider = SinaMarketDataProvider(fetcher: fetcher)
        await provider.connect()
        await provider.subscribe("RB0") { _ in }

        _ = await provider.pollOnce()
        // 失败后 caller 应主动 reconnect（这里直接调 connect 复位）
        await provider.connect()
        _ = await provider.pollOnce()

        let state = await provider.connectionState()
        #expect(state == .connected)
    }
}

// MARK: - 4. 连接生命周期

@Suite("SinaMarketDataProvider · 连接生命周期")
struct SinaProviderLifecycleTests {

    @Test("初始 disconnected")
    func initialDisconnected() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        #expect(await provider.connectionState() == .disconnected)
    }

    @Test("connect → connected")
    func connectTransitions() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        await provider.connect()
        #expect(await provider.connectionState() == .connected)
    }

    @Test("disconnect → 清空订阅 + 状态 disconnected")
    func disconnectClearsSubscriptions() async {
        let provider = SinaMarketDataProvider(fetcher: StubQuoteFetcher())
        await provider.connect()
        await provider.subscribe("RB0") { _ in }
        await provider.subscribe("IF0") { _ in }
        #expect(await provider.subscriberCount() == 2)

        await provider.disconnect()
        #expect(await provider.subscriberCount() == 0)
        #expect(await provider.connectionState() == .disconnected)
    }
}
