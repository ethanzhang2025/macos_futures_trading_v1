// v17.39 D5 · 公式回测历史记录（Codable）
//
// 用途：
// - BacktestWindow 跑完回测后由用户手动保存（💾 按钮）
// - ReviewWindow 月报生成时按 [start, end) 区间挑当月条目附 annex
// - 跨平台 Codable（Linux 测试可覆盖）· Store 在 MainApp（macOS UserDefaults）

import Foundation

/// 单次回测的可持久化摘要（不含完整 equity 曲线 · 仅指标 · 月报够用）
public struct BacktestHistoryEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let signalLineName: String
    public let trajectoryRaw: String     // mock 标的轨迹 raw（randomWalk/up/down/sideways）
    public let barCount: Int
    public let initialEquity: Decimal
    public let endingPnL: Decimal
    public let maxDrawdown: Decimal
    public let sharpe: Double
    public let winRate: Double
    public let expectancy: Decimal
    public let tradeCount: Int

    public init(id: UUID, createdAt: Date, signalLineName: String,
                trajectoryRaw: String, barCount: Int, initialEquity: Decimal,
                endingPnL: Decimal, maxDrawdown: Decimal, sharpe: Double,
                winRate: Double, expectancy: Decimal, tradeCount: Int) {
        self.id = id
        self.createdAt = createdAt
        self.signalLineName = signalLineName
        self.trajectoryRaw = trajectoryRaw
        self.barCount = barCount
        self.initialEquity = initialEquity
        self.endingPnL = endingPnL
        self.maxDrawdown = maxDrawdown
        self.sharpe = sharpe
        self.winRate = winRate
        self.expectancy = expectancy
        self.tradeCount = tradeCount
    }

    /// 月报展示用的简短日期标签（MM-dd HH:mm · Asia/Shanghai）
    public static func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

/// 历史集合（顶层 Codable container · UserDefaults JSON 持久化）
public struct BacktestHistoryLog: Codable, Sendable, Equatable {
    public var entries: [BacktestHistoryEntry]
    public init(entries: [BacktestHistoryEntry] = []) {
        self.entries = entries
    }

    /// 区间筛选 [start, end)（Asia/Shanghai 时区由调用方处理）· 按 createdAt 降序
    public func entries(in range: Range<Date>) -> [BacktestHistoryEntry] {
        entries
            .filter { range.contains($0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
