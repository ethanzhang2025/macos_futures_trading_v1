// WP-53 模块 4 · 日志 + 成交持久化协议层
// A09 禁做项："日志内容不出 SQLCipher 加密边界"
//   → v1 数据模型层只定义协议 + 内存实现
//   → production SQLCipher 实现留 WP-19（数据持久化），但加密边界已在协议层划清
//   → 协议方法显式区分 trades（明文 OK，无敏感信息）vs journals（必须走 SQLCipher）
//
// 协议优先（与 KLineCacheStore / AlertHistoryStore 同形）：
// - InMemoryJournalStore：测试 / 临时
// - 后续 SQLCipherJournalStore（WP-19）：journals 字段必走加密列

import Foundation

/// 日志存储协议
///
/// 加密策略契约（实现方必须遵守）：
/// - Trade 明文存储（仅成交编号 + 价格 + 量，无个人敏感）
/// - TradeJournal 必走加密存储（含原因 / 情绪 / 教训等私密内容）
public protocol JournalStore: Sendable {

    // MARK: - Trade（明文）

    /// 保存 trades（已存在 id 覆盖）
    func saveTrades(_ trades: [Trade]) async throws

    /// 加载所有 trades（按 timestamp 升序）
    func loadAllTrades() async throws -> [Trade]

    /// 加载指定 instrumentID 的 trades
    func loadTrades(forInstrumentID instrumentID: String) async throws -> [Trade]

    /// 加载日期范围内的 trades [from, to)
    func loadTrades(from: Date, to: Date) async throws -> [Trade]

    /// 删除指定 trade
    func deleteTrade(id: UUID) async throws

    // MARK: - TradeJournal（加密）

    /// 保存 / 更新日志（已存在 id 覆盖；自动刷新 updatedAt 由 caller 决定）
    func saveJournal(_ journal: TradeJournal) async throws

    /// 加载所有日志（按 createdAt 降序）
    func loadAllJournals() async throws -> [TradeJournal]

    /// 加载指定 id 的日志
    func loadJournal(id: UUID) async throws -> TradeJournal?

    /// 按日期范围加载日志（按 createdAt）
    func loadJournals(from: Date, to: Date) async throws -> [TradeJournal]

    /// 按标签加载日志（含任一标签即匹配）
    func loadJournals(withAnyTag tags: Set<String>) async throws -> [TradeJournal]

    /// 删除日志（不级联删 trades，A09 禁做单向约束）
    func deleteJournal(id: UUID) async throws
}

// MARK: - 内存实现

public actor InMemoryJournalStore: JournalStore {

    private var trades: [UUID: Trade] = [:]
    private var journals: [UUID: TradeJournal] = [:]

    public init() {}

    // MARK: - Trade

    public func saveTrades(_ trades: [Trade]) async throws {
        for t in trades { self.trades[t.id] = t }
    }

    public func loadAllTrades() async throws -> [Trade] {
        trades.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func loadTrades(forInstrumentID instrumentID: String) async throws -> [Trade] {
        trades.values
            .filter { $0.instrumentID == instrumentID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func loadTrades(from: Date, to: Date) async throws -> [Trade] {
        trades.values
            .filter { $0.timestamp >= from && $0.timestamp < to }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteTrade(id: UUID) async throws {
        trades.removeValue(forKey: id)
    }

    // MARK: - Journal

    public func saveJournal(_ journal: TradeJournal) async throws {
        journals[journal.id] = journal
    }

    public func loadAllJournals() async throws -> [TradeJournal] {
        journals.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func loadJournal(id: UUID) async throws -> TradeJournal? {
        journals[id]
    }

    public func loadJournals(from: Date, to: Date) async throws -> [TradeJournal] {
        journals.values
            .filter { $0.createdAt >= from && $0.createdAt < to }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func loadJournals(withAnyTag tags: Set<String>) async throws -> [TradeJournal] {
        journals.values
            .filter { !$0.tags.isDisjoint(with: tags) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteJournal(id: UUID) async throws {
        journals.removeValue(forKey: id)
    }
}
