// WP-133b · BatchUploadDriver + StubBatchUploadClient 测试（v15.18）
//
// 覆盖：
// - 双阈值（时间 / 数量）触发逻辑
// - upload 失败不 markUploaded（下轮重试）
// - flushAll 绕阈值强制
// - start/stop 生命周期 · 多次 start 不双 task
// - StubBatchUploadClient stats 计数 + mode 切换

import Testing
import Foundation
@testable import Shared

/// 测试用时间引用：Sendable + 锁保护 · 闭包内读 / 测试中写
private final class TimeRef: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ d: Date) { _value = d }
    var value: Date {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

@Suite("BatchUploadDriver · 阈值触发")
struct BatchUploadDriverThresholdTests {

    private func seedEvents(_ store: InMemoryAnalyticsEventStore, count: Int) async throws {
        for i in 0..<count {
            _ = try await store.append(AnalyticsEvent(
                userID: "u",
                deviceID: "d",
                eventName: .chartOpen,
                eventTimestampMs: Int64(i)
            ))
        }
    }

    @Test("首次 tick · lastAttempt==0 视为时间触发 · 立即上报全部")
    func firstTickFiresImmediately() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()
        try await seedEvents(store, count: 5)

        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 100, timeTriggerMs: 5 * 60 * 1000, pollIntervalSec: 30
        )
        await driver.tickNow()

        let snap = await driver.snapshot()
        #expect(snap.attempts == 1)
        #expect(snap.successes == 1)
        #expect(try await store.queryPending(limit: 0).count == 0)
    }

    @Test("数量触发 · pending >= batchSize 立即上报（即便距上次 < 时间阈值）")
    func countTriggerFires() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()
        try await seedEvents(store, count: 3)

        let timeRef = TimeRef(Date(timeIntervalSince1970: 1_700_000_000))
        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 3,           // 阈值降到 3
            timeTriggerMs: 5 * 60 * 1000,
            pollIntervalSec: 30,
            now: { timeRef.value }
        )
        await driver.tickNow()    // 第 1 次：时间触发（lastAttempt==0）
        var snap = await driver.snapshot()
        #expect(snap.successes == 1)

        // 再 seed 3 条 · 短时间内（10s 后）应被数量触发上报
        try await seedEvents(store, count: 3)
        timeRef.value = Date(timeIntervalSince1970: 1_700_000_010)
        await driver.tickNow()
        snap = await driver.snapshot()
        #expect(snap.successes == 2)   // 数量触发成功
    }

    @Test("双阈值都不达 · 跳过不上报")
    func neitherTriggerSkips() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()

        let timeRef = TimeRef(Date(timeIntervalSince1970: 1_700_000_000))
        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 100, timeTriggerMs: 5 * 60 * 1000, pollIntervalSec: 30,
            now: { timeRef.value }
        )
        // 先 tick 一次让 lastAttempt 落地（empty 不会真上报）
        try await seedEvents(store, count: 1)
        await driver.tickNow()        // 时间触发 · 1 条上报
        let snap1 = await driver.snapshot()
        #expect(snap1.successes == 1)

        // 仅 seed 5 条（< 100）· 时间也才走 60s
        try await seedEvents(store, count: 5)
        timeRef.value = Date(timeIntervalSince1970: 1_700_000_060)
        await driver.tickNow()
        let snap2 = await driver.snapshot()
        #expect(snap2.attempts == 1)  // 没有新的 attempt
        #expect(try await store.queryPending(limit: 0).count == 5)
    }
}

@Suite("BatchUploadDriver · 失败重试 + flushAll")
struct BatchUploadDriverRetryTests {

    @Test("upload 失败 · 不 markUploaded · 下轮重试")
    func failKeepsPendingForRetry() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient(mode: .alwaysFail("simulated"))
        _ = try await store.append(AnalyticsEvent(
            userID: "u", deviceID: "d", eventName: .appLaunch, eventTimestampMs: 1
        ))

        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 10, timeTriggerMs: 0, pollIntervalSec: 30   // 时间阈值 0 · 总是触发
        )
        await driver.tickNow()
        var snap = await driver.snapshot()
        #expect(snap.attempts == 1)
        #expect(snap.failures == 1)
        #expect(try await store.queryPending(limit: 0).count == 1)  // 仍 pending

        // 切回 success mode · 再 tick · 应成功 markUploaded
        await client.setMode(.success)
        await driver.tickNow()
        snap = await driver.snapshot()
        #expect(snap.successes == 1)
        #expect(try await store.queryPending(limit: 0).count == 0)
    }

    @Test("flushAll · 绕阈值 · 强制上报所有 pending")
    func flushAllBypassesThresholds() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()
        for _ in 0..<3 {
            _ = try await store.append(AnalyticsEvent(
                userID: "u", deviceID: "d", eventName: .chartOpen, eventTimestampMs: 1
            ))
        }

        let timeRef = TimeRef(Date(timeIntervalSince1970: 1_700_000_000))
        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 100, timeTriggerMs: 5 * 60 * 1000, pollIntervalSec: 30,
            now: { timeRef.value }
        )
        // 先正常 tick 一次（时间触发）· 全清
        await driver.tickNow()
        #expect(try await store.queryPending(limit: 0).count == 0)

        // seed 2 条 · 时间未到 · 数量未到 · tickNow 不会上报
        for _ in 0..<2 {
            _ = try await store.append(AnalyticsEvent(
                userID: "u", deviceID: "d", eventName: .chartOpen, eventTimestampMs: 1
            ))
        }
        timeRef.value = Date(timeIntervalSince1970: 1_700_000_060)
        await driver.tickNow()
        #expect(try await store.queryPending(limit: 0).count == 2)

        // flushAll 绕阈值
        await driver.flushAll()
        #expect(try await store.queryPending(limit: 0).count == 0)
    }
}

@Suite("BatchUploadDriver · onFailure callback（v15.18）")
struct BatchUploadDriverFailureCallbackTests {

    /// 失败计数 actor（@Sendable closure 共享状态）
    private actor FailureCounter {
        var count: Int = 0
        var lastConsecutive: Int = 0
        func record(consecutive: Int) {
            count += 1
            lastConsecutive = consecutive
        }
    }

    @Test("upload 失败 · onFailure 被调用 · 携带连续失败次数")
    func failureCallbackInvoked() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient(mode: .alwaysFail("test"))
        _ = try await store.append(AnalyticsEvent(
            userID: "u", deviceID: "d", eventName: .appLaunch, eventTimestampMs: 1
        ))

        let counter = FailureCounter()
        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 10, timeTriggerMs: 0, pollIntervalSec: 30,
            onFailure: { consec, _, _ in
                await counter.record(consecutive: consec)
            }
        )
        await driver.tickNow()
        // 给 callback Task 执行机会
        try? await Task.sleep(nanoseconds: 50_000_000)
        let cnt = await counter.count
        let lastConsec = await counter.lastConsecutive
        #expect(cnt == 1)
        #expect(lastConsec == 1)
        #expect(await driver.consecutiveFailureCount() == 1)
    }

    @Test("连续 3 次失败 · onFailure 累计到 3 · 成功一次后清零")
    func consecutiveFailuresThenReset() async throws {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient(mode: .alwaysFail("test"))
        _ = try await store.append(AnalyticsEvent(
            userID: "u", deviceID: "d", eventName: .appLaunch, eventTimestampMs: 1
        ))

        let counter = FailureCounter()
        let driver = BatchUploadDriver(
            store: store, client: client,
            batchSize: 10, timeTriggerMs: 0, pollIntervalSec: 30,
            onFailure: { consec, _, _ in await counter.record(consecutive: consec) }
        )
        for _ in 0..<3 { await driver.tickNow() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await counter.lastConsecutive == 3)
        #expect(await driver.consecutiveFailureCount() == 3)

        // 切回 success · 一次成功后 consecutive 清零
        await client.setMode(.success)
        await driver.tickNow()
        #expect(await driver.consecutiveFailureCount() == 0)
    }
}

@Suite("BatchUploadDriver · 生命周期")
struct BatchUploadDriverLifecycleTests {

    @Test("多次 start · 旧 task cancel + await · 防双 task")
    func reentrantStartCancelsOld() async {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()
        let driver = BatchUploadDriver(
            store: store, client: client,
            pollIntervalSec: 1   // 短轮询便于触发
        )
        await driver.start()
        await driver.start()      // 第二次：应 cancel 旧 + 启新 · 不抛
        await driver.stop()
    }

    @Test("stop 后 task 已退出 · 再 stop 幂等")
    func stopIdempotent() async {
        let store = InMemoryAnalyticsEventStore()
        let client = StubBatchUploadClient()
        let driver = BatchUploadDriver(store: store, client: client)
        await driver.stop()       // 未 start 也允许
        await driver.start()
        await driver.stop()
        await driver.stop()       // 重复 stop 幂等
    }
}

@Suite("StubBatchUploadClient · stats + mode")
struct StubBatchUploadClientTests {

    @Test("默认 success mode · upload 累加 calls + eventsReceived")
    func successAccumulates() async throws {
        let client = StubBatchUploadClient()
        try await client.upload([
            AnalyticsEvent(userID: "u", deviceID: "d", eventName: .appLaunch, eventTimestampMs: 1),
            AnalyticsEvent(userID: "u", deviceID: "d", eventName: .chartOpen, eventTimestampMs: 2)
        ])
        try await client.upload([
            AnalyticsEvent(userID: "u", deviceID: "d", eventName: .alertTrigger, eventTimestampMs: 3)
        ])
        let stats = await client.stats()
        #expect(stats.calls == 2)
        #expect(stats.eventsReceived == 3)
    }

    @Test("alwaysFail mode · upload 抛 networkFailed · 仍累加 stats")
    func failModeStillCounts() async throws {
        let client = StubBatchUploadClient(mode: .alwaysFail("test"))
        await #expect(throws: BatchUploadError.self) {
            try await client.upload([
                AnalyticsEvent(userID: "u", deviceID: "d", eventName: .appLaunch, eventTimestampMs: 1)
            ])
        }
        let stats = await client.stats()
        #expect(stats.calls == 1)
        #expect(stats.eventsReceived == 1)
    }
}
