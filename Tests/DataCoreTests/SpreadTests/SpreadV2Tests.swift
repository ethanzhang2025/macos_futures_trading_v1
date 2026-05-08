// 套利 V2 单测（v15.37 · 滚动 Z + 直方图 + 信号 + 回测）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("Spread V2 · 滚动 Z / 直方图 / 信号 / 回测")
struct SpreadV2Tests {

    // MARK: - 测试辅助

    private func makeValues(_ doubles: [Double]) -> [SpreadValue] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return doubles.enumerated().map { (i, v) in
            SpreadValue(
                openTime: start.addingTimeInterval(TimeInterval(i * 60)),
                value: Decimal(v), leg1Close: 100, leg2Close: 100
            )
        }
    }

    // MARK: - 滚动 Z

    @Test("rollingZScores · window 内不足时返 0")
    func rollingZSparse() {
        let v = makeValues([1, 2, 3])
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 5)
        #expect(zs.allSatisfy { $0 == 0 })
    }

    @Test("rollingZScores · 平稳序列 Z 接近 0")
    func rollingZStable() {
        let v = makeValues(Array(repeating: 100.0, count: 30))
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 10)
        // 全相同 → σ=0 → Z=0
        #expect(zs.allSatisfy { abs($0) < 1e-9 })
    }

    @Test("rollingZScores · 末根突变 · Z 显著为正")
    func rollingZSpike() {
        var arr: [Double] = Array(repeating: 100, count: 19) + [120]
        let v = makeValues(arr)
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 10)
        // 末点 = 120 · 过去 10 根含 9 个 100 + 1 个 120 · mean=102 · σ ≈ 6.32 · Z ≈ 2.85
        let lastZ = zs.last!
        #expect(lastZ > 2.5)
        _ = arr
    }

    // MARK: - 直方图

    @Test("histogram · 空 / 单点返 .empty")
    func histogramEmpty() {
        #expect(SpreadHistogramCalculator.compute(makeValues([])) == .empty)
        #expect(SpreadHistogramCalculator.compute(makeValues([5])) == .empty)
    }

    @Test("histogram · 均匀分布 · 各 bin count 接近")
    func histogramUniform() {
        // 100 个均匀分布 [0, 100) 的样本
        let arr = (0..<100).map { Double($0) }
        let h = SpreadHistogramCalculator.compute(makeValues(arr), binCount: 10)
        #expect(h.bins.count == 10)
        #expect(h.totalCount == 100)
        // 每 bin ~10 ± 2（边界 +pad 略偏）
        for bin in h.bins {
            #expect(bin.count >= 5 && bin.count <= 15)
        }
    }

    @Test("histogram · 末值在范围内 · currentBinIndex 有效")
    func histogramCurrentBin() {
        let arr: [Double] = (0..<50).map { Double($0) } + [25]
        let h = SpreadHistogramCalculator.compute(makeValues(arr), binCount: 10)
        // 末值 = 25 · 应在 bins[5] 附近（中段）· 不该是 -1
        #expect(h.currentBinIndex >= 0)
        #expect(h.currentBinIndex < h.bins.count)
    }

    @Test("histogram · 众数 bin 在数据集中处")
    func histogramMode() {
        // 大量集中在 50 附近 · mode 应在中段
        var arr = (0..<10).map { Double($0) }      // 0..9 各 1
        arr.append(contentsOf: Array(repeating: 50.0, count: 50))  // 50 重复 50 次
        let h = SpreadHistogramCalculator.compute(makeValues(arr), binCount: 10)
        let modeBin = h.bins[h.modeBinIndex]
        #expect(modeBin.lowerBound <= 50 && 50 <= modeBin.upperBound)
    }

    // MARK: - 信号生成

    @Test("信号 · 平稳序列无信号")
    func signalsNoEntry() {
        let v = makeValues(Array(repeating: 100.0, count: 100))
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 20)
        let sigs = SpreadSignalGenerator.generate(values: v, rollingZScores: zs)
        #expect(sigs.isEmpty)
    }

    @Test("信号 · Z 突破 +entryThreshold · 短信号 entry")
    func signalShortEntry() {
        // 前 19 根稳定 · 第 20 根突变 · 应触发 short entry
        let arr: [Double] = Array(repeating: 100, count: 19) + [200]
        let v = makeValues(arr)
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 10)
        let sigs = SpreadSignalGenerator.generate(values: v, rollingZScores: zs,
                                                   entryThreshold: 2.0, exitThreshold: 0.5)
        // 至少有 1 个 entry · 第 20 根处
        #expect(!sigs.isEmpty)
        let firstEntry = sigs.first { $0.action == .entry }
        #expect(firstEntry?.side == .short)
    }

    @Test("信号 · entry/exit 严格成对（末尾若持仓自动平）")
    func signalsEntryExitPaired() {
        // 模拟价差先涨突破 +2σ 入场 · 然后回归 0 出场 · 再跌破 -2σ 入场 · 末尾仍持仓
        let arr: [Double] = Array(repeating: 100, count: 30)
            + Array(repeating: 200, count: 5)     // Z 飙升 → short entry
            + Array(repeating: 100, count: 30)    // Z 回归 → exit
            + Array(repeating: 50, count: 5)      // Z 飙降 → long entry
            + Array(repeating: 60, count: 3)      // 持仓中 · 末尾自动平
        let v = makeValues(arr)
        let zs = SpreadStatisticsCalculator.rollingZScores(v, window: 10)
        let sigs = SpreadSignalGenerator.generate(values: v, rollingZScores: zs)
        // entry 数 = exit 数（成对 · 含末尾自动平）
        let entries = sigs.filter { $0.action == .entry }.count
        let exits = sigs.filter { $0.action == .exit }.count
        #expect(entries == exits)
        #expect(entries >= 2)
    }

    // MARK: - 回测引擎

    @Test("回测 · 空信号 → empty summary")
    func backtestEmpty() {
        let (trades, summary) = SpreadBacktester.run(signals: [])
        #expect(trades.isEmpty)
        #expect(summary == .empty)
    }

    @Test("回测 · 做多价差盈利 · pnl = exitValue - entryValue")
    func backtestLongProfit() {
        let entry = SpreadSignal(
            index: 0, openTime: Date(), value: 100, zScore: -2.5,
            side: .long, action: .entry
        )
        let exit = SpreadSignal(
            index: 10, openTime: Date().addingTimeInterval(600),
            value: 130, zScore: 0, side: .long, action: .exit
        )
        let (trades, summary) = SpreadBacktester.run(signals: [entry, exit])
        #expect(trades.count == 1)
        #expect(trades[0].pnl == 30)
        #expect(trades[0].isWin)
        #expect(summary.totalPnL == 30)
        #expect(summary.winRate == 1.0)
    }

    @Test("回测 · 做空价差盈利 · pnl = entryValue - exitValue")
    func backtestShortProfit() {
        let entry = SpreadSignal(
            index: 0, openTime: Date(), value: 200, zScore: 2.5,
            side: .short, action: .entry
        )
        let exit = SpreadSignal(
            index: 10, openTime: Date().addingTimeInterval(600),
            value: 150, zScore: 0, side: .short, action: .exit
        )
        let (trades, summary) = SpreadBacktester.run(signals: [entry, exit])
        #expect(trades[0].pnl == 50)
        #expect(summary.totalPnL == 50)
    }

    @Test("回测 · 多笔交易 · 累积 PnL 单调累计")
    func backtestCumulative() {
        var sigs: [SpreadSignal] = []
        // 3 笔做多 · 各赚 10/20/30
        for i in 0..<3 {
            let base = i * 100
            let entry = SpreadSignal(
                index: base, openTime: Date().addingTimeInterval(TimeInterval(base * 60)),
                value: 100, zScore: -2.5, side: .long, action: .entry
            )
            let exit = SpreadSignal(
                index: base + 10, openTime: Date().addingTimeInterval(TimeInterval((base + 10) * 60)),
                value: Decimal(100 + (i + 1) * 10), zScore: 0,
                side: .long, action: .exit
            )
            sigs.append(contentsOf: [entry, exit])
        }
        let (trades, summary) = SpreadBacktester.run(signals: sigs)
        #expect(trades.count == 3)
        #expect(summary.totalPnL == 60)  // 10 + 20 + 30
        #expect(summary.cumulativePnL == [0, 10, 30, 60])
        #expect(summary.maxWinPnL == 30)
    }

    @Test("回测 · 含亏损交易 · 胜率正确")
    func backtestWinRate() {
        // 2 笔多 · 1 赚 1 亏
        let sigs: [SpreadSignal] = [
            SpreadSignal(index: 0, openTime: Date(), value: 100, zScore: -2.5,
                        side: .long, action: .entry),
            SpreadSignal(index: 10, openTime: Date().addingTimeInterval(600),
                        value: 130, zScore: 0, side: .long, action: .exit),
            SpreadSignal(index: 20, openTime: Date().addingTimeInterval(1200),
                        value: 100, zScore: -2.5, side: .long, action: .entry),
            SpreadSignal(index: 30, openTime: Date().addingTimeInterval(1800),
                        value: 80, zScore: 0, side: .long, action: .exit),
        ]
        let (_, summary) = SpreadBacktester.run(signals: sigs)
        #expect(summary.totalTrades == 2)
        #expect(summary.wins == 1)
        #expect(summary.losses == 1)
        #expect(summary.winRate == 0.5)
        #expect(summary.totalPnL == 10)  // +30 - 20
    }

    @Test("回测 · maxDrawdown 正确捕捉 peak→trough")
    func backtestMaxDrawdown() {
        // 3 笔：+100, -50, +20 → 累积 [0, 100, 50, 70] · maxDD = 50（100→50）
        let sigs: [SpreadSignal] = [
            SpreadSignal(index: 0, openTime: Date(), value: 0, zScore: -2.5,
                        side: .long, action: .entry),
            SpreadSignal(index: 10, openTime: Date().addingTimeInterval(600),
                        value: 100, zScore: 0, side: .long, action: .exit),
            SpreadSignal(index: 20, openTime: Date().addingTimeInterval(1200),
                        value: 100, zScore: -2.5, side: .long, action: .entry),
            SpreadSignal(index: 30, openTime: Date().addingTimeInterval(1800),
                        value: 50, zScore: 0, side: .long, action: .exit),
            SpreadSignal(index: 40, openTime: Date().addingTimeInterval(2400),
                        value: 50, zScore: -2.5, side: .long, action: .entry),
            SpreadSignal(index: 50, openTime: Date().addingTimeInterval(3000),
                        value: 70, zScore: 0, side: .long, action: .exit),
        ]
        let (_, summary) = SpreadBacktester.run(signals: sigs)
        #expect(summary.maxDrawdown == 50)
        #expect(summary.cumulativePnL == [0, 100, 50, 70])
    }

    @Test("回测 · 平均持仓周期正确")
    func backtestAvgHolding() {
        let sigs: [SpreadSignal] = [
            SpreadSignal(index: 0, openTime: Date(), value: 100, zScore: -2.5,
                        side: .long, action: .entry),
            SpreadSignal(index: 5, openTime: Date().addingTimeInterval(300),
                        value: 110, zScore: 0, side: .long, action: .exit),
            SpreadSignal(index: 10, openTime: Date().addingTimeInterval(600),
                        value: 100, zScore: -2.5, side: .long, action: .entry),
            SpreadSignal(index: 25, openTime: Date().addingTimeInterval(1500),
                        value: 110, zScore: 0, side: .long, action: .exit),
        ]
        let (_, summary) = SpreadBacktester.run(signals: sigs)
        // 持仓 5 + 15 = 20 / 2 = 10
        #expect(summary.avgHoldingBars == 10)
    }
}
