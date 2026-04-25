// WP-133a · 埋点事件持久化协议
//
// 设计取舍：
// - 协议先行 + 多实现（InMemory / JSONFile · 未来 SQLCipher 接同协议）
// - 客户端职责：写入 / 查询未上报 / 标记已上报 / 清理老数据
// - 后端 WAPU 查询是 PostgreSQL 的事，不在本协议范围
//
// 与 KLineCacheStore（WP-21a-3）模式一致：协议 + InMemory + JSONFile 双实现

import Foundation

/// 埋点事件持久化错误
public enum AnalyticsEventStoreError: Error, CustomStringConvertible, Equatable {
    case ioFailed(String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .ioFailed(let msg):     return "持久化 IO 失败: \(msg)"
        case .decodeFailed(let msg): return "持久化反序列化失败: \(msg)"
        }
    }
}

/// 埋点事件持久化协议
public protocol AnalyticsEventStore: Sendable {
    /// 追加一条事件 · 返回赋值后的 id
    @discardableResult
    func append(_ event: AnalyticsEvent) async throws -> Int64

    /// 批量追加 · 返回各事件赋值后的 id（顺序与入参一致）
    @discardableResult
    func appendBatch(_ events: [AnalyticsEvent]) async throws -> [Int64]

    /// 查询所有未上报事件（uploaded=false）按时间升序
    /// - Parameter limit: 最大条数（防 OOM；默认 0 = 不限）
    func queryPending(limit: Int) async throws -> [AnalyticsEvent]

    /// 标记一批事件为已上报
    func markUploaded(ids: [Int64]) async throws

    /// 清理 N 毫秒之前的已上报事件（防客户端无限增长）
    /// - Parameter beforeTimestampMs: 截止时间戳（毫秒）；只清理 uploaded=true 且 eventTimestampMs < 该值
    /// - Returns: 实际清理条数
    @discardableResult
    func cleanupUploaded(beforeTimestampMs: Int64) async throws -> Int

    /// 当前总条数（含已上报 + 未上报；测试 / 调试用）
    func count() async throws -> Int
}
