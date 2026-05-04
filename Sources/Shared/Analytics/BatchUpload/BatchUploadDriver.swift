// WP-133b · 上报 driver（v15.18 · 客户端层闭环）
//
// 设计取舍（StageA-补遗 G2 §上报机制 + D2 §WP-133）：
// - 双阈值触发：每 N 分钟 OR 积累 M 条立即上报（默认 5min / 100 条）
// - poll 周期 = pollIntervalSec（默认 30s 短轮询）· 每次 tick 决定是否真上报
// - upload 失败：不 markUploaded · 下轮重试（同事件 id 自然 idempotent · 后端去重靠 (user_id, event_ts) 唯一约束）
// - now / sleep 全部注入 · actor 单测可控时间 + 取消后台 task 干净
// - 与 ReplayDriver 模式一致：actor 持 task · cancel 后 await 旧 task 防双 task（v15.16 hotfix #12 经验）

import Foundation

public actor BatchUploadDriver {

    // MARK: - 依赖（构造注入）

    private let store: any AnalyticsEventStore
    private let client: any BatchUploadClient

    /// 单次取批上限（同时也是 "M 条立即上报" 的数量阈值 · 默认 100）
    private let batchSize: Int
    /// 时间触发阈值（毫秒 · 默认 5min = 300_000）
    private let timeTriggerMs: Int64
    /// poll 周期（秒 · 默认 30）
    private let pollIntervalSec: UInt64

    private let now: @Sendable () -> Date
    private let sleep: @Sendable (UInt64) async throws -> Void

    // v15.18 · 失败回调（caller 监听 · 可用于 emit banner / 上报监控）
    /// (failureCount, batchSize, error) → Void
    public typealias FailureCallback = @Sendable (Int, Int, Error) async -> Void
    private let onFailure: FailureCallback?

    // MARK: - 状态

    private var pollTask: Task<Void, Never>?
    private var lastUploadAttemptMs: Int64 = 0

    // 内省统计（测试 / 监控用）
    private var attempts: Int = 0
    private var successes: Int = 0
    private var failures: Int = 0
    /// v15.18 · 连续失败次数（成功时清零 · onFailure 可决定 N 连败时降级）
    private var consecutiveFailures: Int = 0

    // MARK: - 初始化

    public init(
        store: any AnalyticsEventStore,
        client: any BatchUploadClient,
        batchSize: Int = 100,
        timeTriggerMs: Int64 = 5 * 60 * 1000,
        pollIntervalSec: UInt64 = 30,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
        onFailure: FailureCallback? = nil
    ) {
        self.store = store
        self.client = client
        self.batchSize = batchSize
        self.timeTriggerMs = timeTriggerMs
        self.pollIntervalSec = pollIntervalSec
        self.now = now
        self.sleep = sleep
        self.onFailure = onFailure
    }

    // MARK: - 生命周期

    /// 启动周期 poll · 已运行则先 cancel + await 旧 task 防双 task
    public func start() async {
        if let old = pollTask {
            old.cancel()
            await old.value
            pollTask = nil
        }
        pollTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// 停止 · cancel + await（确保副作用排空）
    public func stop() async {
        guard let task = pollTask else { return }
        pollTask = nil
        task.cancel()
        await task.value
    }

    /// 立即触发一次 tick（外部强制刷新 · 如 App 即将退出前）· 不绕过阈值（仍按 count / time 判断）
    public func tickNow() async {
        await tickOnce()
    }

    /// 强制 flush（绕阈值 · 取所有 pending 上报 · 用于优雅退出 / 测试）
    public func flushAll() async {
        await tickOnce(forceUpload: true)
    }

    // MARK: - 内部

    private func runLoop() async {
        while !Task.isCancelled {
            await tickOnce()
            do {
                try await sleep(pollIntervalSec * 1_000_000_000)
            } catch {
                break  // sleep 抛错（cancel）· 退出循环
            }
        }
    }

    /// 单次 tick · 双阈值判断 · 上报 + markUploaded · 失败不标记下轮重试
    private func tickOnce(forceUpload: Bool = false) async {
        let pending: [AnalyticsEvent]
        do {
            pending = try await store.queryPending(limit: batchSize)
        } catch {
            return  // store 查询失败静默 · 下轮重试
        }
        guard !pending.isEmpty else { return }

        let nowMs = AnalyticsEvent.nowMs(now())
        let timeTriggered = lastUploadAttemptMs == 0 || (nowMs - lastUploadAttemptMs) >= timeTriggerMs
        let countTriggered = pending.count >= batchSize
        guard forceUpload || timeTriggered || countTriggered else { return }

        attempts += 1
        lastUploadAttemptMs = nowMs
        do {
            try await client.upload(pending)
            try await store.markUploaded(ids: pending.map(\.id))
            successes += 1
            consecutiveFailures = 0
        } catch {
            failures += 1
            consecutiveFailures += 1
            // 不 markUploaded · 下轮 queryPending 仍返回这些事件 · 自然重试
            // v15.18 · 触发 onFailure callback 同步 await（保证测试可靠 · 调用方不应在 callback 内做长任务）
            if let cb = onFailure {
                await cb(consecutiveFailures, pending.count, error)
            }
        }
    }

    // MARK: - 内省

    public func snapshot() -> (attempts: Int, successes: Int, failures: Int, lastAttemptMs: Int64) {
        (attempts, successes, failures, lastUploadAttemptMs)
    }

    /// v15.18 · 当前连续失败次数（caller 决定降级阈值）
    public func consecutiveFailureCount() -> Int { consecutiveFailures }
}
