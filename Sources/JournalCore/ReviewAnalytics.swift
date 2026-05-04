// WP-50 模块 3 · 复盘 8 张图聚合算法
// 输入：[Trade] + multipliers → PositionMatcher → [ClosedPosition] → 8 个聚合方法
// 时区：Asia/Shanghai（与 TradingCalendar 对齐）
// 注入：当前时区 + 当前 Calendar 注入便于测试

import Foundation
import Shared

public enum ReviewAnalytics {

    /// 默认时区（A 股期货）
    public static let defaultTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    // MARK: - 1. 月度盈亏

    public static func monthlyPnL(
        from positions: [ClosedPosition],
        timeZone: TimeZone = defaultTimeZone
    ) -> MonthlyPnL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        struct Key: Hashable { let year: Int; let month: Int }
        var byMonth: [Key: (pnl: Decimal, count: Int)] = [:]

        for position in positions {
            let c = calendar.dateComponents([.year, .month], from: position.closeTime)
            // year/month 在 Asia/Shanghai 时区下永远非 nil；?? 0 仅为编译器满意
            let key = Key(year: c.year ?? 0, month: c.month ?? 0)
            var pair = byMonth[key] ?? (Decimal(0), 0)
            pair.pnl += position.realizedPnL
            pair.count += 1
            byMonth[key] = pair
        }
        let buckets = byMonth
            .sorted { ($0.key.year, $0.key.month) < ($1.key.year, $1.key.month) }
            .map { (k, v) in MonthlyPnLBucket(year: k.year, month: k.month, realizedPnL: v.pnl, tradeCount: v.count) }
        let total = positions.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        return MonthlyPnL(buckets: buckets, totalPnL: total)
    }

    // MARK: - 1b. 季度盈亏（v15.17 · 月度聚合到季度 · D2 §2 月度/季度总结自动生成）

    public static func quarterlyPnL(
        from positions: [ClosedPosition],
        timeZone: TimeZone = defaultTimeZone
    ) -> QuarterlyPnL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        struct Key: Hashable { let year: Int; let quarter: Int }
        var byQuarter: [Key: (pnl: Decimal, count: Int)] = [:]

        for position in positions {
            let c = calendar.dateComponents([.year, .month], from: position.closeTime)
            let year = c.year ?? 0
            let month = c.month ?? 1
            let quarter = (month - 1) / 3 + 1   // 1~3 → Q1, 4~6 → Q2, ...
            let key = Key(year: year, quarter: quarter)
            var pair = byQuarter[key] ?? (Decimal(0), 0)
            pair.pnl += position.realizedPnL
            pair.count += 1
            byQuarter[key] = pair
        }
        let buckets = byQuarter
            .sorted { ($0.key.year, $0.key.quarter) < ($1.key.year, $1.key.quarter) }
            .map { (k, v) in QuarterlyPnLBucket(year: k.year, quarter: k.quarter, realizedPnL: v.pnl, tradeCount: v.count) }
        let total = positions.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        return QuarterlyPnL(buckets: buckets, totalPnL: total)
    }

    // MARK: - 1c. 年度盈亏（v15.17 · 长周期总结 · 日历年聚合）

    public static func yearlyPnL(
        from positions: [ClosedPosition],
        timeZone: TimeZone = defaultTimeZone
    ) -> YearlyPnL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var byYear: [Int: (pnl: Decimal, count: Int)] = [:]

        for position in positions {
            let year = calendar.component(.year, from: position.closeTime)
            var pair = byYear[year] ?? (Decimal(0), 0)
            pair.pnl += position.realizedPnL
            pair.count += 1
            byYear[year] = pair
        }
        let buckets = byYear
            .sorted { $0.key < $1.key }
            .map { (k, v) in YearlyPnLBucket(year: k, realizedPnL: v.pnl, tradeCount: v.count) }
        let total = positions.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        return YearlyPnL(buckets: buckets, totalPnL: total)
    }

    // MARK: - 2. 分布直方

    /// - Parameter binSize: 单桶宽度（如 100 = 每桶 100 元盈亏区间）
    public static func pnlDistribution(
        from positions: [ClosedPosition],
        binSize: Decimal
    ) -> PnLDistribution {
        precondition(binSize > 0, "binSize 必须 > 0")
        guard !positions.isEmpty else {
            return PnLDistribution(bins: [], binSize: binSize, positiveCount: 0, negativeCount: 0)
        }

        // 按 binSize 分桶（floor 向下取整）+ 同遍统计正负笔数
        var bucketCounts: [Int: Int] = [:]   // 桶索引 → 计数
        var positive = 0
        var negative = 0
        for position in positions {
            let bucketIndex = Self.bucketIndex(for: position.realizedPnL, binSize: binSize)
            bucketCounts[bucketIndex, default: 0] += 1
            if position.realizedPnL > 0 { positive += 1 }
            else if position.realizedPnL < 0 { negative += 1 }
        }
        let bins = bucketCounts.keys.sorted().map { idx -> PnLDistributionBin in
            let lower = Decimal(idx) * binSize
            return PnLDistributionBin(lowerBound: lower, upperBound: lower + binSize, count: bucketCounts[idx, default: 0])
        }
        return PnLDistribution(bins: bins, binSize: binSize, positiveCount: positive, negativeCount: negative)
    }

    private static func bucketIndex(for value: Decimal, binSize: Decimal) -> Int {
        var quotient = Decimal()
        var divided = value / binSize
        // floor：负数向下、正数向下
        NSDecimalRound(&quotient, &divided, 0, .down)
        return NSDecimalNumber(decimal: quotient).intValue
    }

    // MARK: - 3. 胜率曲线

    public static func winRateCurve(from positions: [ClosedPosition]) -> WinRateCurve {
        let sorted = positions.sorted { $0.closeTime < $1.closeTime }
        var wins = 0
        var total = 0
        var points: [WinRatePoint] = []
        points.reserveCapacity(sorted.count)
        for position in sorted {
            total += 1
            if position.isWin { wins += 1 }
            let rate = Double(wins) / Double(total)
            points.append(WinRatePoint(timestamp: position.closeTime, cumulativeWins: wins, cumulativeTotal: total, cumulativeWinRate: rate))
        }
        let final = total > 0 ? Double(wins) / Double(total) : 0
        return WinRateCurve(points: points, finalWinRate: final)
    }

    // MARK: - 4. 品种矩阵

    public static func instrumentMatrix(from positions: [ClosedPosition]) -> InstrumentMatrix {
        var byInstrument: [String: (count: Int, total: Decimal, wins: Int)] = [:]
        for position in positions {
            var t = byInstrument[position.instrumentID] ?? (0, Decimal(0), 0)
            t.count += 1
            t.total += position.realizedPnL
            if position.isWin { t.wins += 1 }
            byInstrument[position.instrumentID] = t
        }
        let cells = byInstrument
            .map { (id, t) -> InstrumentMatrixCell in
                let rate = t.count > 0 ? Double(t.wins) / Double(t.count) : 0
                return InstrumentMatrixCell(instrumentID: id, tradeCount: t.count, totalPnL: t.total, winCount: t.wins, winRate: rate)
            }
            .sorted { $0.totalPnL > $1.totalPnL }
        return InstrumentMatrix(cells: cells)
    }

    // MARK: - 5. 持仓时间统计

    public static func holdingDurationStats(from positions: [ClosedPosition]) -> HoldingDurationStats {
        let durations = positions.map { $0.holdingSeconds }.sorted()
        guard !durations.isEmpty else {
            return HoldingDurationStats(
                totalCount: 0, averageSeconds: 0, medianSeconds: 0,
                minSeconds: 0, maxSeconds: 0, buckets: []
            )
        }
        let total = durations.reduce(0, +)
        let avg = total / Double(durations.count)
        let median: TimeInterval = {
            let n = durations.count
            if n % 2 == 1 { return durations[n / 2] }
            return (durations[n / 2 - 1] + durations[n / 2]) / 2
        }()

        // 6 个桶：< 1m / 1-5m / 5-30m / 30m-1h / 1h-1d / > 1d
        let bucketSpec: [(label: String, lower: TimeInterval, upper: TimeInterval)] = [
            ("<1m",   0,                 60),
            ("1-5m",  60,                300),
            ("5-30m", 300,               1800),
            ("30m-1h",1800,              3600),
            ("1h-1d", 3600,              86400),
            (">1d",   86400,             .infinity),
        ]
        let buckets: [HoldingDurationBucket] = bucketSpec.map { spec in
            let count = durations.filter { $0 >= spec.lower && $0 < spec.upper }.count
            return HoldingDurationBucket(label: spec.label, lowerSeconds: spec.lower, upperSeconds: spec.upper, count: count)
        }

        return HoldingDurationStats(
            totalCount: durations.count,
            averageSeconds: avg,
            medianSeconds: median,
            minSeconds: durations.first ?? 0,
            maxSeconds: durations.last ?? 0,
            buckets: buckets
        )
    }

    // MARK: - 6. 最大回撤

    public static func maxDrawdownCurve(from positions: [ClosedPosition]) -> MaxDrawdownCurve {
        let sorted = positions.sorted { $0.closeTime < $1.closeTime }
        var cumulative: Decimal = 0
        var highWater: Decimal = 0
        var highWaterTime: Date? = nil
        var points: [EquityPoint] = []
        points.reserveCapacity(sorted.count)

        var maxDD: Decimal = 0
        var maxDDStart: Date? = nil
        var maxDDEnd: Date? = nil

        for position in sorted {
            cumulative += position.realizedPnL
            if cumulative > highWater {
                highWater = cumulative
                highWaterTime = position.closeTime
            }
            let drawdown = highWater - cumulative
            points.append(EquityPoint(timestamp: position.closeTime, cumulativePnL: cumulative, highWaterMark: highWater, drawdown: drawdown))

            if drawdown > maxDD {
                maxDD = drawdown
                maxDDStart = highWaterTime
                maxDDEnd = position.closeTime
            }
        }
        return MaxDrawdownCurve(points: points, maxDrawdown: maxDD, maxDrawdownStart: maxDDStart, maxDrawdownEnd: maxDDEnd)
    }

    // MARK: - 7. 盈亏比

    public static func profitLossRatio(from positions: [ClosedPosition]) -> ProfitLossRatio {
        let wins = positions.filter { $0.realizedPnL > 0 }
        let losses = positions.filter { $0.realizedPnL < 0 }
        let avgWin: Decimal = wins.isEmpty ? 0 : wins.reduce(Decimal(0)) { $0 + $1.realizedPnL } / Decimal(wins.count)
        let avgLossSigned: Decimal = losses.isEmpty ? 0 : losses.reduce(Decimal(0)) { $0 + $1.realizedPnL } / Decimal(losses.count)
        let avgLoss = -avgLossSigned   // 转正
        let ratio: Decimal = avgLoss > 0 ? avgWin / avgLoss : 0
        return ProfitLossRatio(averageWin: avgWin, averageLoss: avgLoss, ratio: ratio, winCount: wins.count, lossCount: losses.count)
    }

    // MARK: - 8. 时段分析

    public static func sessionPnL(
        from positions: [ClosedPosition],
        timeZone: TimeZone = defaultTimeZone
    ) -> SessionPnL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var bySlot: [TradingSlot: (count: Int, total: Decimal, wins: Int)] = [:]
        for position in positions {
            let slot = Self.slot(for: position.closeTime, calendar: calendar)
            var t = bySlot[slot] ?? (0, Decimal(0), 0)
            t.count += 1
            t.total += position.realizedPnL
            if position.isWin { t.wins += 1 }
            bySlot[slot] = t
        }
        let buckets = TradingSlot.allCases.map { slot -> SessionPnLBucket in
            let t = bySlot[slot] ?? (0, Decimal(0), 0)
            let rate = t.count > 0 ? Double(t.wins) / Double(t.count) : 0
            return SessionPnLBucket(slot: slot, tradeCount: t.count, totalPnL: t.total, winCount: t.wins, winRate: rate)
        }
        return SessionPnL(buckets: buckets)
    }

    /// 按平仓时间归类时段
    private static func slot(for date: Date, calendar: Calendar) -> TradingSlot {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        switch minutes {
        case (9 * 60)..<(11 * 60 + 30):  return .morning
        case (13 * 60)..<(15 * 60):      return .afternoon
        case (21 * 60)..<(24 * 60):      return .night
        case 0..<(2 * 60 + 30):          return .midnight
        default:                         return .other
        }
    }

    // MARK: - 9. 复合风险调整指标（v15.18 · v2 范围 · 夏普 / Sortino / Calmar）
    //
    // 全部按"日 PnL"序列计算（按 closeTime 日聚合）· 年化系数默认 252（A 股期货交易日近似）
    // 输入空 / 单点 / 标准差 0 时返回 0（不抛 · 调用方 UI 视情况降级）

    /// 风险调整指标聚合
    public struct RiskAdjustedMetrics: Sendable, Codable, Equatable {
        public let sharpeRatio: Double           // 年化夏普 = mean / std × √252
        public let sortinoRatio: Double          // 年化 Sortino = mean / downsideStd × √252
        public let calmarRatio: Double           // 年化收益 / |最大回撤|
        public let recoveryFactor: Double        // 总收益 / |最大回撤|
        public let dailyMean: Double             // 日均收益
        public let dailyStdDev: Double           // 日波动
        public let dailyDownsideStdDev: Double   // 日下行波动
        public let tradingDays: Int              // 有交易的日历天数
    }

    // MARK: - 10. 盈利能力综合指标（v15.18 · ProfitFactor / Expectancy / GrossWin/Loss）

    public struct ProfitabilityMetrics: Sendable, Codable, Equatable {
        public let grossWin: Decimal           // 所有盈利交易总和
        public let grossLoss: Decimal          // 所有亏损交易总和（取绝对值 · 已转正）
        public let profitFactor: Double        // GrossWin / GrossLoss（无亏损时 +∞ → 999.0 上限）
        public let winRate: Double             // 胜率 0-1
        public let lossRate: Double            // 败率 0-1
        public let expectancy: Decimal         // 单笔期望 = avgWin*winRate - avgLoss*lossRate
        public let largestWin: Decimal         // 最大单笔盈利
        public let largestLoss: Decimal        // 最大单笔亏损（绝对值）
        public let totalTrades: Int
        public let winningTrades: Int
        public let losingTrades: Int
    }

    public static func profitabilityMetrics(from positions: [ClosedPosition]) -> ProfitabilityMetrics {
        guard !positions.isEmpty else {
            return ProfitabilityMetrics(
                grossWin: 0, grossLoss: 0, profitFactor: 0,
                winRate: 0, lossRate: 0, expectancy: 0,
                largestWin: 0, largestLoss: 0,
                totalTrades: 0, winningTrades: 0, losingTrades: 0
            )
        }
        let wins = positions.filter { $0.realizedPnL > 0 }
        let losses = positions.filter { $0.realizedPnL < 0 }
        let total = positions.count
        let winRate = Double(wins.count) / Double(total)
        let lossRate = Double(losses.count) / Double(total)

        let grossWin = wins.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        let grossLossSigned = losses.reduce(Decimal(0)) { $0 + $1.realizedPnL }
        let grossLoss = -grossLossSigned   // 转正

        let pf: Double
        if grossLoss > 0 {
            pf = NSDecimalNumber(decimal: grossWin / grossLoss).doubleValue
        } else if grossWin > 0 {
            pf = 999.0   // 无亏损 · 上限避免 Inf
        } else {
            pf = 0
        }

        let avgWin: Decimal = wins.isEmpty ? 0 : grossWin / Decimal(wins.count)
        let avgLoss: Decimal = losses.isEmpty ? 0 : grossLoss / Decimal(losses.count)
        let expectancy = avgWin * Decimal(winRate) - avgLoss * Decimal(lossRate)

        let largestWin = wins.map(\.realizedPnL).max() ?? 0
        let largestLossSigned = losses.map(\.realizedPnL).min() ?? 0
        let largestLoss = -largestLossSigned

        return ProfitabilityMetrics(
            grossWin: grossWin,
            grossLoss: grossLoss,
            profitFactor: pf,
            winRate: winRate,
            lossRate: lossRate,
            expectancy: expectancy,
            largestWin: largestWin,
            largestLoss: largestLoss,
            totalTrades: total,
            winningTrades: wins.count,
            losingTrades: losses.count
        )
    }

    // MARK: - 11. 连胜连败 Streak（v15.19+ batch17 · trader 连败心理预警必备）
    //
    // 算法：按 closeTime 升序遍历 ClosedPosition · 走 sign-run · 平交易（PnL=0）跳过不算
    // 提供 maxWinningStreak / maxLosingStreak（绝对值）+ currentStreak（带符号 · 正连胜负连败）
    // 与 ReviewAnalytics 现有指标同模式 · 测试覆盖 8+ 场景

    public struct StreakMetrics: Sendable, Codable, Equatable {
        public let maxWinningStreak: Int        // 历史最长连胜 N 笔
        public let maxLosingStreak: Int         // 历史最长连败 N 笔（绝对值 · 不带负号）
        public let currentStreak: Int           // 当前 · 正=连胜 N · 负=连败 N · 0=无交易/全平
        public let currentStreakIsWinning: Bool // currentStreak > 0
        public let switchCount: Int             // 胜→败 / 败→胜 切换次数（趋势稳定性参考）
        public let totalDecisiveTrades: Int     // 计入统计的非平交易数（PnL ≠ 0）
    }

    public static func streakMetrics(from positions: [ClosedPosition]) -> StreakMetrics {
        let sorted = positions.sorted { $0.closeTime < $1.closeTime }
        var maxWin = 0
        var maxLoss = 0          // 负值（min）· 末了取绝对
        var run = 0              // 带符号
        var switches = 0
        var prevWasWin: Bool? = nil
        var decisive = 0
        for p in sorted {
            let pnl = p.realizedPnL
            if pnl == 0 { continue }   // 平交易不计入 streak（trader 视角无情绪冲击）
            let isWin = pnl > 0
            decisive += 1
            if let prev = prevWasWin, prev != isWin {
                switches += 1
                run = 0
            }
            run += isWin ? 1 : -1
            if run > maxWin { maxWin = run }
            if run < maxLoss { maxLoss = run }
            prevWasWin = isWin
        }
        return StreakMetrics(
            maxWinningStreak: maxWin,
            maxLosingStreak: -maxLoss,
            currentStreak: run,
            currentStreakIsWinning: run > 0,
            switchCount: switches,
            totalDecisiveTrades: decisive
        )
    }

    public static func riskAdjustedMetrics(
        from positions: [ClosedPosition],
        annualizationFactor: Double = 252,
        timeZone: TimeZone = defaultTimeZone
    ) -> RiskAdjustedMetrics {
        guard !positions.isEmpty else {
            return RiskAdjustedMetrics(
                sharpeRatio: 0, sortinoRatio: 0, calmarRatio: 0, recoveryFactor: 0,
                dailyMean: 0, dailyStdDev: 0, dailyDownsideStdDev: 0, tradingDays: 0
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // 按日聚合 PnL（key = yyyy-MM-dd 起始时间）
        var byDay: [Date: Decimal] = [:]
        for p in positions {
            let day = calendar.startOfDay(for: p.closeTime)
            byDay[day, default: 0] += p.realizedPnL
        }
        let dailyDecimals = byDay.values
        let daily = dailyDecimals.map { NSDecimalNumber(decimal: $0).doubleValue }
        let n = daily.count
        guard n > 0 else {
            return RiskAdjustedMetrics(
                sharpeRatio: 0, sortinoRatio: 0, calmarRatio: 0, recoveryFactor: 0,
                dailyMean: 0, dailyStdDev: 0, dailyDownsideStdDev: 0, tradingDays: 0
            )
        }
        let mean = daily.reduce(0, +) / Double(n)
        let variance: Double = n > 1
            ? daily.map { pow($0 - mean, 2) }.reduce(0, +) / Double(n - 1)
            : 0
        let std = variance.squareRoot()
        let downsideSquares = daily.filter { $0 < mean }.map { pow($0 - mean, 2) }
        let downsideVar = downsideSquares.isEmpty ? 0 : downsideSquares.reduce(0, +) / Double(downsideSquares.count)
        let downsideStd = downsideVar.squareRoot()

        let annualMultiplier = annualizationFactor.squareRoot()
        let sharpe = std > 0 ? (mean / std) * annualMultiplier : 0
        let sortino = downsideStd > 0 ? (mean / downsideStd) * annualMultiplier : 0

        // Calmar / Recovery 借用现有 maxDrawdownCurve
        let dd = maxDrawdownCurve(from: positions).maxDrawdown
        let ddAbs = abs(NSDecimalNumber(decimal: dd).doubleValue)
        let totalPnL = daily.reduce(0, +)
        let annualPnL = totalPnL * (annualizationFactor / Double(n))
        let calmar = ddAbs > 0 ? annualPnL / ddAbs : 0
        let recovery = ddAbs > 0 ? totalPnL / ddAbs : 0

        return RiskAdjustedMetrics(
            sharpeRatio: sharpe,
            sortinoRatio: sortino,
            calmarRatio: calmar,
            recoveryFactor: recovery,
            dailyMean: mean,
            dailyStdDev: std,
            dailyDownsideStdDev: downsideStd,
            tradingDays: n
        )
    }
}
