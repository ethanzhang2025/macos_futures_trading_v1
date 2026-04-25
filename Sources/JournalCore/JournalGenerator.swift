// WP-53 模块 5 · 半自动日志初稿生成
// 策略：按 (instrumentID, 时间窗口) 聚合 trades → 生成 TradeJournal 初稿
//   - 同合约 + 时间窗口（默认 8 小时）内的 trades 归到一篇日志
//   - 自动 title（"rb2510 · 2026-04-25"）+ tradeIDs 关联 + reason 模板（统计开/平 + 盈亏估算占位）
//   - 用户接手后填情绪 / 偏差 / 教训
// A09 禁做项：单向引用（生成的 journal.tradeIDs 不修改 trades）

import Foundation

public enum JournalGenerator {

    /// 聚合规则配置
    public struct Configuration: Sendable {
        /// 同合约连续 trades 间隔超过 windowSeconds 视为新一段（默认 8 小时）
        public var windowSeconds: TimeInterval
        /// 时间分组所用日历时区
        public var timeZone: TimeZone

        public init(windowSeconds: TimeInterval = 8 * 3600, timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current) {
            self.windowSeconds = windowSeconds
            self.timeZone = timeZone
        }

        public static let `default` = Configuration()
    }

    /// 按 (instrumentID, 时间窗口) 聚合 trades 生成日志初稿
    /// - Parameters:
    ///   - trades: 已按 timestamp 升序的 trades（caller 责任）
    ///   - now: 生成时间戳（注入便于测试）
    /// - Returns: 日志初稿数组（用户编辑后调 store.saveJournal）
    public static func generateDrafts(
        from trades: [Trade],
        configuration: Configuration = .default,
        now: Date = Date()
    ) -> [TradeJournal] {
        guard !trades.isEmpty else { return [] }
        let sorted = trades.sorted { $0.timestamp < $1.timestamp }

        // 按 instrumentID 分桶
        var byInstrument: [String: [Trade]] = [:]
        for trade in sorted {
            byInstrument[trade.instrumentID, default: []].append(trade)
        }

        var drafts: [TradeJournal] = []
        for (instrumentID, group) in byInstrument {
            let segments = splitByWindow(group, windowSeconds: configuration.windowSeconds)
            for segment in segments {
                drafts.append(makeDraft(instrumentID: instrumentID, trades: segment, configuration: configuration, now: now))
            }
        }
        // 按时间倒序（最近的初稿在前，更符合 UI 列表预期）
        return drafts.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 私有

    /// 按时间窗口分段：相邻 trade 间隔 > windowSeconds 视为新段
    private static func splitByWindow(_ trades: [Trade], windowSeconds: TimeInterval) -> [[Trade]] {
        guard !trades.isEmpty else { return [] }
        var segments: [[Trade]] = []
        var current: [Trade] = [trades[0]]
        for index in 1..<trades.count {
            let prev = trades[index - 1].timestamp
            let curr = trades[index].timestamp
            if curr.timeIntervalSince(prev) > windowSeconds {
                segments.append(current)
                current = [trades[index]]
            } else {
                current.append(trades[index])
            }
        }
        segments.append(current)
        return segments
    }

    /// 构造单段的 draft journal
    private static func makeDraft(instrumentID: String, trades: [Trade], configuration: Configuration, now: Date) -> TradeJournal {
        let dateString = formatDate(trades.first?.timestamp ?? now, timeZone: configuration.timeZone)
        let title = "\(instrumentID) · \(dateString)"
        let tradeIDs = trades.map(\.id)

        let openCount = trades.filter { $0.offsetFlag == .open }.count
        let closeCount = trades.count - openCount
        let totalVolume = trades.reduce(0) { $0 + $1.volume }
        let totalCommission = trades.reduce(Decimal(0)) { $0 + $1.commission }

        let reason = """
        【系统初稿】合约 \(instrumentID)
        - 共 \(trades.count) 笔成交（开 \(openCount) / 平 \(closeCount)）
        - 总手数：\(totalVolume) · 总手续费：\(totalCommission)
        - 起止时间：\(formatDateTime(trades.first?.timestamp ?? now, timeZone: configuration.timeZone)) → \(formatDateTime(trades.last?.timestamp ?? now, timeZone: configuration.timeZone))

        请补充：交易理由 / 偏差 / 教训
        """

        // createdAt 用首笔成交时间（用户翻日志按交易日）
        let createdAt = trades.first?.timestamp ?? now
        return TradeJournal(
            tradeIDs: tradeIDs,
            title: title,
            reason: reason,
            createdAt: createdAt,
            updatedAt: now
        )
    }

    private static func formatDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func formatDateTime(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0)
    }
}
