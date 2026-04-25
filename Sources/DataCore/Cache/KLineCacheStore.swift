// WP-21a · K 线本地缓存层 v1
// 设计目的：
// - 启动时优先从缓存恢复近期 N 根 K 线（让用户先看到图表，再增量接入实时流）
// - 实时与缓存切换不闪烁（UnifiedDataSource Facade 使用，留 WP-21a 子模块 4）
//
// 设计原则：
// - 协议优先（KLineCacheStore），便于多实现并存（JSON 文件 / 内存 / SQLite 留 WP-19）
// - actor 隔离并发安全（多任务并发 save/load）
// - 不上 LRU / 不上加密（K 线非敏感，复杂度留给 WP-19）
// - JSON 序列化精度说明：JSONEncoder 编码 Decimal 走 NSNumber 通道，对 K 线价格（≤ 4 位小数）
//   精度完全够用（Double 53-bit mantissa ≈ 15-17 显著位）；Tick 级金额计算不应使用本缓存

import Foundation
import Shared

// 注：KLine 的 Codable conformance 已在 Sources/Shared/Models/KLine.swift 声明（WP-21a 缓存层需要）
//     KLinePeriod 的 Codable 由 WP-55 WorkspaceTemplate.swift 提供

// MARK: - 协议

/// K 线本地缓存协议
public protocol KLineCacheStore: Sendable {

    /// 加载指定合约 + 周期的所有缓存 K 线（按 openTime 升序）
    /// - Returns: 空数组表示无缓存（不视为错误）
    func load(instrumentID: String, period: KLinePeriod) async throws -> [KLine]

    /// 全量替换指定合约 + 周期的缓存
    func save(_ klines: [KLine], instrumentID: String, period: KLinePeriod) async throws

    /// 追加新 K 线到缓存末尾（已存在 openTime 重复的 K 线会被覆盖）
    /// - Parameter maxBars: 缓存上限；超过则截尾保留最近 maxBars 根；0 表示不限
    func append(_ klines: [KLine], instrumentID: String, period: KLinePeriod, maxBars: Int) async throws

    /// 清除指定合约 + 周期的缓存
    func clear(instrumentID: String, period: KLinePeriod) async throws

    /// 清除全部缓存
    func clearAll() async throws
}

// MARK: - 内存实现（测试 / 临时场景 / 单元集成）

/// 内存 K 线缓存 actor 实现
/// 用途：单元测试、集成测试、不需要持久化的临时场景
public actor InMemoryKLineCacheStore: KLineCacheStore {

    private struct Key: Hashable {
        let instrumentID: String
        let period: KLinePeriod
    }

    private var storage: [Key: [KLine]] = [:]

    public init() {}

    public func load(instrumentID: String, period: KLinePeriod) async throws -> [KLine] {
        storage[Key(instrumentID: instrumentID, period: period)] ?? []
    }

    public func save(_ klines: [KLine], instrumentID: String, period: KLinePeriod) async throws {
        storage[Key(instrumentID: instrumentID, period: period)] = klines.sorted { $0.openTime < $1.openTime }
    }

    public func append(_ klines: [KLine], instrumentID: String, period: KLinePeriod, maxBars: Int) async throws {
        let key = Key(instrumentID: instrumentID, period: period)
        storage[key] = Self.merged(existing: storage[key] ?? [], incoming: klines, maxBars: maxBars)
    }

    public func clear(instrumentID: String, period: KLinePeriod) async throws {
        storage[Key(instrumentID: instrumentID, period: period)] = nil
    }

    public func clearAll() async throws {
        storage.removeAll()
    }

    /// 合并 + 去重 + 排序 + 截尾（incoming 同 openTime 优先覆盖 existing）
    /// - Parameter maxBars: 0 表示不限
    static func merged(existing: [KLine], incoming: [KLine], maxBars: Int) -> [KLine] {
        var byTime: [Date: KLine] = [:]
        for k in existing { byTime[k.openTime] = k }
        for k in incoming { byTime[k.openTime] = k }
        let sorted = byTime.values.sorted { $0.openTime < $1.openTime }
        guard maxBars > 0, sorted.count > maxBars else { return sorted }
        return Array(sorted.suffix(maxBars))
    }
}
