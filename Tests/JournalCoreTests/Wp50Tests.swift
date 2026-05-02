// WP-50 · 复盘分析 8 张图测试
// FIFO 配对 + 8 图各自的已知期望值

import Testing
import Foundation
import Shared
@testable import JournalCore

// MARK: - 测试辅助

private let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")!

/// 构造 trade · 价格/手数 + 时间组件
private func trade(
    _ instrumentID: String = "rb2510",
    direction: Direction,
    offset: OffsetFlag,
    price: Decimal,
    volume: Int = 1,
    commission: Decimal = 0,
    timestamp: Date
) -> Trade {
    Trade(
        tradeReference: "T-\(UUID().uuidString.prefix(6))",
        instrumentID: instrumentID,
        direction: direction, offsetFlag: offset,
        price: price, volume: volume, commission: commission,
        timestamp: timestamp, source: .manual
    )
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = beijingTimeZone
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
    return calendar.date(from: c)!
}

// MARK: - 1. PositionMatcher FIFO 配对

@Suite("PositionMatcher · FIFO 配对")
struct PositionMatcherTests {

    @Test("空 trades → 空配对")
    func emptyInput() {
        let result = PositionMatcher.match(trades: [])
        #expect(result.closed.isEmpty)
        #expect(result.openRemaining.isEmpty)
    }

    @Test("多头：buy-open 3500 → sell-close 3520，PnL = (3520-3500)*1*10 = 200")
    func longTradeBasicPnL() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .sell, offset: .close, price: 3520, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].side == .long)
        #expect(result.closed[0].realizedPnL == 200)
        #expect(result.openRemaining.isEmpty)
    }

    @Test("空头：sell-open 3500 → buy-close 3480，PnL = (3500-3480)*1*10 = 200")
    func shortTradeBasicPnL() {
        let t1 = trade(direction: .sell, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .buy, offset: .close, price: 3480, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].side == .short)
        #expect(result.closed[0].realizedPnL == 200)
    }

    @Test("FIFO：先开 3500 后开 3510 → 一笔平仓 1 手 → 配对 3500 那笔")
    func fifoOrder() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .buy, offset: .open, price: 3510, timestamp: date(2026, 4, 25, 10))
        let t3 = trade(direction: .sell, offset: .close, price: 3520, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2, t3], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].openPrice == 3500)
        #expect(result.openRemaining.count == 1)
        #expect(result.openRemaining[0].remainingVolume == 1)
    }

    @Test("部分平仓：开 5 手 → 平 2 手 → 1 配对 + 剩 3 手")
    func partialClose() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, volume: 5, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .sell, offset: .close, price: 3520, volume: 2, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].volume == 2)
        #expect(result.closed[0].realizedPnL == 400)  // (3520-3500)*2*10
        #expect(result.openRemaining[0].remainingVolume == 3)
    }

    @Test("一次平仓跨多笔开仓：3 + 2 = 5 → 一次平 5 → 拆 2 个 closed")
    func crossMultipleOpens() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, volume: 3, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .buy, offset: .open, price: 3510, volume: 2, timestamp: date(2026, 4, 25, 10))
        let t3 = trade(direction: .sell, offset: .close, price: 3520, volume: 5, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2, t3], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 2)
        // 第 1 个：配 t1（3500，3 手）
        #expect(result.closed[0].volume == 3)
        #expect(result.closed[0].realizedPnL == 600)  // (3520-3500)*3*10
        // 第 2 个：配 t2（3510，2 手）
        #expect(result.closed[1].volume == 2)
        #expect(result.closed[1].realizedPnL == 200)  // (3520-3510)*2*10
    }

    @Test("多合约不串线：rb 与 hc 各自配对")
    func multiInstrumentIsolation() {
        let t1 = trade("rb2510", direction: .buy, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade("hc2510", direction: .buy, offset: .open, price: 3000, timestamp: date(2026, 4, 25, 9))
        let t3 = trade("rb2510", direction: .sell, offset: .close, price: 3520, timestamp: date(2026, 4, 25, 14))
        let t4 = trade("hc2510", direction: .sell, offset: .close, price: 3050, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(
            trades: [t1, t2, t3, t4],
            multipliers: ["rb2510": 10, "hc2510": 10]
        )
        #expect(result.closed.count == 2)
        #expect(result.closed.contains { $0.instrumentID == "rb2510" && $0.realizedPnL == 200 })
        #expect(result.closed.contains { $0.instrumentID == "hc2510" && $0.realizedPnL == 500 })
    }

    @Test("手续费分摊：开 5 手 commission 50 → 平 2 手 → 开侧分摊 20")
    func commissionProrated() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, volume: 5, commission: 50, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .sell, offset: .close, price: 3520, volume: 2, commission: 20, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2], multipliers: ["rb2510": 10])
        // PnL before fees: 400; commission: 20 (open share) + 20 (close) = 40; net 360
        #expect(result.closed[0].totalCommission == 40)
        #expect(result.closed[0].realizedPnL == 360)
    }

    @Test("平今 / 平昨 / 强平 都视为平仓")
    func closeFlagsAllRecognized() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .sell, offset: .closeToday, price: 3520, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
    }

    @Test("multiplier 缺失时 fallback = 1")
    func multiplierFallback() {
        let t1 = trade(direction: .buy, offset: .open, price: 3500, timestamp: date(2026, 4, 25, 9))
        let t2 = trade(direction: .sell, offset: .close, price: 3520, timestamp: date(2026, 4, 25, 14))
        let result = PositionMatcher.match(trades: [t1, t2])  // 无 multipliers
        #expect(result.closed[0].realizedPnL == 20)  // (3520-3500)*1*1
    }
}

// MARK: - 测试辅助：构造 closed positions

private func makeClosedPosition(
    instrumentID: String = "rb2510",
    side: PositionSide = .long,
    pnl: Decimal,
    closeTime: Date,
    holdingSeconds: TimeInterval = 3600
) -> ClosedPosition {
    ClosedPosition(
        instrumentID: instrumentID,
        side: side,
        openTradeID: UUID(), closeTradeID: UUID(),
        openTime: closeTime.addingTimeInterval(-holdingSeconds),
        closeTime: closeTime,
        openPrice: 3500, closePrice: 3500 + pnl, volume: 1,
        realizedPnL: pnl, totalCommission: 0
    )
}

// MARK: - 2. 月度盈亏

@Suite("ReviewAnalytics · 月度盈亏")
struct MonthlyPnLTests {

    @Test("空输入 → 空 buckets, totalPnL = 0")
    func empty() {
        let result = ReviewAnalytics.monthlyPnL(from: [])
        #expect(result.buckets.isEmpty)
        #expect(result.totalPnL == 0)
    }

    @Test("跨月聚合 + 排序")
    func crossMonthAggregate() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 3, 15)),
            makeClosedPosition(pnl: -50, closeTime: date(2026, 3, 20)),
            makeClosedPosition(pnl: 200, closeTime: date(2026, 4, 10)),
        ]
        let result = ReviewAnalytics.monthlyPnL(from: positions)
        #expect(result.buckets.count == 2)
        #expect(result.buckets[0].year == 2026 && result.buckets[0].month == 3)
        #expect(result.buckets[0].realizedPnL == 50)
        #expect(result.buckets[0].tradeCount == 2)
        #expect(result.buckets[1].month == 4)
        #expect(result.buckets[1].realizedPnL == 200)
        #expect(result.totalPnL == 250)
    }
}

// MARK: - 2b. 季度盈亏（v15.17 · D2 §2 月度/季度总结）

@Suite("ReviewAnalytics · 季度盈亏")
struct QuarterlyPnLTests {

    @Test("空输入 → 空 buckets, totalPnL = 0")
    func empty() {
        let result = ReviewAnalytics.quarterlyPnL(from: [])
        #expect(result.buckets.isEmpty)
        #expect(result.totalPnL == 0)
    }

    @Test("Q1 边界（3月）+ Q2 起点（4月）正确分桶")
    func quarterBoundary() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 1, 5)),   // Q1
            makeClosedPosition(pnl: 200, closeTime: date(2026, 3, 31)),  // Q1
            makeClosedPosition(pnl: 300, closeTime: date(2026, 4, 1)),   // Q2
            makeClosedPosition(pnl: 400, closeTime: date(2026, 12, 31)), // Q4
        ]
        let result = ReviewAnalytics.quarterlyPnL(from: positions)
        #expect(result.buckets.count == 3)
        #expect(result.buckets[0].year == 2026 && result.buckets[0].quarter == 1)
        #expect(result.buckets[0].realizedPnL == 300)
        #expect(result.buckets[0].tradeCount == 2)
        #expect(result.buckets[1].quarter == 2)
        #expect(result.buckets[1].realizedPnL == 300)
        #expect(result.buckets[2].quarter == 4)
        #expect(result.buckets[2].realizedPnL == 400)
        #expect(result.totalPnL == 1000)
    }

    @Test("跨年 · 排序按 (year, quarter) 升序")
    func crossYear() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 11, 1)),  // 2026 Q4
            makeClosedPosition(pnl: 200, closeTime: date(2025, 7, 1)),   // 2025 Q3
        ]
        let result = ReviewAnalytics.quarterlyPnL(from: positions)
        #expect(result.buckets.count == 2)
        #expect(result.buckets[0].year == 2025 && result.buckets[0].quarter == 3)
        #expect(result.buckets[1].year == 2026 && result.buckets[1].quarter == 4)
    }
}

// MARK: - 2c. 年度盈亏（v15.17 · 日历年聚合）

@Suite("ReviewAnalytics · 年度盈亏")
struct YearlyPnLTests {

    @Test("空输入 → 空 buckets, totalPnL = 0")
    func empty() {
        let result = ReviewAnalytics.yearlyPnL(from: [])
        #expect(result.buckets.isEmpty)
        #expect(result.totalPnL == 0)
    }

    @Test("跨年聚合 + 排序 + 同年累加")
    func crossYear() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2025, 1, 5)),
            makeClosedPosition(pnl: 200, closeTime: date(2025, 12, 31)),
            makeClosedPosition(pnl: 300, closeTime: date(2026, 6, 15)),
            makeClosedPosition(pnl: -50, closeTime: date(2026, 11, 30)),
        ]
        let result = ReviewAnalytics.yearlyPnL(from: positions)
        #expect(result.buckets.count == 2)
        #expect(result.buckets[0].year == 2025)
        #expect(result.buckets[0].realizedPnL == 300)
        #expect(result.buckets[0].tradeCount == 2)
        #expect(result.buckets[1].year == 2026)
        #expect(result.buckets[1].realizedPnL == 250)
        #expect(result.totalPnL == 550)
    }
}

// MARK: - 3. 分布直方

@Suite("ReviewAnalytics · 分布直方")
struct PnLDistributionTests {

    @Test("binSize 100，PnL [50, 150, 250] → 桶 0/1/2 各 1")
    func basicBuckets() {
        let positions = [
            makeClosedPosition(pnl: 50, closeTime: date(2026, 4, 25)),
            makeClosedPosition(pnl: 150, closeTime: date(2026, 4, 25)),
            makeClosedPosition(pnl: 250, closeTime: date(2026, 4, 25)),
        ]
        let result = ReviewAnalytics.pnlDistribution(from: positions, binSize: 100)
        #expect(result.bins.count == 3)
        #expect(result.bins.allSatisfy { $0.count == 1 })
        #expect(result.positiveCount == 3)
        #expect(result.negativeCount == 0)
    }

    @Test("负数桶：PnL -50 → 桶 -1（[-100, 0)）")
    func negativeBucket() {
        let positions = [makeClosedPosition(pnl: -50, closeTime: date(2026, 4, 25))]
        let result = ReviewAnalytics.pnlDistribution(from: positions, binSize: 100)
        #expect(result.bins.count == 1)
        #expect(result.bins[0].lowerBound == -100)
        #expect(result.bins[0].upperBound == 0)
        #expect(result.negativeCount == 1)
    }
}

// MARK: - 4. 胜率曲线

@Suite("ReviewAnalytics · 胜率曲线")
struct WinRateCurveTests {

    @Test("3 胜 1 负 → finalWinRate = 0.75")
    func basicWinRate() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 9)),
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 10)),
            makeClosedPosition(pnl: -50, closeTime: date(2026, 4, 25, 11)),
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 14)),
        ]
        let result = ReviewAnalytics.winRateCurve(from: positions)
        #expect(result.points.count == 4)
        #expect(result.finalWinRate == 0.75)
        // 第 3 点：3 胜 0 负？不对，第 3 笔是 -50 → 2 胜 1 负 → 2/3
        #expect(abs(result.points[2].cumulativeWinRate - 2.0 / 3.0) < 0.001)
    }
}

// MARK: - 5. 品种矩阵

@Suite("ReviewAnalytics · 品种矩阵")
struct InstrumentMatrixTests {

    @Test("rb 总盈 100，hc 总盈 -50 → 按 totalPnL 降序")
    func sortByPnLDesc() {
        let positions = [
            makeClosedPosition(instrumentID: "rb2510", pnl: 100, closeTime: date(2026, 4, 25)),
            makeClosedPosition(instrumentID: "rb2510", pnl: -50, closeTime: date(2026, 4, 25)),
            makeClosedPosition(instrumentID: "hc2510", pnl: -50, closeTime: date(2026, 4, 25)),
        ]
        let result = ReviewAnalytics.instrumentMatrix(from: positions)
        #expect(result.cells.count == 2)
        #expect(result.cells[0].instrumentID == "rb2510")
        #expect(result.cells[0].totalPnL == 50)
        #expect(result.cells[0].tradeCount == 2)
        #expect(result.cells[0].winCount == 1)
        #expect(result.cells[0].winRate == 0.5)
        #expect(result.cells[1].instrumentID == "hc2510")
    }
}

// MARK: - 6. 持仓时间统计

@Suite("ReviewAnalytics · 持仓时间")
struct HoldingDurationTests {

    @Test("空 → 全 0")
    func empty() {
        let result = ReviewAnalytics.holdingDurationStats(from: [])
        #expect(result.totalCount == 0)
    }

    @Test("3 个 [60, 300, 1800] → median = 300")
    func medianAndBuckets() {
        let positions = [
            makeClosedPosition(pnl: 0, closeTime: date(2026, 4, 25), holdingSeconds: 60),
            makeClosedPosition(pnl: 0, closeTime: date(2026, 4, 25), holdingSeconds: 300),
            makeClosedPosition(pnl: 0, closeTime: date(2026, 4, 25), holdingSeconds: 1800),
        ]
        let result = ReviewAnalytics.holdingDurationStats(from: positions)
        #expect(result.totalCount == 3)
        #expect(result.medianSeconds == 300)
        #expect(result.minSeconds == 60)
        #expect(result.maxSeconds == 1800)

        // 6 桶：60s 在 1-5m / 300s 在 5-30m / 1800s 在 30m-1h
        let labels = result.buckets.filter { $0.count > 0 }.map(\.label)
        #expect(labels == ["1-5m", "5-30m", "30m-1h"])
    }
}

// MARK: - 7. 最大回撤

@Suite("ReviewAnalytics · 最大回撤")
struct MaxDrawdownTests {

    @Test("权益 +100 → -200 → +50：高水位 100，最低 -100，回撤 200")
    func basicDrawdown() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 10)),
            makeClosedPosition(pnl: -200, closeTime: date(2026, 4, 25, 11)),
            makeClosedPosition(pnl: 50, closeTime: date(2026, 4, 25, 12)),
        ]
        let result = ReviewAnalytics.maxDrawdownCurve(from: positions)
        #expect(result.points.count == 3)
        #expect(result.points[0].cumulativePnL == 100)
        #expect(result.points[0].drawdown == 0)
        #expect(result.points[1].cumulativePnL == -100)
        #expect(result.points[1].drawdown == 200)  // 100 - (-100) = 200
        #expect(result.maxDrawdown == 200)
        #expect(result.maxDrawdownStart == date(2026, 4, 25, 10))
        #expect(result.maxDrawdownEnd == date(2026, 4, 25, 11))
    }

    @Test("无回撤（一直上涨）→ maxDrawdown = 0")
    func noDrawdown() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 10)),
            makeClosedPosition(pnl: 50, closeTime: date(2026, 4, 25, 11)),
        ]
        let result = ReviewAnalytics.maxDrawdownCurve(from: positions)
        #expect(result.maxDrawdown == 0)
    }
}

// MARK: - 8. 盈亏比

@Suite("ReviewAnalytics · 盈亏比")
struct ProfitLossRatioTests {

    @Test("avgWin 100 / avgLoss 50 → ratio = 2")
    func basicRatio() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25)),
            makeClosedPosition(pnl: -50, closeTime: date(2026, 4, 25)),
        ]
        let result = ReviewAnalytics.profitLossRatio(from: positions)
        #expect(result.averageWin == 100)
        #expect(result.averageLoss == 50)
        #expect(result.ratio == 2)
        #expect(result.winCount == 1)
        #expect(result.lossCount == 1)
    }

    @Test("无亏损 → ratio = 0（避免除零）")
    func noLossRatioZero() {
        let positions = [makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25))]
        let result = ReviewAnalytics.profitLossRatio(from: positions)
        #expect(result.ratio == 0)
        #expect(result.lossCount == 0)
    }
}

// MARK: - 9. 时段分析

@Suite("ReviewAnalytics · 时段分析")
struct SessionPnLTests {

    @Test("4 时段聚合：早盘 100 / 午盘 -50 / 夜盘 200 / 凌晨 0")
    func sessionAggregation() {
        let positions = [
            makeClosedPosition(pnl: 100, closeTime: date(2026, 4, 25, 10, 0)),    // morning
            makeClosedPosition(pnl: -50, closeTime: date(2026, 4, 25, 14, 0)),   // afternoon
            makeClosedPosition(pnl: 200, closeTime: date(2026, 4, 25, 22, 0)),   // night
        ]
        let result = ReviewAnalytics.sessionPnL(from: positions)
        let morning = result.buckets.first { $0.slot == .morning }!
        let afternoon = result.buckets.first { $0.slot == .afternoon }!
        let night = result.buckets.first { $0.slot == .night }!
        let midnight = result.buckets.first { $0.slot == .midnight }!
        #expect(morning.totalPnL == 100)
        #expect(morning.tradeCount == 1)
        #expect(afternoon.totalPnL == -50)
        #expect(night.totalPnL == 200)
        #expect(midnight.tradeCount == 0)
    }
}
