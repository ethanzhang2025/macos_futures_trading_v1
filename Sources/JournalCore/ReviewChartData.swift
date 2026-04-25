// WP-50 模块 2 · 复盘 8 张图的数据契约
// 8 图：MonthlyPnL / PnLDistribution / WinRateCurve / InstrumentMatrix /
//       HoldingDurationStats / MaxDrawdownCurve / ProfitLossRatio / SessionPnL
// 数据层只提供 struct，UI 层（Mac 切机时）负责绘图

import Foundation

// MARK: - 1. 月度盈亏

/// 单月聚合
public struct MonthlyPnLBucket: Sendable, Codable, Equatable, Hashable {
    public let year: Int
    public let month: Int
    public let realizedPnL: Decimal
    public let tradeCount: Int       // 闭合持仓数量

    public init(year: Int, month: Int, realizedPnL: Decimal, tradeCount: Int) {
        self.year = year
        self.month = month
        self.realizedPnL = realizedPnL
        self.tradeCount = tradeCount
    }
}

public struct MonthlyPnL: Sendable, Codable, Equatable {
    public let buckets: [MonthlyPnLBucket]   // 按 (year, month) 升序
    public let totalPnL: Decimal

    public init(buckets: [MonthlyPnLBucket], totalPnL: Decimal) {
        self.buckets = buckets
        self.totalPnL = totalPnL
    }
}

// MARK: - 2. 分布直方（单笔盈亏分桶）

public struct PnLDistributionBin: Sendable, Codable, Equatable, Hashable {
    /// 桶下界（含），上界由下个 bin 推导；最后一个 bin 上界为 .greatestFiniteMagnitude 隐含
    public let lowerBound: Decimal
    public let upperBound: Decimal
    public let count: Int

    public init(lowerBound: Decimal, upperBound: Decimal, count: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.count = count
    }
}

public struct PnLDistribution: Sendable, Codable, Equatable {
    public let bins: [PnLDistributionBin]
    public let binSize: Decimal
    public let positiveCount: Int   // 盈利笔数
    public let negativeCount: Int   // 亏损笔数

    public init(bins: [PnLDistributionBin], binSize: Decimal, positiveCount: Int, negativeCount: Int) {
        self.bins = bins
        self.binSize = binSize
        self.positiveCount = positiveCount
        self.negativeCount = negativeCount
    }
}

// MARK: - 3. 胜率曲线（按时间滚动）

public struct WinRatePoint: Sendable, Codable, Equatable, Hashable {
    public let timestamp: Date       // 第 N 笔闭合时间
    public let cumulativeWins: Int
    public let cumulativeTotal: Int
    /// 累计胜率 [0, 1]
    public let cumulativeWinRate: Double

    public init(timestamp: Date, cumulativeWins: Int, cumulativeTotal: Int, cumulativeWinRate: Double) {
        self.timestamp = timestamp
        self.cumulativeWins = cumulativeWins
        self.cumulativeTotal = cumulativeTotal
        self.cumulativeWinRate = cumulativeWinRate
    }
}

public struct WinRateCurve: Sendable, Codable, Equatable {
    public let points: [WinRatePoint]   // 按 closeTime 升序
    public let finalWinRate: Double

    public init(points: [WinRatePoint], finalWinRate: Double) {
        self.points = points
        self.finalWinRate = finalWinRate
    }
}

// MARK: - 4. 品种矩阵（按合约聚合）

public struct InstrumentMatrixCell: Sendable, Codable, Equatable, Hashable {
    public let instrumentID: String
    public let tradeCount: Int
    public let totalPnL: Decimal
    public let winCount: Int
    public let winRate: Double      // [0, 1]

    public init(instrumentID: String, tradeCount: Int, totalPnL: Decimal, winCount: Int, winRate: Double) {
        self.instrumentID = instrumentID
        self.tradeCount = tradeCount
        self.totalPnL = totalPnL
        self.winCount = winCount
        self.winRate = winRate
    }
}

public struct InstrumentMatrix: Sendable, Codable, Equatable {
    public let cells: [InstrumentMatrixCell]   // 按 totalPnL 降序

    public init(cells: [InstrumentMatrixCell]) {
        self.cells = cells
    }
}

// MARK: - 5. 持仓时间统计

public struct HoldingDurationStats: Sendable, Codable, Equatable {
    /// 总闭合持仓数（用于 sanity check）
    public let totalCount: Int
    /// 平均持仓秒数
    public let averageSeconds: TimeInterval
    /// 中位持仓秒数
    public let medianSeconds: TimeInterval
    /// 最短 / 最长（秒）
    public let minSeconds: TimeInterval
    public let maxSeconds: TimeInterval
    /// 按分桶的持仓时间分布（< 1m / 1-5m / 5-30m / 30m-1h / 1h-1d / > 1d）
    public let buckets: [HoldingDurationBucket]

    public init(totalCount: Int, averageSeconds: TimeInterval, medianSeconds: TimeInterval, minSeconds: TimeInterval, maxSeconds: TimeInterval, buckets: [HoldingDurationBucket]) {
        self.totalCount = totalCount
        self.averageSeconds = averageSeconds
        self.medianSeconds = medianSeconds
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.buckets = buckets
    }
}

public struct HoldingDurationBucket: Sendable, Codable, Equatable, Hashable {
    public let label: String          // "<1m" / "1-5m" / "5-30m" / ...
    public let lowerSeconds: TimeInterval
    public let upperSeconds: TimeInterval   // .infinity 表示 ">"
    public let count: Int

    public init(label: String, lowerSeconds: TimeInterval, upperSeconds: TimeInterval, count: Int) {
        self.label = label
        self.lowerSeconds = lowerSeconds
        self.upperSeconds = upperSeconds
        self.count = count
    }
}

// MARK: - 6. 最大回撤曲线（累计权益 + 最大回撤区间）

public struct EquityPoint: Sendable, Codable, Equatable, Hashable {
    public let timestamp: Date
    public let cumulativePnL: Decimal
    /// 截至此点的累计权益最高水位（用于 drawdown 渲染）
    public let highWaterMark: Decimal
    /// 当前与水位之差（绝对值；正数表示在回撤中）
    public let drawdown: Decimal

    public init(timestamp: Date, cumulativePnL: Decimal, highWaterMark: Decimal, drawdown: Decimal) {
        self.timestamp = timestamp
        self.cumulativePnL = cumulativePnL
        self.highWaterMark = highWaterMark
        self.drawdown = drawdown
    }
}

public struct MaxDrawdownCurve: Sendable, Codable, Equatable {
    public let points: [EquityPoint]
    public let maxDrawdown: Decimal           // 全期最大回撤（绝对值）
    public let maxDrawdownStart: Date?        // 回撤起点（高水位时间）
    public let maxDrawdownEnd: Date?          // 回撤底点

    public init(points: [EquityPoint], maxDrawdown: Decimal, maxDrawdownStart: Date?, maxDrawdownEnd: Date?) {
        self.points = points
        self.maxDrawdown = maxDrawdown
        self.maxDrawdownStart = maxDrawdownStart
        self.maxDrawdownEnd = maxDrawdownEnd
    }
}

// MARK: - 7. 盈亏比

public struct ProfitLossRatio: Sendable, Codable, Equatable {
    public let averageWin: Decimal       // 盈利笔的平均盈利
    public let averageLoss: Decimal      // 亏损笔的平均亏损（正数）
    public let ratio: Decimal            // averageWin / averageLoss；亏损为 0 时 = 0
    public let winCount: Int
    public let lossCount: Int

    public init(averageWin: Decimal, averageLoss: Decimal, ratio: Decimal, winCount: Int, lossCount: Int) {
        self.averageWin = averageWin
        self.averageLoss = averageLoss
        self.ratio = ratio
        self.winCount = winCount
        self.lossCount = lossCount
    }
}

// MARK: - 8. 时段分析

/// 交易时段（v1 简化为 4 段：早盘/午盘/夜盘/凌晨夜盘）
public enum TradingSlot: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case morning      // 09:00-11:30
    case afternoon    // 13:00-15:00
    case night        // 21:00-23:59
    case midnight     // 00:00-02:30
    case other        // 其他（含集合竞价/盘前）
}

public struct SessionPnLBucket: Sendable, Codable, Equatable, Hashable {
    public let slot: TradingSlot
    public let tradeCount: Int
    public let totalPnL: Decimal
    public let winCount: Int
    public let winRate: Double

    public init(slot: TradingSlot, tradeCount: Int, totalPnL: Decimal, winCount: Int, winRate: Double) {
        self.slot = slot
        self.tradeCount = tradeCount
        self.totalPnL = totalPnL
        self.winCount = winCount
        self.winRate = winRate
    }
}

public struct SessionPnL: Sendable, Codable, Equatable {
    public let buckets: [SessionPnLBucket]   // 按 TradingSlot.allCases 顺序

    public init(buckets: [SessionPnLBucket]) {
        self.buckets = buckets
    }
}
