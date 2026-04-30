// WP-42 v13.2 · Drawing 持久化协议（按 instrumentID + period 隔离 · 与 AlertConfigStore 单聚合根模式不同）
// 设计取舍：
// - 每个 (instrumentID, period) 组合一组 [Drawing]（用户在不同合约/周期独立画线）
// - 整组 JSON 序列化（drawings 体量小 · v1 用户级别画线 < 50 条 / 组 · 全量 save 性能 OK）
// - InMemory + SQLite 多实现并存（StoreManager 注入）

import Foundation

/// Drawing 持久化错误
public enum DrawingStoreError: Error, Sendable, Equatable {
    case decodeFailed
    case encodeFailed
    case ioFailed(String)
}

/// Drawing 持久化协议
public protocol DrawingStore: Sendable {
    /// 加载某 (instrumentID, period) 的画线（不存在返回空数组 · 与 alerts/trades 不同 · 画线无 nil 语义）
    func load(instrumentID: String, period: KLinePeriod) async throws -> [Drawing]

    /// 整体保存（覆盖现有 · 同 (instrumentID, period) key）
    func save(_ drawings: [Drawing], instrumentID: String, period: KLinePeriod) async throws

    /// 清空指定 (instrumentID, period) 的画线
    func clear(instrumentID: String, period: KLinePeriod) async throws

    /// 清空所有画线（重置场景）
    func clearAll() async throws
}

/// 内存实现 · 测试 / 默认占位
public actor InMemoryDrawingStore: DrawingStore {
    private var stored: [String: [Drawing]] = [:]

    public init() {}

    public func load(instrumentID: String, period: KLinePeriod) async throws -> [Drawing] {
        stored[Self.key(instrumentID, period)] ?? []
    }

    public func save(_ drawings: [Drawing], instrumentID: String, period: KLinePeriod) async throws {
        stored[Self.key(instrumentID, period)] = drawings
    }

    public func clear(instrumentID: String, period: KLinePeriod) async throws {
        stored.removeValue(forKey: Self.key(instrumentID, period))
    }

    public func clearAll() async throws {
        stored.removeAll()
    }

    private static func key(_ instrumentID: String, _ period: KLinePeriod) -> String {
        "\(instrumentID).\(period.rawValue)"
    }
}
