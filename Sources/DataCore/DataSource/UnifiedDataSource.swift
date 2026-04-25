// WP-21a 子模块 4 · 统一数据源 Facade
// 组装 KLineCacheStore + MarketDataProvider + KLineBuilder，提供单一入口
//
// 工作流：
//   1. start(instrumentID:period:) → AsyncStream<DataSourceUpdate>
//      a. 立即从 cache 加载并 yield .snapshot(cached)（启动不闪烁）
//      b. 订阅实时 Tick → KLineBuilder 合成 → yield .completedBar(K)
//      c. 完成的 K 线增量 append 到 cache（断电恢复友好）
//   2. stop / stopAll：取消订阅 + 清理 builder + 关闭 stream
//
// v1 不做：
//   - HistoricalKLineProvider 历史合并（HistoricalKLine vs KLine 类型适配留 v2）
//   - 当前未完成 K 线推送（KLineBuilder 只在跨周期时返回完成 K 线）
//   - Tick 级 emit（上层若需要走 MarketDataProvider 直接订阅）

import Foundation
import Shared

/// UnifiedDataSource 推送给 caller 的更新事件
public enum DataSourceUpdate: Sendable, Equatable {
    /// 启动快照：从缓存加载的近期 K 线（按 openTime 升序，可能为空数组）
    case snapshot([KLine])
    /// KLineBuilder 完成一根新 K 线（已增量 append 到 cache）
    case completedBar(KLine)
}

/// 统一数据源 Facade
public actor UnifiedDataSource {

    // MARK: - 依赖（注入便于测试）

    private let cache: KLineCacheStore
    private let realtime: SimulatedMarketDataProvider
    private let cacheMaxBars: Int

    // MARK: - 内部订阅状态

    private struct Key: Hashable {
        let instrumentID: String
        let period: KLinePeriod
    }

    private final class SubscriptionState {
        let builder: KLineBuilder
        let continuation: AsyncStream<DataSourceUpdate>.Continuation
        init(builder: KLineBuilder, continuation: AsyncStream<DataSourceUpdate>.Continuation) {
            self.builder = builder
            self.continuation = continuation
        }
    }

    private var subscriptions: [Key: SubscriptionState] = [:]

    // MARK: - 初始化

    /// - Parameters:
    ///   - cache: K 线本地缓存
    ///   - realtime: 实时行情 provider（v1 用 SimulatedMarketDataProvider；
    ///     WP-21b Mac 真 CTP 实现后注入 CTPMarketDataProvider）
    ///   - cacheMaxBars: 缓存上限（每 instrumentID + period）；0 = 不限
    public init(
        cache: KLineCacheStore,
        realtime: SimulatedMarketDataProvider,
        cacheMaxBars: Int = 1000
    ) {
        self.cache = cache
        self.realtime = realtime
        self.cacheMaxBars = cacheMaxBars
    }

    // MARK: - 公开 API

    /// 启动订阅 · 立即 emit cache snapshot，然后是实时 K 线增量
    /// - Note: 同一 (instrumentID, period) 重复 start 会替换之前的订阅（旧 stream 终止）
    public func start(instrumentID: String, period: KLinePeriod) async -> AsyncStream<DataSourceUpdate> {
        let key = Key(instrumentID: instrumentID, period: period)

        // 替换已存在的订阅（避免双订阅 + 资源泄漏）
        await cleanup(key: key)

        // 1. 创建 stream
        let (stream, continuation) = AsyncStream<DataSourceUpdate>.makeStream()

        // 2. 加载缓存快照（失败静默 → 空数组，不阻断订阅）
        let cached = (try? await cache.load(instrumentID: instrumentID, period: period)) ?? []
        continuation.yield(.snapshot(cached))

        // 3. 注册订阅状态
        let builder = KLineBuilder(instrumentID: instrumentID, period: period)
        subscriptions[key] = SubscriptionState(builder: builder, continuation: continuation)

        // 4. stream 终止时自动 cleanup（caller 不必显式 stop）
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cleanup(key: key) }
        }

        // 5. 订阅实时 Tick
        await realtime.subscribe(instrumentID) { [weak self] tick in
            Task { await self?.handleTick(tick, key: key) }
        }

        return stream
    }

    /// 停止订阅
    public func stop(instrumentID: String, period: KLinePeriod) async {
        let key = Key(instrumentID: instrumentID, period: period)
        await cleanup(key: key)
    }

    /// 停止所有订阅
    public func stopAll() async {
        // 拷贝 keys 快照：cleanup 会修改 subscriptions，避免遍历突变集合
        for key in Array(subscriptions.keys) {
            await cleanup(key: key)
        }
    }

    /// 当前活跃订阅（测试 / 内省用）
    public func activeSubscriptions() -> [(instrumentID: String, period: KLinePeriod)] {
        subscriptions.keys.map { (instrumentID: $0.instrumentID, period: $0.period) }
    }

    // MARK: - 私有

    private func handleTick(_ tick: Tick, key: Key) async {
        guard let sub = subscriptions[key] else { return }
        guard let completed = sub.builder.onTick(tick) else { return }

        sub.continuation.yield(.completedBar(completed))

        // 增量持久化（失败静默：缓存层非关键路径，不影响实时流）
        try? await cache.append(
            [completed],
            instrumentID: key.instrumentID,
            period: key.period,
            maxBars: cacheMaxBars
        )
    }

    private func cleanup(key: Key) async {
        guard let sub = subscriptions.removeValue(forKey: key) else { return }
        sub.continuation.finish()

        // 若该 instrumentID 已无任何 period 订阅，取消上游 realtime 订阅
        let stillSubscribed = subscriptions.keys.contains { $0.instrumentID == key.instrumentID }
        if !stillSubscribed {
            await realtime.unsubscribe(key.instrumentID)
        }
    }
}
