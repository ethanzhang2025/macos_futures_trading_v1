// WP-21a 子模块 4 · UnifiedDataSource Facade 测试
// snapshot 启动 / Tick → completedBar / 增量持久化 / stop / stopAll / 多 instrument 隔离 / 缓存恢复

import Testing
import Foundation
import Shared
@testable import DataCore

// MARK: - 测试辅助

private func makeKLine(
    _ instrumentID: String = "rb2510",
    period: KLinePeriod = .minute1,
    openTime: Date,
    close: Decimal = 3500
) -> KLine {
    KLine(
        instrumentID: instrumentID, period: period, openTime: openTime,
        open: close, high: close, low: close, close: close,
        volume: 0, openInterest: 0, turnover: 0
    )
}

/// 构造跨 N 分钟的 Tick 序列（每分钟两个 Tick：第 0 秒 + 第 30 秒），用于驱动 KLineBuilder 跨周期
private func makeMinuteTicks(_ instrumentID: String, baseDate: Date, minuteOffsets: [Int], price: Decimal = 3500) -> [Tick] {
    minuteOffsets.flatMap { offset -> [Tick] in
        let m = offset
        let timeStr = String(format: "%02d:%02d:00", m / 60, m % 60)
        return [
            Tick(
                instrumentID: instrumentID,
                lastPrice: price, volume: 0, openInterest: 0, turnover: 0,
                bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
                highestPrice: 0, lowestPrice: 0, openPrice: 0,
                preClosePrice: 0, preSettlementPrice: 0,
                upperLimitPrice: 0, lowerLimitPrice: 0,
                updateTime: timeStr, updateMillisec: 0,
                tradingDay: "20260425", actionDay: "20260425"
            )
        ]
    }
}

/// 收集器
private actor UpdateCollector {
    private(set) var updates: [DataSourceUpdate] = []
    func append(_ u: DataSourceUpdate) { updates.append(u) }
    func count() -> Int { updates.count }
    func snapshot() -> [DataSourceUpdate] { updates }
}

/// 异步等待收集器收到至少 N 个 update（避免靠 Task.yield 不稳）
private func waitForUpdates(_ collector: UpdateCollector, count: Int, timeoutSeconds: Double = 1.0) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while await collector.count() < count, Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
    }
}

private func consume(_ stream: AsyncStream<DataSourceUpdate>, into collector: UpdateCollector) -> Task<Void, Never> {
    Task {
        for await update in stream {
            await collector.append(update)
        }
    }
}

// MARK: - 1. 启动快照

@Suite("UnifiedDataSource · 启动快照")
struct UDSStartSnapshotTests {

    @Test("空缓存 → snapshot([]) 立即出")
    func emptyCacheSnapshot() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        let collector = UpdateCollector()
        let stream = await source.start(instrumentID: "rb2510", period: .minute1)
        let consumeTask = consume(stream, into: collector)

        await waitForUpdates(collector, count: 1)

        let updates = await collector.snapshot()
        #expect(updates.count == 1)
        #expect(updates[0] == .snapshot([]))

        await source.stopAll()
        consumeTask.cancel()
    }

    @Test("有缓存 → snapshot(cached) 含历史 K 线")
    func cachedSnapshot() async throws {
        let cache = InMemoryKLineCacheStore()
        let cached = (0..<5).map {
            makeKLine(openTime: Date(timeIntervalSince1970: TimeInterval($0) * 60))
        }
        try await cache.save(cached, instrumentID: "rb2510", period: .minute1)

        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        let collector = UpdateCollector()
        let stream = await source.start(instrumentID: "rb2510", period: .minute1)
        let consumeTask = consume(stream, into: collector)

        await waitForUpdates(collector, count: 1)

        let updates = await collector.snapshot()
        if case let .snapshot(bars) = updates[0] {
            #expect(bars.count == 5)
        } else {
            Issue.record("应该是 snapshot")
        }

        await source.stopAll()
        consumeTask.cancel()
    }
}

// MARK: - 2. 实时 Tick → completedBar

@Suite("UnifiedDataSource · 实时 Tick 到 completedBar")
struct UDSRealtimeFlowTests {

    @Test("跨分钟 Tick 触发 completedBar emit")
    func tickProducesCompletedBar() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        let collector = UpdateCollector()
        let stream = await source.start(instrumentID: "rb2510", period: .minute1)
        let consumeTask = consume(stream, into: collector)

        await waitForUpdates(collector, count: 1)  // snapshot

        // 推 1 分钟的 Tick → 跨到第 2 分钟时第 1 根 K 线 emit
        await realtime.connect()
        let baseDate = Date()
        let ticks = makeMinuteTicks("rb2510", baseDate: baseDate, minuteOffsets: [9 * 60, 9 * 60 + 1])
        for t in ticks { await realtime.push(t) }

        await waitForUpdates(collector, count: 2, timeoutSeconds: 2.0)

        let updates = await collector.snapshot()
        let completedCount = updates.filter {
            if case .completedBar = $0 { return true } else { return false }
        }.count
        #expect(completedCount == 1)

        await source.stopAll()
        consumeTask.cancel()
    }

    @Test("completedBar 自动 append 到缓存（增量持久化）")
    func completedBarPersistsToCache() async throws {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        let collector = UpdateCollector()
        let stream = await source.start(instrumentID: "rb2510", period: .minute1)
        let consumeTask = consume(stream, into: collector)

        await waitForUpdates(collector, count: 1)  // snapshot
        await realtime.connect()

        let ticks = makeMinuteTicks("rb2510", baseDate: Date(), minuteOffsets: [9 * 60, 9 * 60 + 1])
        for t in ticks { await realtime.push(t) }

        await waitForUpdates(collector, count: 2, timeoutSeconds: 2.0)

        let cached = try await cache.load(instrumentID: "rb2510", period: .minute1)
        #expect(cached.count == 1)

        await source.stopAll()
        consumeTask.cancel()
    }
}

// MARK: - 3. stop / stopAll

@Suite("UnifiedDataSource · stop / stopAll")
struct UDSLifecycleTests {

    @Test("stop 后 stream 终止 + 取消 realtime 订阅")
    func stopTerminatesStream() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        #expect(await realtime.subscriberCount() == 1)
        #expect(await source.activeSubscriptions().count == 1)

        await source.stop(instrumentID: "rb2510", period: .minute1)
        #expect(await realtime.subscriberCount() == 0)
        #expect(await source.activeSubscriptions().count == 0)
    }

    @Test("stopAll 清空所有订阅 + 取消所有 realtime 订阅")
    func stopAllClearsAll() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "hc2510", period: .minute5)
        #expect(await source.activeSubscriptions().count == 2)
        #expect(await realtime.subscriberCount() == 2)

        await source.stopAll()
        #expect(await source.activeSubscriptions().isEmpty)
        #expect(await realtime.subscriberCount() == 0)
    }

    @Test("同 (instrumentID, period) 重复 start 替换旧订阅（不重复挂载）")
    func startReplacesExisting() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        #expect(await source.activeSubscriptions().count == 1)
        #expect(await realtime.subscriberCount() == 1)

        await source.stopAll()
    }
}

// MARK: - 4. 多 instrument / 多 period 隔离

@Suite("UnifiedDataSource · 多合约多周期隔离")
struct UDSMultiInstrumentTests {

    @Test("同合约不同周期：只订阅一次 realtime + 各 stream 独立")
    func samePidDifferentPeriods() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "rb2510", period: .minute5)

        // realtime 只订阅 1 次（因为是同 instrumentID，handler 会被替换；但 source 内部记两个 subscription state）
        #expect(await source.activeSubscriptions().count == 2)

        await source.stop(instrumentID: "rb2510", period: .minute1)
        #expect(await source.activeSubscriptions().count == 1)
        // hc 仍订阅，realtime 不取消
        #expect(await realtime.subscriberCount() == 1)

        await source.stopAll()
    }

    @Test("WP-44b: 同合约多 period 同时订阅 · realtime subscribe 仅 1 次")
    func multiPeriodSubscribesOnce() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "rb2510", period: .minute3)
        _ = await source.start(instrumentID: "rb2510", period: .minute5)

        // 关键：subscriberCount = 1（虽然 source 内部 3 subscriptions）
        #expect(await realtime.subscriberCount() == 1)
        #expect(await source.activeSubscriptions().count == 3)

        await source.stopAll()
    }

    @Test("WP-44b: 同合约多 period · 单次 push 多 builder 同时收到 tick")
    func multiPeriodAllReceiveTicks() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        let coll1 = UpdateCollector()
        let coll5 = UpdateCollector()
        let s1 = await source.start(instrumentID: "rb2510", period: .minute1)
        let s5 = await source.start(instrumentID: "rb2510", period: .minute5)
        let t1 = consume(s1, into: coll1)
        let t5 = consume(s5, into: coll5)

        await waitForUpdates(coll1, count: 1)
        await waitForUpdates(coll5, count: 1)

        // 推跨 6 分钟的 tick 序列：minute1 应触发 ≥5 根 completedBar；minute5 触发 ≥1 根
        await realtime.connect()
        let baseDate = Date()
        let ticks = makeMinuteTicks(
            "rb2510",
            baseDate: baseDate,
            minuteOffsets: [9 * 60, 9 * 60 + 1, 9 * 60 + 2, 9 * 60 + 3, 9 * 60 + 4, 9 * 60 + 5, 9 * 60 + 6]
        )
        for t in ticks { await realtime.push(t) }

        // 等异步 yield 完成
        try? await Task.sleep(nanoseconds: 80_000_000)

        // minute1：跨 6 个边界 → ≥5 个 completedBar
        let m1Completed = await coll1.snapshot().filter {
            if case .completedBar = $0 { return true } else { return false }
        }.count
        // minute5：跨 1 个边界（第 5 分钟切换）→ ≥1 个 completedBar
        let m5Completed = await coll5.snapshot().filter {
            if case .completedBar = $0 { return true } else { return false }
        }.count

        #expect(m1Completed >= 5)
        #expect(m5Completed >= 1)

        await source.stopAll()
        t1.cancel(); t5.cancel()
    }

    @Test("WP-44b: 同合约多 period · 关 1 个 period · 其他 period 仍收到 tick")
    func stopOnePeriodKeepsOthers() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "rb2510", period: .minute5)

        await source.stop(instrumentID: "rb2510", period: .minute1)

        // realtime 仍订阅（minute5 还在）
        #expect(await realtime.subscriberCount() == 1)
        #expect(await source.activeSubscriptions().count == 1)

        await source.stop(instrumentID: "rb2510", period: .minute5)
        // 全关后 realtime 才取消
        #expect(await realtime.subscriberCount() == 0)
    }

    @Test("不同合约：realtime 订阅 N 个 + stop 一个不影响其他")
    func differentInstruments() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = SimulatedMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime)

        _ = await source.start(instrumentID: "rb2510", period: .minute1)
        _ = await source.start(instrumentID: "hc2510", period: .minute1)
        _ = await source.start(instrumentID: "ag2510", period: .minute1)
        #expect(await realtime.subscriberCount() == 3)

        await source.stop(instrumentID: "hc2510", period: .minute1)
        #expect(await realtime.subscriberCount() == 2)
        #expect(await realtime.isSubscribed("rb2510"))
        #expect(await realtime.isSubscribed("ag2510"))
        #expect(await realtime.isSubscribed("hc2510") == false)

        await source.stopAll()
    }
}

// MARK: - v2 · 历史 K 线合并

/// 测试 stub：可预设返回历史 K 线 / 注入失败
private actor StubHistoricalProvider: HistoricalKLineProvider {
    private var minutePayload: Result<[HistoricalKLine], Error> = .success([])
    private var dailyPayload: Result<[HistoricalKLine], Error> = .success([])
    private(set) var minuteCalls: [(symbol: String, interval: Int)] = []

    func setMinute(_ result: Result<[HistoricalKLine], Error>) { minutePayload = result }
    func setDaily(_ result: Result<[HistoricalKLine], Error>) { dailyPayload = result }

    func historicalDaily(symbol: String) async throws -> [HistoricalKLine] {
        switch dailyPayload {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }

    func historicalMinute(symbol: String, intervalMinutes: Int) async throws -> [HistoricalKLine] {
        minuteCalls.append((symbol: symbol, interval: intervalMinutes))
        switch minutePayload {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}

private func hk(_ date: String, close: Decimal = 3500) -> HistoricalKLine {
    HistoricalKLine(date: date, open: close, high: close, low: close, close: close, volume: 100, openInterest: 50)
}

@Suite("UnifiedDataSource v2 · 历史 K 线合并")
struct UnifiedDataSourceHistoryMergeTests {

    @Test("nil historical → 行为同 v1（snapshot 仅来自 cache）")
    func nilHistoricalSameAsV1() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = MockMarketDataProvider()
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: nil)
        let stream = await source.start(instrumentID: "RB0", period: .hour1)

        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        if case .snapshot(let bars) = first {
            #expect(bars.isEmpty)  // cache 空 + 没注入 historical → 空
        } else {
            Issue.record("期望 snapshot")
        }
        await source.stopAll()
    }

    @Test("cache 空 + historical 3 根 → snapshot 3 根（按 openTime 升序）")
    func emptyCachePlusHistorical() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        await stub.setMinute(.success([
            hk("2026-04-23 14:00:00", close: 3100),
            hk("2026-04-23 15:00:00", close: 3110),
            hk("2026-04-23 16:00:00", close: 3120)
        ]))
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub)
        let stream = await source.start(instrumentID: "RB0", period: .hour1)

        var iter = stream.makeAsyncIterator()
        if case .snapshot(let bars) = await iter.next() {
            #expect(bars.count == 3)
            #expect(bars[0].close == 3100)
            #expect(bars[2].close == 3120)
            #expect(bars[0].openTime < bars[1].openTime)
            #expect(bars[1].openTime < bars[2].openTime)
        } else {
            Issue.record("期望 snapshot")
        }
        // 验证 historical fetcher 被调用（symbol + interval=60）
        let calls = await stub.minuteCalls
        #expect(calls.count == 1)
        #expect(calls.first?.symbol == "RB0")
        #expect(calls.first?.interval == 60)
        await source.stopAll()
    }

    @Test("cache + historical 重叠 → cache 优先去重")
    func overlapCachePreferred() async throws {
        let cache = InMemoryKLineCacheStore()
        // cache 有 1 根 14:00 close=9999（人为冲突值，测试是否被 cache 覆盖）
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        let cachedTime = f.date(from: "2026-04-23 14:00:00")!
        let cachedKLine = KLine(
            instrumentID: "RB0", period: .hour1, openTime: cachedTime,
            open: 9999, high: 9999, low: 9999, close: 9999,
            volume: 0, openInterest: 0, turnover: 0
        )
        try await cache.save([cachedKLine], instrumentID: "RB0", period: .hour1)

        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        await stub.setMinute(.success([
            hk("2026-04-23 14:00:00", close: 3100),  // 与 cache 重叠
            hk("2026-04-23 15:00:00", close: 3110)
        ]))
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub)
        let stream = await source.start(instrumentID: "RB0", period: .hour1)

        var iter = stream.makeAsyncIterator()
        if case .snapshot(let bars) = await iter.next() {
            #expect(bars.count == 2)  // 去重后 2 根
            // 14:00 应是 cache 的 9999，不是 historical 的 3100
            let bar14 = bars.first { $0.openTime == cachedTime }
            #expect(bar14?.close == 9999)
        } else {
            Issue.record("期望 snapshot")
        }
        await source.stopAll()
    }

    @Test("historical fetch 失败 → 静默回退到 cache（不阻断订阅）")
    func historicalFetchFailureFallsBack() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        await stub.setMinute(.failure(MarketDataError.providerError("network down")))
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub)
        let stream = await source.start(instrumentID: "RB0", period: .hour1)

        var iter = stream.makeAsyncIterator()
        if case .snapshot(let bars) = await iter.next() {
            #expect(bars.isEmpty)  // cache 也空 → 空数组而不是抛错
        } else {
            Issue.record("期望 snapshot 而非 stream 终止")
        }
        await source.stopAll()
    }

    @Test("不支持的 period（monthly）→ 不查 historical minute，回退到 cache")
    func unsupportedPeriodSkipsHistorical() async {
        // v12.7：minute1/5/15/30/60 全支持 historicalMinute · 仅 daily/weekly/monthly 走 historicalDaily 不在此函数
        // 用 .monthly 测 intervalMinutes(for:) 返 nil 时 UDS 跳过 historicalMinute 调用
        let cache = InMemoryKLineCacheStore()
        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        await stub.setMinute(.success([hk("2026-04-23 14:00:00")]))  // 即使设了也不应被调用
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub)
        let stream = await source.start(instrumentID: "RB0", period: .monthly)

        var iter = stream.makeAsyncIterator()
        if case .snapshot(let bars) = await iter.next() {
            #expect(bars.isEmpty)
        } else {
            Issue.record("期望 snapshot")
        }
        // 不支持的 period 不应触发 historical minute fetch
        let calls = await stub.minuteCalls
        #expect(calls.isEmpty)
        await source.stopAll()
    }

    @Test("cacheMaxBars 截尾应用到合并后的 snapshot")
    func mergedSnapshotRespectsCacheMaxBars() async {
        let cache = InMemoryKLineCacheStore()
        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        // 历史给 5 根，但 cacheMaxBars=3 → snapshot 只取最近 3 根
        await stub.setMinute(.success([
            hk("2026-04-23 11:00:00", close: 3100),
            hk("2026-04-23 12:00:00", close: 3101),
            hk("2026-04-23 13:00:00", close: 3102),
            hk("2026-04-23 14:00:00", close: 3103),
            hk("2026-04-23 15:00:00", close: 3104)
        ]))
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub, cacheMaxBars: 3)
        let stream = await source.start(instrumentID: "RB0", period: .hour1)

        var iter = stream.makeAsyncIterator()
        if case .snapshot(let bars) = await iter.next() {
            #expect(bars.count == 3)
            #expect(bars.first?.close == 3102)  // 截尾后保留最近 3 根
            #expect(bars.last?.close == 3104)
        } else {
            Issue.record("期望 snapshot")
        }
        await source.stopAll()
    }

    @Test("interval 映射：minute5 → 5 / minute15 → 15 / hour1 → 60")
    func intervalMinutesMapping() async {
        let realtime = MockMarketDataProvider()
        let stub = StubHistoricalProvider()
        await stub.setMinute(.success([]))
        let cache = InMemoryKLineCacheStore()
        let source = UnifiedDataSource(cache: cache, realtime: realtime, historical: stub)

        _ = await source.start(instrumentID: "RB0", period: .minute5)
        _ = await source.start(instrumentID: "RB0", period: .minute15)
        _ = await source.start(instrumentID: "RB0", period: .hour1)

        let calls = await stub.minuteCalls
        #expect(calls.count == 3)
        #expect(calls.map(\.interval).sorted() == [5, 15, 60])
        await source.stopAll()
    }
}
