// WP-21a 子模块 4 · 统一数据源 Facade
// 组装 KLineCacheStore + MarketDataProvider + (v2) HistoricalKLineProvider + KLineBuilder，提供单一入口
//
// 工作流：
//   1. start(instrumentID:period:) → AsyncStream<DataSourceUpdate>
//      a. 立即从 cache 加载（v1）+ 历史合并去重（v2 · 若注入了 historical provider）→ yield .snapshot(merged)
//      b. 订阅实时 Tick → KLineBuilder 合成 → yield .completedBar(K)
//      c. 完成的 K 线增量 append 到 cache（断电恢复友好）
//   2. stop / stopAll：取消订阅 + 清理 builder + 关闭 stream
//
// v2 历史合并（本次新增）：
//   - 注入 HistoricalKLineProvider（可选 · 默认 nil = 行为同 v1 仅 cache）
//   - start 时拉历史 K + 与 cache 合并去重（cache 优先 · 经 KLineBuilder 严格合成）
//   - fetch 失败静默回退到 cache（不阻断订阅启动）
//   - 仅支持 KLinePeriod ∈ {minute5, minute15, hour1} + daily（Sina 历史 K 提供的周期）
//
// 仍不做：
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
    /// v2 · 可选历史 K 线 provider（注入 → start 时合并；nil → 行为同 v1）
    private let historical: (any HistoricalKLineProvider)?
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
    ///   - historical: v2 历史 K 线 provider（可选 · nil = 行为同 v1 · 仅 cache 启动 snapshot）
    ///     - Production：`SinaMarketData`（已通过 SinaMarketData+Provider 适配）
    ///     - Stage B：`CTPHistoricalProvider`
    ///   - cacheMaxBars: 缓存上限（每 instrumentID + period）；0 = 不限
    public init(
        cache: KLineCacheStore,
        realtime: any MarketDataProvider,
        historical: (any HistoricalKLineProvider)? = nil,
        cacheMaxBars: Int = 1000
    ) {
        self.cache = cache
        self.realtime = realtime
        self.historical = historical
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
        // v2 · 历史合并：注入了 historical provider 时拉历史 K 与 cache 合并去重（cache 优先）
        let merged = await loadHistorySnapshot(instrumentID: instrumentID, period: period, cache: cached)
        continuation.yield(.snapshot(merged))

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

    // MARK: - v2 · 历史 K 线合并

    /// 拉历史 K 与 cache 合并去重（cache 优先）；historical 不可用 / 失败 / 周期不支持 → 静默回退到 cache
    private func loadHistorySnapshot(instrumentID: String, period: KLinePeriod, cache: [KLine]) async -> [KLine] {
        guard let historical, let interval = Self.intervalMinutes(for: period) else { return cache }
        guard let raw = try? await historical.historicalMinute(symbol: instrumentID, intervalMinutes: interval) else { return cache }
        let historicalKLines = raw.compactMap { Self.toKLine($0, instrumentID: instrumentID, period: period) }
        return Self.merge(historical: historicalKLines, cache: cache, maxBars: cacheMaxBars)
    }

    /// KLinePeriod → Sina 历史 K 周期分钟数（仅 5/15/60 三档；其他 period 返回 nil 回退到 cache）
    private static func intervalMinutes(for period: KLinePeriod) -> Int? {
        switch period {
        case .minute5:  return 5
        case .minute15: return 15
        case .hour1:    return 60
        default:        return nil
        }
    }

    /// HistoricalKLine → KLine（按 Asia/Shanghai 解析 date 字符串）
    private static func toKLine(_ h: HistoricalKLine, instrumentID: String, period: KLinePeriod) -> KLine? {
        guard let openTime = parseHistoricalDate(h.date) else { return nil }
        return KLine(
            instrumentID: instrumentID, period: period, openTime: openTime,
            open: h.open, high: h.high, low: h.low, close: h.close,
            volume: h.volume, openInterest: Decimal(h.openInterest), turnover: 0
        )
    }

    private static func parseHistoricalDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// 按 openTime 合并去重；cache 优先（cache 经 KLineBuilder 严格合成，比 historical 原始数据可靠）
    /// 最终按 openTime 升序 + 截取最近 maxBars 根（maxBars=0 不截）
    private static func merge(historical: [KLine], cache: [KLine], maxBars: Int) -> [KLine] {
        var byTime: [Date: KLine] = [:]
        for k in historical { byTime[k.openTime] = k }
        for k in cache { byTime[k.openTime] = k }  // cache 覆盖 historical
        let sorted = byTime.values.sorted { $0.openTime < $1.openTime }
        if maxBars > 0, sorted.count > maxBars {
            return Array(sorted.suffix(maxBars))
        }
        return sorted
    }
}
