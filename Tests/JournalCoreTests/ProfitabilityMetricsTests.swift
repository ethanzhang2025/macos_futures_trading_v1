// WP-50 v15.18 · 盈利能力综合指标单测

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("ReviewAnalytics · 盈利能力综合指标")
struct ProfitabilityMetricsTests {

    private func position(_ pnl: Decimal) -> ClosedPosition {
        ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: Date(), closeTime: Date(),
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空输入 · 全部 0")
    func emptyZero() {
        let m = ReviewAnalytics.profitabilityMetrics(from: [])
        #expect(m.totalTrades == 0)
        #expect(m.profitFactor == 0)
        #expect(m.expectancy == 0)
    }

    @Test("全胜 · profitFactor = 999.0 上限（防 Inf）")
    func allWinsProfitFactorCap() {
        let m = ReviewAnalytics.profitabilityMetrics(from: [
            position(100), position(200), position(50)
        ])
        #expect(m.winningTrades == 3)
        #expect(m.losingTrades == 0)
        #expect(m.grossWin == 350)
        #expect(m.grossLoss == 0)
        #expect(m.profitFactor == 999.0)
        #expect(m.winRate == 1.0)
    }

    @Test("全亏 · profitFactor = 0")
    func allLossesProfitFactorZero() {
        let m = ReviewAnalytics.profitabilityMetrics(from: [
            position(-100), position(-50)
        ])
        #expect(m.winningTrades == 0)
        #expect(m.losingTrades == 2)
        #expect(m.grossWin == 0)
        #expect(m.grossLoss == 150)   // 转正
        #expect(m.profitFactor == 0)
    }

    @Test("混合 · profitFactor = grossWin / grossLoss")
    func mixedProfitFactor() {
        let m = ReviewAnalytics.profitabilityMetrics(from: [
            position(200), position(-50), position(100), position(-50)
        ])
        // grossWin = 300 / grossLoss = 100 / pf = 3.0
        #expect(m.grossWin == 300)
        #expect(m.grossLoss == 100)
        #expect(m.profitFactor == 3.0)
        #expect(m.winRate == 0.5)
        #expect(m.totalTrades == 4)
    }

    @Test("expectancy 计算 · avgWin*winRate - avgLoss*lossRate")
    func expectancyCalculation() {
        // 4 笔：+100, +200, -50, -50 · avgWin=150 / avgLoss=50 / winRate=0.5
        // expectancy = 150*0.5 - 50*0.5 = 75 - 25 = 50
        let m = ReviewAnalytics.profitabilityMetrics(from: [
            position(100), position(200), position(-50), position(-50)
        ])
        #expect(m.expectancy == 50)
    }

    @Test("largestWin / largestLoss · 最大单笔")
    func largestExtremes() {
        let m = ReviewAnalytics.profitabilityMetrics(from: [
            position(50), position(500), position(-100), position(-300)
        ])
        #expect(m.largestWin == 500)
        #expect(m.largestLoss == 300)   // 转正
    }
}
