// v17.51 D2 v2.4 · MonteCarloRunner 单测

import Testing
import Foundation
@testable import IndicatorCore

private func mkBar(_ close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close,
            volume: 100, amount: 0, openInterest: 0, timestamp: nil)
}

private func mkResult(endingPnL: Double, initialEquity: Decimal = 100_000) -> BacktestResult {
    BacktestResult(trades: [], equityCurve: [],
                   endingPnL: Decimal(endingPnL), maxDrawdown: 0,
                   sharpe: 0, sortino: 0, calmar: 0,
                   winRate: 0, expectancy: 0,
                   initialEquity: initialEquity)
}

@Suite("MonteCarloRunner · makeResult 统计 · v17.51 D2 v2.4")
struct MonteCarloMakeResultTests {

    @Test("空 runs · 所有 stats = 0")
    func emptyRuns() {
        let r = MonteCarloRunner.makeResult(runs: [])
        #expect(r.runs.isEmpty)
        #expect(r.avgPnL == 0)
        #expect(r.stdPnL == 0)
        #expect(r.profitableRatio == 0)
        #expect(r.medianPnL == 0)
    }

    @Test("单 run · stats 收敛到该 run 的值（std=0）")
    func singleRun() {
        let r = MonteCarloRunner.makeResult(runs: [mkResult(endingPnL: 1000)])
        #expect(r.avgPnL == 1000)
        #expect(r.stdPnL == 0)
        #expect(r.minPnL == 1000)
        #expect(r.maxPnL == 1000)
        #expect(r.medianPnL == 1000)
        #expect(r.p5PnL == 1000)
        #expect(r.p95PnL == 1000)
        #expect(r.profitableRatio == 1.0)
    }

    @Test("5 runs · 1,2,3,4,5 · avg=3 · median=3 · profitable=100%")
    func fiveRunsBasic() {
        let runs = [1.0, 2.0, 3.0, 4.0, 5.0].map { mkResult(endingPnL: $0) }
        let r = MonteCarloRunner.makeResult(runs: runs)
        #expect(r.avgPnL == 3.0)
        #expect(r.minPnL == 1.0)
        #expect(r.maxPnL == 5.0)
        #expect(r.medianPnL == 3.0)
        #expect(r.profitableRatio == 1.0)
        // std: variance = ((1-3)² + (2-3)² + ... + (5-3)²)/5 = (4+1+0+1+4)/5 = 2 · std=√2≈1.414
        #expect(abs(r.stdPnL - 2.0.squareRoot()) < 1e-9)
    }

    @Test("含负 run · profitableRatio 反映正占比")
    func mixedSign() {
        let runs = [-100.0, -50.0, 0.0, 50.0, 100.0].map { mkResult(endingPnL: $0) }
        let r = MonteCarloRunner.makeResult(runs: runs)
        #expect(r.avgPnL == 0)
        // 0 不算 profitable · 2/5
        #expect(r.profitableRatio == 0.4)
    }

    @Test("p5 / p95 线性插值（10 个 run · 等距）")
    func percentileLinearInterp() {
        let runs = (1...10).map { mkResult(endingPnL: Double($0 * 10)) }
        let r = MonteCarloRunner.makeResult(runs: runs)
        // sorted [10, 20, 30, ..., 100]
        // p5 = 0.05 * 9 = 0.45 → 10 + 0.45 * (20-10) = 14.5
        #expect(abs(r.p5PnL - 14.5) < 1e-9)
        // p95 = 0.95 * 9 = 8.55 → 90 + 0.55 * (100-90) = 95.5
        #expect(abs(r.p95PnL - 95.5) < 1e-9)
        // median = 0.5 * 9 = 4.5 → 50 + 0.5 * (60-50) = 55
        #expect(abs(r.medianPnL - 55) < 1e-9)
    }
}

@Suite("MonteCarloRunner · run 端到端（与 SimpleBacktestEngine 联动）· v17.51")
struct MonteCarloRunEndToEndTests {

    @Test("空 seeds · 返空")
    func emptySeeds() throws {
        var lexer = Lexer(source: "BUY:1;")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let r = MonteCarloRunner.run(formula: formula, seeds: [],
                                      barsForSeed: { _ in [] })
        #expect(r.runs.isEmpty)
    }

    @Test("3 seeds · 不同 bars · 3 个独立 run")
    func threeSeeds() throws {
        var lexer = Lexer(source: "BUY:1;")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let r = MonteCarloRunner.run(
            formula: formula, seeds: [1, 2, 3],
            barsForSeed: { seed in
                // seed=1 → 涨 10 · seed=2 → 涨 20 · seed=3 → 涨 30
                [mkBar(100), mkBar(Decimal(100 + seed * 10))]
            })
        #expect(r.runs.count == 3)
        // 3 run pnl: 10, 20, 30 · avg=20 · profitable=100%
        #expect(r.avgPnL == 20)
        #expect(r.profitableRatio == 1.0)
    }

    @Test("空 bars seed · 跳过（不计入 stats）")
    func skipEmptyBars() throws {
        var lexer = Lexer(source: "BUY:1;")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let r = MonteCarloRunner.run(
            formula: formula, seeds: [1, 2, 3],
            barsForSeed: { seed in
                seed == 2 ? [] : [mkBar(100), mkBar(110)]
            })
        // seed=2 空 bars 跳过 · 仅 2 run
        #expect(r.runs.count == 2)
    }
}
