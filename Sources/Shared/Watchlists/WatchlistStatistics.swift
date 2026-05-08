// 自选合约统计 HUD（v15.38 · 行情列表 V2）
//
// 输入：合约 ID 列表 + changePct closure
// 输出：聚合统计指标（涨跌家数 / 平均涨幅 / 涨停跌停数 / 极值合约名）
//
// 用途：分组视图 / 聚合视图顶部 stats HUD · trader 一眼看到当前视图情绪

import Foundation

public struct WatchlistStats: Sendable, Equatable {
    public let total: Int                          // 有 quote 数据的合约总数
    public let gainers: Int                        // 上涨家数（changePct > 0）
    public let losers: Int                         // 下跌家数（changePct < 0）
    public let unchanged: Int                      // 平盘（== 0）
    public let limitUpCount: Int                   // 涨停（≥ +9.5%）
    public let limitDownCount: Int                 // 跌停（≤ -9.5%）
    public let avgChangePct: Double                // 平均涨跌幅
    public let topGainerID: String?                // 涨幅最大合约 ID
    public let topGainerPct: Double                // 涨幅最大值
    public let topLoserID: String?                 // 跌幅最大合约 ID
    public let topLoserPct: Double                 // 跌幅最大值（带负号）

    public static let empty = WatchlistStats(
        total: 0, gainers: 0, losers: 0, unchanged: 0,
        limitUpCount: 0, limitDownCount: 0, avgChangePct: 0,
        topGainerID: nil, topGainerPct: 0,
        topLoserID: nil, topLoserPct: 0
    )

    /// 涨跌情绪偏向（-1 = 全跌 · 0 = 平衡 · +1 = 全涨）
    public var bullBias: Double {
        guard total > 0 else { return 0 }
        return Double(gainers - losers) / Double(total)
    }
}

public enum WatchlistStatsCalculator {

    /// 计算统计指标
    /// - Parameters:
    ///   - ids: 合约 ID 列表
    ///   - changePctForID: closure · 取合约涨跌幅 · nil 视为无数据（不计入 total）
    public static func compute(
        ids: [String],
        changePctForID: (String) -> Double?
    ) -> WatchlistStats {
        var gainers = 0
        var losers = 0
        var unchanged = 0
        var limitUp = 0
        var limitDown = 0
        var sumPct: Double = 0
        var topGainerID: String? = nil
        var topGainerPct: Double = -.infinity
        var topLoserID: String? = nil
        var topLoserPct: Double = .infinity
        var withData = 0

        for id in ids {
            guard let p = changePctForID(id) else { continue }
            withData += 1
            sumPct += p
            if p > 0 { gainers += 1 }
            else if p < 0 { losers += 1 }
            else { unchanged += 1 }
            if p >= 9.5 { limitUp += 1 }
            if p <= -9.5 { limitDown += 1 }
            if p > topGainerPct { topGainerPct = p; topGainerID = id }
            if p < topLoserPct { topLoserPct = p; topLoserID = id }
        }

        guard withData > 0 else { return .empty }
        return WatchlistStats(
            total: withData,
            gainers: gainers, losers: losers, unchanged: unchanged,
            limitUpCount: limitUp, limitDownCount: limitDown,
            avgChangePct: sumPct / Double(withData),
            topGainerID: topGainerID,
            topGainerPct: topGainerPct == -.infinity ? 0 : topGainerPct,
            topLoserID: topLoserID,
            topLoserPct: topLoserPct == .infinity ? 0 : topLoserPct
        )
    }
}
