// WP-120 · Banner 持久化协议 + 实现（v15.18）
//
// 设计取舍：
// - 协议 + 多实现：InMemory（测试）+ UserDefaults（v1 · 不需 SQLite）
// - 持久化的是"已 dismissed 的 banner id 集合" · 不持久化 banner 本身（banner 来自后端 source · 重启再拉）
// - id 集合用 Set<String> · O(1) 查 · 一次写入 / 多次查
// - cleanup 接口可选：按已知 banner 列表反差清理过期的 dismissed id（防 UserDefaults 无限增长）

import Foundation

public protocol BannerDismissalStore: Sendable {
    /// 添加一个 dismissed id
    func markDismissed(_ id: String) async
    /// 是否已 dismissed
    func isDismissed(_ id: String) async -> Bool
    /// 全部已 dismissed id
    func allDismissed() async -> Set<String>
    /// 清理：保留指定 id 集合 · 移除其余（防 UserDefaults 无限增长）
    func retain(only: Set<String>) async
}

/// 内存实现 · 测试 / 默认占位
public actor InMemoryBannerDismissalStore: BannerDismissalStore {
    private var dismissed: Set<String> = []
    public init() {}
    public func markDismissed(_ id: String) async { dismissed.insert(id) }
    public func isDismissed(_ id: String) async -> Bool { dismissed.contains(id) }
    public func allDismissed() async -> Set<String> { dismissed }
    public func retain(only: Set<String>) async { dismissed.formIntersection(only) }
}

/// UserDefaults 实现 · v1 默认（不依赖 SQLCipher · 启动时一次性 load）
/// actor 串行 + nonisolated(unsafe) defaults（UserDefaults 内部线程安全）
/// 注：UserDefaults 不是 Sendable · 调用方传入需 .standard 或在 main isolated 上下文中创建 instance
public actor UserDefaultsBannerDismissalStore: BannerDismissalStore {

    private static let key = "com.futures-terminal.banners.dismissed"
    nonisolated(unsafe) private let defaults: UserDefaults
    private var cache: Set<String>

    /// 默认 .standard · UserDefaults 在 actor 之外的可变性由 Apple 内部线程安全保证
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let arr = defaults.stringArray(forKey: Self.key) ?? []
        self.cache = Set(arr)
    }

    public func markDismissed(_ id: String) async {
        guard !cache.contains(id) else { return }
        cache.insert(id)
        defaults.set(Array(cache), forKey: Self.key)
    }

    public func isDismissed(_ id: String) async -> Bool {
        cache.contains(id)
    }

    public func allDismissed() async -> Set<String> {
        cache
    }

    public func retain(only ids: Set<String>) async {
        let filtered = cache.intersection(ids)
        guard filtered.count != cache.count else { return }
        cache = filtered
        defaults.set(Array(cache), forKey: Self.key)
    }
}
