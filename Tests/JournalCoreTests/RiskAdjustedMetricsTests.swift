// WP-50 v15.18 · 复合风险调整指标单测（Sharpe / Sortino / Calmar / Recovery）

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("ReviewAnalytics · 复合风险调整指标（v15.18）")
struct RiskAdjustedMetricsTests {

    private func utc(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        c.year = y; c.month = mo; c.day = d; c.hour = 15; c.minute = 0
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func position(_ pnl: Decimal, day: Date) -> ClosedPosition {
        ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: day.addingTimeInterval(-3600), closeTime: day,
            openPrice: 3500, closePrice: 3500 + pnl / 10,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空输入 · 全部指标 = 0（防 NaN / Inf）")
    func emptyReturnsZero() {
        let m = ReviewAnalytics.riskAdjustedMetrics(from: [])
        #expect(m.sharpeRatio == 0)
        #expect(m.sortinoRatio == 0)
        #expect(m.calmarRatio == 0)
        #expect(m.recoveryFactor == 0)
        #expect(m.tradingDays == 0)
    }

    @Test("单日单笔 · std=0 · sharpe=0（不抛 Inf）")
    func singleDaySharpeZero() {
        let m = ReviewAnalytics.riskAdjustedMetrics(from: [
            position(100, day: utc(2026, 1, 1))
        ])
        #expect(m.tradingDays == 1)
        #expect(m.sharpeRatio == 0)   // n=1 std=0
    }

    @Test("3 天均盈利且波动相同 · sharpe > 0 · 计算正确（mean=100 / std≠0 / annualized）")
    func threeDaySharpePositive() {
        let positions = [
            position(50, day: utc(2026, 1, 1)),
            position(100, day: utc(2026, 1, 2)),
            position(150, day: utc(2026, 1, 3))
        ]
        let m = ReviewAnalytics.riskAdjustedMetrics(from: positions, annualizationFactor: 252)
        #expect(m.tradingDays == 3)
        #expect(m.dailyMean == 100)
        // var = ((50-100)^2 + (100-100)^2 + (150-100)^2) / (3-1) = 5000/2 = 2500 · std=50
        #expect(m.dailyStdDev == 50)
        // sharpe = (100/50) * sqrt(252) ≈ 2 * 15.87 ≈ 31.75
        #expect(m.sharpeRatio > 31)
        #expect(m.sharpeRatio < 32)
    }

    @Test("3 天 · sortino · 仅下行波动")
    func sortinoOnlyDownsideStd() {
        let positions = [
            position(-100, day: utc(2026, 1, 1)),
            position(100, day: utc(2026, 1, 2)),
            position(100, day: utc(2026, 1, 3))
        ]
        // mean = (−100 + 100 + 100) / 3 ≈ 33.33
        // 仅 −100 < mean · downsideVar = (−100 − 33.33)² / 1 ≈ 17777.78
        // downsideStd ≈ 133.33
        let m = ReviewAnalytics.riskAdjustedMetrics(from: positions)
        #expect(m.sortinoRatio > 0)
        #expect(m.dailyDownsideStdDev > 100 && m.dailyDownsideStdDev < 200)
    }

    @Test("Calmar / Recovery · 用 maxDrawdownCurve 计算")
    func calmarUsesMaxDrawdown() {
        let positions = [
            position(200, day: utc(2026, 1, 1)),     // cum = 200
            position(-300, day: utc(2026, 1, 2)),    // cum = -100, dd from 200 = -300
            position(400, day: utc(2026, 1, 3))      // cum = 300
        ]
        let m = ReviewAnalytics.riskAdjustedMetrics(from: positions)
        // total = 300 · maxDrawdown = -300（从 200 到 -100）· recovery = 300 / 300 = 1
        #expect(m.recoveryFactor == 1)
        #expect(m.calmarRatio != 0)
    }

    @Test("同日多笔合并为日 PnL 序列（按 closeTime 日聚合）")
    func sameDayMerged() {
        let day = utc(2026, 1, 1)
        let positions = [
            position(50, day: day),
            position(50, day: day),     // 同日 · 合并 = 100
            position(200, day: utc(2026, 1, 2))
        ]
        let m = ReviewAnalytics.riskAdjustedMetrics(from: positions)
        #expect(m.tradingDays == 2)
        #expect(m.dailyMean == 150)   // (100 + 200) / 2
    }
}
