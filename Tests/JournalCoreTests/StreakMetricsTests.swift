// v15.19+ batch17 · 连胜连败 streak 单测
// 覆盖空 / 全胜 / 全负 / 交替 / 平交易跳过 / 当前 streak 方向 / closeTime 排序

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("ReviewAnalytics · 连胜连败 Streak v15.19+ batch17")
struct StreakMetricsTests {

    private func position(_ pnl: Decimal, at offsetSec: TimeInterval) -> ClosedPosition {
        ClosedPosition(
            instrumentID: "rb2501", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: Date(timeIntervalSince1970: 1_700_000_000),
            closeTime: Date(timeIntervalSince1970: 1_700_000_000 + offsetSec),
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空输入 · 全部 0")
    func empty() {
        let m = ReviewAnalytics.streakMetrics(from: [])
        #expect(m.maxWinningStreak == 0)
        #expect(m.maxLosingStreak == 0)
        #expect(m.currentStreak == 0)
        #expect(m.totalDecisiveTrades == 0)
        #expect(m.switchCount == 0)
    }

    @Test("全胜 5 笔 · maxWin=5 / current=+5 / switches=0")
    func allWinning() {
        let positions = (0..<5).map { position(100, at: TimeInterval($0 * 60)) }
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 5)
        #expect(m.maxLosingStreak == 0)
        #expect(m.currentStreak == 5)
        #expect(m.currentStreakIsWinning == true)
        #expect(m.switchCount == 0)
        #expect(m.totalDecisiveTrades == 5)
    }

    @Test("全亏 4 笔 · maxLoss=4 / current=-4")
    func allLosing() {
        let positions = (0..<4).map { position(-100, at: TimeInterval($0 * 60)) }
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 0)
        #expect(m.maxLosingStreak == 4)
        #expect(m.currentStreak == -4)
        #expect(m.currentStreakIsWinning == false)
        #expect(m.switchCount == 0)
    }

    @Test("交替胜负 · maxWin=1 / maxLoss=1 / current=最后一笔 / switches 多次")
    func alternating() {
        // W L W L W → maxWin=1 maxLoss=1 current=+1 switches=4
        let positions = [
            position(100, at: 0),
            position(-100, at: 60),
            position(100, at: 120),
            position(-100, at: 180),
            position(100, at: 240)
        ]
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 1)
        #expect(m.maxLosingStreak == 1)
        #expect(m.currentStreak == 1)
        #expect(m.switchCount == 4)
    }

    @Test("3 胜 → 5 负 → 当前连败 5 / 历史最长连胜 3")
    func winThenLossStreak() {
        var positions: [ClosedPosition] = []
        for i in 0..<3 { positions.append(position(100, at: TimeInterval(i * 60))) }
        for i in 0..<5 { positions.append(position(-100, at: TimeInterval((3 + i) * 60))) }
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 3)
        #expect(m.maxLosingStreak == 5)
        #expect(m.currentStreak == -5)
        #expect(m.currentStreakIsWinning == false)
        #expect(m.switchCount == 1)
    }

    @Test("平交易（PnL=0）跳过 · 不破坏 streak")
    func breakevenSkipped() {
        // W W 0 W → 平不算切换 · maxWin=3 / current=+3
        let positions = [
            position(100, at: 0),
            position(100, at: 60),
            position(0, at: 120),     // 平交易
            position(100, at: 180)
        ]
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 3)
        #expect(m.currentStreak == 3)
        #expect(m.totalDecisiveTrades == 3)   // 平不计入
        #expect(m.switchCount == 0)
    }

    @Test("乱序输入 · 按 closeTime 升序统计（不依赖输入顺序）")
    func unorderedInput() {
        // 时序 W L L L · 但乱序传入
        let positions = [
            position(-100, at: 60),
            position(-100, at: 180),
            position(100, at: 0),
            position(-100, at: 120)
        ]
        let m = ReviewAnalytics.streakMetrics(from: positions)
        #expect(m.maxWinningStreak == 1)
        #expect(m.maxLosingStreak == 3)
        #expect(m.currentStreak == -3)
        #expect(m.switchCount == 1)
    }

    @Test("Codable 往返")
    func codableRoundTrip() throws {
        let positions = [position(100, at: 0), position(-100, at: 60)]
        let m = ReviewAnalytics.streakMetrics(from: positions)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(ReviewAnalytics.StreakMetrics.self, from: data)
        #expect(decoded == m)
    }
}
