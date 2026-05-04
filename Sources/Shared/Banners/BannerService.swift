// WP-120 · Banner 服务 actor（v15.18）
//
// 设计取舍：
// - 高层 API · 隔离 store / source · UI 调用单一入口
// - refresh：从 source 拉 → 与 dismissed 集合合并 → 返回应展示列表（按 createdAt 倒序）
// - dismiss：写入 dismissed store + 缓存最新 active 列表
// - now 注入便于测试过期判断
// - 失败静默：source 抛错时返回缓存（不阻塞 UI）

import Foundation

public actor BannerService {

    private let store: any BannerDismissalStore
    private let source: any BannerSource
    private let now: @Sendable () -> Date

    /// 最近一次 refresh 后的应展示列表（已过滤 dismissed + 过期）· dismiss 后重算
    private var activeCache: [Banner] = []
    /// 最近一次 source 拉取的全集（用于 dismiss 时不需重新 fetch）
    private var lastFetched: [Banner] = []

    public init(
        store: any BannerDismissalStore,
        source: any BannerSource,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.source = source
        self.now = now
    }

    /// 从 source 拉取最新 → 过滤 dismissed + 过期 → 更新 active 缓存 → 返回
    /// 失败静默：source 抛错返回 activeCache（不阻塞 UI）
    @discardableResult
    public func refresh() async -> [Banner] {
        do {
            let fetched = try await source.fetchLatest()
            lastFetched = fetched
            await rebuildActive()
        } catch {
            // 静默 fallback · 上次 active 仍可用
        }
        return activeCache
    }

    /// 用户 dismiss 一条 banner · 持久化 + 重算 active
    public func dismiss(_ id: String) async {
        await store.markDismissed(id)
        await rebuildActive()
    }

    /// 当前应展示的 active 列表（不触发 refresh）
    public func active() async -> [Banner] {
        activeCache
    }

    /// 内省（测试用）
    public func dismissedCount() async -> Int {
        await store.allDismissed().count
    }

    // MARK: - 内部

    private func rebuildActive() async {
        let dismissed = await store.allDismissed()
        let nowMs = AnalyticsEvent.nowMs(now())
        activeCache = lastFetched
            .filter { !dismissed.contains($0.id) && !$0.isExpired(nowMs: nowMs) }
            .sorted { $0.createdAtMs > $1.createdAtMs }   // 最新在前
    }
}
