// v17.83 D4 v3 · MultiAssetMultiPeriodBacktest 单测

import Testing
import Foundation
@testable import IndicatorCore

private func bar(_ close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close, volume: 100,
            amount: 0, openInterest: 0, timestamp: nil)
}

private func uptrend(_ n: Int, start: Decimal = 100, step: Decimal = 1) -> [BarData] {
    (0..<n).map { i in bar(start + Decimal(i) * step) }
}

private func sideways(_ n: Int, around: Decimal = 100) -> [BarData] {
    (0..<n).map { i in bar(around + (i % 2 == 0 ? 1 : -1)) }
}

private func downtrend(_ n: Int, start: Decimal = 200, step: Decimal = 1) -> [BarData] {
    (0..<n).map { i in bar(start - Decimal(i) * step) }
}

private func parseFormula(_ src: String) throws -> Formula {
    var lexer = Lexer(source: src)
    let tokens = try lexer.tokenize()
    var parser = Parser(tokens: tokens)
    return try parser.parse()
}

@Suite("MultiAssetMultiPeriodBacktest · v17.83 D4 v3 多品种多周期")
struct MultiAssetMultiPeriodBacktestTests {

    @Test("空 cells · 返回空 outcomes + 0 鲁棒性")
    func emptyCells() throws {
        let formula = try parseFormula("BUY: 1;")
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: [])
        #expect(r.outcomes.isEmpty)
        #expect(r.inputCellCount == 0)
        #expect(r.failedCellCount == 0)
        #expect(r.robustness.cellCount == 0)
        #expect(r.robustness.positiveCellCount == 0)
        #expect(r.robustness.bestCell == nil)
        #expect(r.robustness.worstCell == nil)
    }

    @Test("单 cell · uptrend 全程持仓 · pnl > 0")
    func singleCellUptrend() throws {
        // 公式：BUY: 1; → 全程持仓信号
        let formula = try parseFormula("BUY: 1;")
        let cells = [BacktestCell(symbol: "rb2510", periodLabel: "5m", bars: uptrend(10))]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        #expect(r.outcomes.count == 1)
        #expect(r.failedCellCount == 0)
        let first = r.outcomes[0]
        #expect(first.symbol == "rb2510")
        #expect(first.periodLabel == "5m")
        #expect(first.result.endingPnL > 0)
        #expect(r.robustness.positiveRate == 1.0)
        #expect(r.robustness.bestCell?.symbol == "rb2510")
        #expect(r.robustness.worstCell?.symbol == "rb2510")
    }

    @Test("多 cell 全 uptrend · 全部 positive · positive rate 1.0")
    func allPositive() throws {
        let formula = try parseFormula("BUY: 1;")
        let cells = [
            BacktestCell(symbol: "rb2510", periodLabel: "5m",  bars: uptrend(10, start: 100, step: 1)),
            BacktestCell(symbol: "rb2510", periodLabel: "1H",  bars: uptrend(10, start: 100, step: 2)),
            BacktestCell(symbol: "i2510",  periodLabel: "5m",  bars: uptrend(10, start: 800, step: 3)),
            BacktestCell(symbol: "i2510",  periodLabel: "1H",  bars: uptrend(10, start: 800, step: 4)),
        ]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        #expect(r.outcomes.count == 4)
        #expect(r.robustness.positiveCellCount == 4)
        #expect(r.robustness.positiveRate == 1.0)
        #expect(r.robustness.avgEndingPnL > 0)
        // outcomes 按 endingPnL desc 排序 · best 应是 step 最大的
        #expect(r.robustness.bestCell?.periodLabel == "1H")
    }

    @Test("混合 cell · uptrend 赚 / downtrend long-only 亏 · positive rate < 1")
    func mixedScenarios() throws {
        let formula = try parseFormula("BUY: 1;")
        let cells = [
            BacktestCell(symbol: "rb2510", periodLabel: "5m", bars: uptrend(10)),
            BacktestCell(symbol: "rb2510", periodLabel: "1H", bars: downtrend(10)),
            BacktestCell(symbol: "i2510",  periodLabel: "5m", bars: uptrend(10)),
            BacktestCell(symbol: "i2510",  periodLabel: "1H", bars: downtrend(10)),
        ]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        #expect(r.outcomes.count == 4)
        #expect(r.robustness.positiveCellCount == 2)
        #expect(r.robustness.positiveRate == 0.5)
        // best = uptrend cell · worst = downtrend cell
        #expect(r.robustness.bestCell?.result.endingPnL ?? 0 > 0)
        #expect(r.robustness.worstCell?.result.endingPnL ?? 0 < 0)
    }

    @Test("空 bars cell 静默跳过 · 不计入 outcomes")
    func emptyBarsCellSkipped() throws {
        let formula = try parseFormula("BUY: 1;")
        let cells = [
            BacktestCell(symbol: "rb2510", periodLabel: "5m", bars: uptrend(10)),
            BacktestCell(symbol: "empty",  periodLabel: "1H", bars: []),
            BacktestCell(symbol: "i2510",  periodLabel: "5m", bars: uptrend(10)),
        ]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        #expect(r.outcomes.count == 2)
        #expect(r.inputCellCount == 3)
        #expect(r.failedCellCount == 1)
    }

    @Test("totalTradeCount = 各 cell trade 累加")
    func totalTradesAggregated() throws {
        // BUY: 1; → 每 cell 1 trade（开头开 + 末尾强平）
        let formula = try parseFormula("BUY: 1;")
        let cells = [
            BacktestCell(symbol: "a", periodLabel: "5m", bars: uptrend(5)),
            BacktestCell(symbol: "b", periodLabel: "5m", bars: uptrend(5)),
            BacktestCell(symbol: "c", periodLabel: "5m", bars: uptrend(5)),
        ]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        #expect(r.robustness.totalTradeCount == 3)
    }

    @Test("avgWinRate 跨 cell 平均")
    func avgWinRate() throws {
        let formula = try parseFormula("BUY: 1;")
        let cells = [
            BacktestCell(symbol: "win",  periodLabel: "5m", bars: uptrend(5)),
            BacktestCell(symbol: "loss", periodLabel: "5m", bars: downtrend(5)),
        ]
        let r = MultiAssetMultiPeriodBacktest.run(formula: formula, cells: cells)
        // win cell winRate=1 · loss cell winRate=0 → avg=0.5
        #expect(abs(r.robustness.avgWinRate - 0.5) < 1e-9)
    }
}
