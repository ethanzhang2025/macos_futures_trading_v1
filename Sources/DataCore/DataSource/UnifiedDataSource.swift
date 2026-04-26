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
    private let realtime: any MarketDataProvider
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
    /// WP-44c · 每个 instrumentID 在 realtime 上的订阅 token（首次订阅时记录，cleanup 时精确退订）
    private var realtimeTokens: [String: SubscriptionToken] = [:]

    // MARK: - 初始化

    /// - Parameters:
    ///   - cache: K 线本地缓存
    ///   - realtime: 实时行情 provider
    ///     - Production：`SinaMarketDataProvider`（WP-31a 起生效）+ `SinaPollingDriver` 驱动
    ///     - Mock / 测试：`SimulatedMarketDataProvider`（WP-21a 已交付）/ `MockMarketDataProvider`
    ///     - Stage B：`CTPMarketDataProvider`（WP-220 真 CTP 接入）
    ///   - cacheMaxBars: 缓存上限（每 instrumentID + period）；0 = 不限
    public init(
        cache: KLineCacheStore,
        realtime: any MarketDataProvider,
        cacheMaxBars: Int = 1000
    ) {
        self.cache = cache
        self.realtime = realtime
        self.cacheMaxBars = cacheMaxBars
    }

    // MARK: - 公开 API

    /// 启动订阅 · 立即 emit cache snapshot，然后是实时 K 线增量
    /// - Note: 同一 (instrumentID, period) 重复 start 会替换之前的订阅（旧 stream 终止）
    /// - WP-44b: 同 instrumentID 不同 period 可同时订阅（各自一条 stream + 独立 KLineBuilder）；
    ///   底层 realtime provider 按 instrumentID 仅订阅一次，handleTick 内部 dispatch 给所有匹配 period
    public func start(instrumentID: String, period: KLinePeriod) async -> AsyncStream<DataSourceUpdate> {
        let key = Key(instrumentID: instrumentID, period: period)

        // 替换已存在的订阅（避免双订阅 + 资源泄漏）
        await cleanup(key: key)

        // 1. 创建 stream
        let (stream, continuation) = AsyncStream<DataSourceUpdate>.makeStream()

        // 2. 加载缓存快照（失败静默 → 空数组，不阻断订阅）
        let cached = (try? await cache.load(instrumentID: instrumentID, period: period)) ?? []
        continuation.yield(.snapshot(cached))

        // 3. 检查此 instrumentID 是否已经在 realtime 订阅中（决定是否注册 handler）
        let isFirstSubscriptionForInstrument = !subscriptions.keys.contains { $0.instrumentID == instrumentID }

        // 4. 注册订阅状态
        let builder = KLineBuilder(instrumentID: instrumentID, period: period)
        subscriptions[key] = SubscriptionState(builder: builder, continuation: continuation)

        // 5. stream 终止时自动 cleanup（caller 不必显式 stop）
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cleanup(key: key) }
        }

        // 6. 仅当此 instrumentID 是首次订阅时注册 realtime handler
        //    后续同 instrumentID 的其他 period 共享此 handler（避免 MarketDataProvider 字典覆盖）
        // WP-44c · 保存 token 以便 cleanup 精确退订（不影响同合约其他模块的 handler）
        if isFirstSubscriptionForInstrument {
            let token = await realtime.subscribe(instrumentID) { [weak self] tick in
                Task { await self?.handleTick(tick) }
            }
            realtimeTokens[instrumentID] = token
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

    /// WP-44b: 按 tick.instrumentID 找出所有匹配 keys（多 period 各处理一次）
    private func handleTick(_ tick: Tick) async {
        // 拷贝快照：handleTick 内可能 cleanup（例如某 period 的 builder 触发 stream 关闭）
        let matchingKeys = subscriptions.keys.filter { $0.instrumentID == tick.instrumentID }
        for key in matchingKeys {
            guard let sub = subscriptions[key] else { continue }
            guard let completed = sub.builder.onTick(tick) else { continue }

            sub.continuation.yield(.completedBar(completed))

            // 增量持久化（失败静默：缓存层非关键路径，不影响实时流）
            try? await cache.append(
                [completed],
                instrumentID: key.instrumentID,
                period: key.period,
                maxBars: cacheMaxBars
            )
        }
    }

    private func cleanup(key: Key) async {
        guard let sub = subscriptions.removeValue(forKey: key) else { return }
        sub.continuation.finish()

        // 若该 instrumentID 已无任何 period 订阅，按 token 精确退订上游 realtime
        // WP-44c · 不再调 unsubscribe(_:) 清空整个 bucket（避免误清同合约其他模块的 handler）
        let stillSubscribed = subscriptions.keys.contains { $0.instrumentID == key.instrumentID }
        if !stillSubscribed, let token = realtimeTokens.removeValue(forKey: key.instrumentID) {
            await realtime.unsubscribe(key.instrumentID, token: token)
        }
    }
}
