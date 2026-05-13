// v17.187 · CrossLinkage 评估历史持久化（v17.172/175/178 闭环）
//
// 用途：
//   trader 关掉 App 后想看"昨天 RB 涨停时 HC 滞后了哪些次"
//   每次 evaluateAll 跑完 · matched / mismatched 都存入历史
//   按时间倒序展示 · 默认仅 1000 条上限（trader 不需无限历史 · 老数据自动滚出）
//
// 存储：
// - UserDefaults JSON（轻量 · 1000 条 << 1MB · 不必上 SQLite）
// - 失败静默（与 IndicatorFavoritesStore 一致）

import Foundation

/// 单条历史记录 · 比 CrossLinkageObservation 多一个时间戳
public struct CrossLinkageHistoryEntry: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let ruleID: String
    public let verdict: String           // matched / mismatched / notTriggered（rawValue）
    public let triggerInstrument: String
    public let watchInstrument: String
    public let triggerChangePct: Double
    public let watchChangePct: Double
    public let message: String

    public init(
        timestamp: Date,
        ruleID: String,
        verdict: String,
        triggerInstrument: String,
        watchInstrument: String,
        triggerChangePct: Double,
        watchChangePct: Double,
        message: String
    ) {
        self.timestamp = timestamp
        self.ruleID = ruleID
        self.verdict = verdict
        self.triggerInstrument = triggerInstrument
        self.watchInstrument = watchInstrument
        self.triggerChangePct = triggerChangePct
        self.watchChangePct = watchChangePct
        self.message = message
    }

    /// 从 CrossLinkageObservation 派生（caller 提供规则的 trigger/watch instrument）· 时间戳取 now
    public static func from(
        observation: CrossLinkageObservation,
        rule: CrossInstrumentLinkageRule,
        now: Date = Date()
    ) -> CrossLinkageHistoryEntry {
        CrossLinkageHistoryEntry(
            timestamp: now,
            ruleID: observation.ruleID,
            verdict: observation.verdict.rawValue,
            triggerInstrument: rule.triggerInstrument,
            watchInstrument: rule.watchInstrument,
            triggerChangePct: observation.triggerChangePct,
            watchChangePct: observation.watchChangePct,
            message: observation.message
        )
    }
}

/// 历史集合 · 时间倒序 · 上限保护
public struct CrossLinkageObservationHistory: Sendable, Codable, Equatable {
    public var entries: [CrossLinkageHistoryEntry]
    public static let defaultMaxEntries = 1000

    public init(entries: [CrossLinkageHistoryEntry] = []) {
        self.entries = entries
    }

    public static let empty = CrossLinkageObservationHistory()

    /// 追加（自动按时间倒序排 · 超过上限自动 drop oldest）· caller 不必关心顺序
    public mutating func append(_ entry: CrossLinkageHistoryEntry, maxEntries: Int = defaultMaxEntries) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    /// 批量追加（evaluateAll 一次性结果）· 默认仅留 verdict != "notTriggered"（trader 不关心未触发）
    public mutating func appendBatch(
        observations: [CrossLinkageObservation],
        rules: [CrossInstrumentLinkageRule],
        now: Date = Date(),
        includeNotTriggered: Bool = false,
        maxEntries: Int = defaultMaxEntries
    ) {
        let ruleByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.ruleID, $0) })
        for obs in observations {
            if !includeNotTriggered, obs.verdict == .notTriggered { continue }
            guard let rule = ruleByID[obs.ruleID] else { continue }
            append(.from(observation: obs, rule: rule, now: now), maxEntries: maxEntries)
        }
    }

    public mutating func clear() {
        entries.removeAll()
    }
}

public enum CrossLinkageObservationHistoryStore {
    public static let key = "crossLinkageObservationHistory.v1"

    public static func load(defaults: UserDefaults = .standard) -> CrossLinkageObservationHistory? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CrossLinkageObservationHistory.self, from: data)
    }

    public static func save(_ history: CrossLinkageObservationHistory, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }
}
