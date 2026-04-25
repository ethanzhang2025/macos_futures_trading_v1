// WP-23 模块 2 · Feature Flag 门控服务
// D2 §2 禁做项："不在业务层散落 if flag.xxx 判断，统一由门控服务读取"
//
// 优先级链（CompositeFlagStore 实现）：
//   远程 JSON > 本地 UserDefaults override > FeatureFlag.defaultValue
//
// 设计：
// - FeatureFlagStore 协议：读单 flag
// - InMemoryFlagStore：测试 / 临时
// - UserDefaultsFlagStore：本地 override（开发/调试 / 用户偏好）
// - RemoteJSONFlagStore：远程配置（注入 fetcher 闭包，纯函数测试友好）
// - CompositeFlagStore：组合优先级
// - FeatureFlagService actor：业务唯一入口

import Foundation

// MARK: - 协议

public protocol FeatureFlagStore: Sendable {
    /// 读取 flag 当前值（nil = 该 store 未配置该 flag，由优先级链 fallback）
    func value(for flag: FeatureFlag) async -> Bool?
}

// MARK: - 内存实现（测试 / 临时）

public actor InMemoryFlagStore: FeatureFlagStore {

    private var values: [FeatureFlag: Bool] = [:]

    public init(initial: [FeatureFlag: Bool] = [:]) {
        self.values = initial
    }

    public func value(for flag: FeatureFlag) async -> Bool? {
        values[flag]
    }

    /// 设置 flag 值（测试驱动）
    public func set(_ flag: FeatureFlag, to value: Bool?) {
        if let value { values[flag] = value } else { values.removeValue(forKey: flag) }
    }

    public func snapshot() -> [FeatureFlag: Bool] { values }
}

// MARK: - UserDefaults 实现（本地 override）

/// 本地 override · 用于开发调试 / 用户偏好持久化
/// key 命名：`featureFlag.<rawValue>`，避免与其他模块的 UserDefaults key 冲突
/// `@unchecked Sendable`：UserDefaults 内部线程安全（Apple 文档保证），但未声明 Sendable 需手动标记
public struct UserDefaultsFlagStore: FeatureFlagStore, @unchecked Sendable {

    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "featureFlag.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func value(for flag: FeatureFlag) async -> Bool? {
        let key = keyPrefix + flag.rawValue
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    /// 设置本地 override（nil = 清除）
    public func set(_ flag: FeatureFlag, to value: Bool?) {
        let key = keyPrefix + flag.rawValue
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

// MARK: - 远程 JSON 实现

/// 远程配置缓存 · fetcher 注入便于测试（不依赖真实 URLSession）
/// 远程 JSON 格式：`{"featureFlags": {"subscription.paywall": true, ...}}`
public actor RemoteJSONFlagStore: FeatureFlagStore {

    /// 抓取器闭包：返回最新 flag 字典；抛错则保持现有缓存
    public typealias Fetcher = @Sendable () async throws -> [String: Bool]

    private let fetcher: Fetcher
    private var cachedValues: [String: Bool] = [:]
    private var lastFetchedAt: Date?

    public init(fetcher: @escaping Fetcher) {
        self.fetcher = fetcher
    }

    public func value(for flag: FeatureFlag) async -> Bool? {
        cachedValues[flag.rawValue]
    }

    /// 主动刷新远程配置；失败保持原缓存
    /// - Returns: 是否刷新成功
    @discardableResult
    public func refresh(now: Date = Date()) async -> Bool {
        do {
            let fresh = try await fetcher()
            cachedValues = fresh
            lastFetchedAt = now
            return true
        } catch {
            return false
        }
    }

    public var lastFetched: Date? { lastFetchedAt }

    public func currentSnapshot() -> [String: Bool] { cachedValues }
}

// MARK: - 组合优先级 store

/// 远程优先 → 本地 override 兜底 → enum default 兜底
public struct CompositeFlagStore: FeatureFlagStore {

    private let stores: [FeatureFlagStore]

    /// stores 顺序代表优先级（越靠前越高）
    public init(stores: [FeatureFlagStore]) {
        self.stores = stores
    }

    public func value(for flag: FeatureFlag) async -> Bool? {
        for store in stores {
            if let value = await store.value(for: flag) {
                return value
            }
        }
        return nil
    }
}

// MARK: - 服务（业务唯一入口）

/// Feature Flag 统一查询服务 · D2 §2 禁做项落实
///
/// 业务层只调 `service.isEnabled(.subscriptionPaywall)`，
/// 不直接持有 store / 不读 UserDefaults / 不解析 JSON
public actor FeatureFlagService {

    private let store: FeatureFlagStore

    /// - Parameter store: 通常注入 CompositeFlagStore（远程 + 本地 + 默认 fallback 链）
    public init(store: FeatureFlagStore) {
        self.store = store
    }

    /// 默认装配 · 仅本地 + 默认值（无远程）
    public static func makeDefault() -> FeatureFlagService {
        let local = UserDefaultsFlagStore()
        let composite = CompositeFlagStore(stores: [local])
        return FeatureFlagService(store: composite)
    }

    /// 业务唯一查询入口 · 自动套用默认值兜底
    public func isEnabled(_ flag: FeatureFlag) async -> Bool {
        await store.value(for: flag) ?? flag.defaultValue
    }

    /// 批量查询（UI 设置面板一次性展示用）
    public func snapshot() async -> [FeatureFlag: Bool] {
        var result: [FeatureFlag: Bool] = [:]
        for flag in FeatureFlag.allCases {
            result[flag] = await isEnabled(flag)
        }
        return result
    }
}
