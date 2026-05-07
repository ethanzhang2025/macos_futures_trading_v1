// SyncConflictLog · 冲突日志（WP-60 · batch002）
//
// 抽象 + 内存默认实现：
//   - 协议 ConflictLog · SQLite 实现留给后续接入 StoreCore
//   - InMemoryConflictLog 满足 SyncEngineDemo / Tests / Stage A 早期需求
//
// 内存版能力：
//   - cap 限定（FIFO 截断）
//   - 按 recordType 过滤
//   - 按时间窗 since 过滤
//   - 按 recordID 查询
//   - paginate（offset + limit）
//
// 为什么不用 SQLite：
//   - SQLite store 在 StoreCore（依赖链复杂 · 引入会让 SyncCore 变大）
//   - 冲突量极小（个位数/天）· 内存够用
//   - 后续若需要持久化 · 实现 ConflictLog 协议即可

import Foundation

public protocol ConflictLog: Sendable {
    func record(_ conflict: SyncConflict) async
    func recordAll(_ conflicts: [SyncConflict]) async
    func all() async -> [SyncConflict]
    func count() async -> Int
    func clear() async
}

/// 内存版冲突日志 · 默认实现
public actor InMemoryConflictLog: ConflictLog {
    private var entries: [SyncConflict] = []
    private let cap: Int

    public init(cap: Int = 1000) {
        self.cap = cap
    }

    // MARK: - ConflictLog

    public func record(_ conflict: SyncConflict) {
        entries.append(conflict)
        if entries.count > cap {
            entries.removeFirst(entries.count - cap)
        }
    }

    public func recordAll(_ conflicts: [SyncConflict]) {
        for c in conflicts { record(c) }
    }

    public func all() -> [SyncConflict] { entries }

    public func count() -> Int { entries.count }

    public func clear() { entries.removeAll() }

    // MARK: - 查询扩展

    /// 按 recordType 过滤 · 时间倒序
    public func filter(recordType: String) -> [SyncConflict] {
        entries.filter { $0.recordType == recordType }
            .sorted { $0.resolvedAt > $1.resolvedAt }
    }

    /// 自 since 之后的冲突 · 时间倒序
    public func since(_ date: Date) -> [SyncConflict] {
        entries.filter { $0.resolvedAt >= date }
            .sorted { $0.resolvedAt > $1.resolvedAt }
    }

    /// 同一 recordID 的所有冲突 · 时间倒序
    public func entries(for recordID: UUID) -> [SyncConflict] {
        entries.filter { $0.recordID == recordID }
            .sorted { $0.resolvedAt > $1.resolvedAt }
    }

    /// 分页（按 resolvedAt 倒序 · 最近优先）
    public func paginate(offset: Int, limit: Int) -> [SyncConflict] {
        guard limit > 0 else { return [] }
        let sorted = entries.sorted { $0.resolvedAt > $1.resolvedAt }
        guard offset < sorted.count else { return [] }
        let end = min(offset + limit, sorted.count)
        return Array(sorted[offset..<end])
    }
}
