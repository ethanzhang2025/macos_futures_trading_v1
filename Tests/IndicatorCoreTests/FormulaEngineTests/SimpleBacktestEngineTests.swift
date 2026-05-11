// v17.37 D1/D2 · SimpleBacktestEngine 单测

import Testing
import Foundation
@testable import IndicatorCore

private func bar(close: Decimal, open: Decimal? = nil, high: Decimal? = nil, low: Decimal? = nil) -> BarData {
    BarData(
        open: open ?? close,
        high: high ?? close,
        low: low ?? close,
        close: close,
        volume: 100,
        amount: 0,
        openInterest: 0,
        timestamp: nil
    )
}

@Suite("SimpleBacktestEngine · v17.37 D1/D2 公式回测 v1")
struct SimpleBacktestEngineTests {

    @Test("空 bars · 返回空结果")
    func emptyBars() {
        let result = SimpleBacktestEngine.runWithSignal(signal: [], bars: [], initialEquity: 100_000)
        #expect(result.trades.isEmpty)
        #expect(result.equityCurve.isEmpty)
        #expect(result.endingPnL == 0)
        #expect(result.initialEquity == 100_000)
    }

    @Test("信号全 0 · 不开仓 · equity 不变")
    func noSignalNoTrade() {
        let bars = [bar(close: 100), bar(close: 105), bar(close: 110)]
        let signal: [Decimal?] = [0, 0, 0]
        let r = SimpleBacktestEngine.runWithSignal(signal: signal, bars: bars, initialEquity: 100_000)
        #expect(r.trades.isEmpty)
        #expect(r.equityCurve == [100_000, 100_000, 100_000])
        #expect(r.endingPnL == 0)
    }

    @Test("buy-and-hold · 单次开仓 + 末根强平 · 累计 PnL")
    func buyAndHold() {
        let bars = [bar(close: 100), bar(close: 110), bar(close: 120)]
        let signal: [Decimal?] = [1, 1, 1]
        let r = SimpleBacktestEngine.runWithSignal(signal: signal, bars: bars, initialEquity: 100_000)
        #expect(r.trades.count == 1)
        #expect(r.trades[0].entryPrice == 100)
        #expect(r.trades[0].exitPrice == 120)
        #expect(r.trades[0].pnl == 20)
        #expect(r.endingPnL == 20)
        // equity 曲线（持仓 MTM）：100000 / 100010 / 100020
        #expect(r.equityCurve == [100_000, 100_010, 100_020])
    }

    @Test("信号穿越 · 开 → 平 → 再开 · 多 trade")
    func multipleTrades() {
        let bars = [
            bar(close: 100), bar(close: 110),   // 开 100 · 持仓
            bar(close: 105),                     // 信号转 0 · 本根 close 平 → trade1 pnl=5
            bar(close: 102), bar(close: 120)    // 102 重新开仓 · 末根 120 强平 → trade2 pnl=18
        ]
        let signal: [Decimal?] = [1, 1, 0, 1, 1]
        let r = SimpleBacktestEngine.runWithSignal(signal: signal, bars: bars, initialEquity: 100_000)
        #expect(r.trades.count == 2)
        #expect(r.trades[0].entryPrice == 100 && r.trades[0].exitPrice == 105)
        #expect(r.trades[1].entryPrice == 102 && r.trades[1].exitPrice == 120)
        #expect(r.endingPnL == 23)   // 5 + 18
        #expect(r.winRate == 1.0)    // 2/2 全胜
    }

    @Test("胜率 · 50% · 一胜一负")
    func winRate50() {
        let bars = [
            bar(close: 100), bar(close: 90),    // -10
            bar(close: 95),                      // signal 0 · 平
            bar(close: 100), bar(close: 120)    // +20 强平
        ]
        let signal: [Decimal?] = [1, 1, 0, 1, 1]
        let r = SimpleBacktestEngine.runWithSignal(signal: signal, bars: bars, initialEquity: 100_000)
        #expect(r.trades.count == 2)
        #expect(r.winRate == 0.5)
        // trade1 pnl = 95 - 100 = -5（输）· trade2 pnl = 120 - 100 = 20（赢）
        #expect(r.endingPnL == 15)
        #expect(r.expectancy == Decimal(15) / Decimal(2))   // 7.5
    }

    @Test("maxDrawdown · 峰谷差")
    func maxDrawdown() {
        // 持仓全程 · close 100 → 120 → 90 → 110
        let bars = [bar(close: 100), bar(close: 120), bar(close: 90), bar(close: 110)]
        let signal: [Decimal?] = [1, 1, 1, 1]
        let r = SimpleBacktestEngine.runWithSignal(signal: signal, bars: bars, initialEquity: 100_000)
        // equity 曲线：100000 / 100020 / 99990(峰) / 100010
        // peak = 100020 · valley = 99990 · DD = 30
        #expect(r.maxDrawdown == 30)
    }

    @Test("Sharpe · 单调上涨 std=0 → 0（避 NaN）· 波动序列 > 0")
    func sharpeEdgeCases() {
        // case 1：单调上涨 · returns 都相同 · std≈0
        let monoBars = [bar(close: 100), bar(close: 110), bar(close: 120)]
        let r1 = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1], bars: monoBars, initialEquity: 100_000)
        // 每根 +10 · std=0 → sharpe=0（避 NaN）
        #expect(r1.sharpe == 0)

        // case 2：起伏 returns（10, -5, 15）· sharpe > 0
        let voltBars = [bar(close: 100), bar(close: 110), bar(close: 105), bar(close: 120)]
        let r2 = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1, 1], bars: voltBars, initialEquity: 100_000)
        #expect(r2.sharpe > 0)
    }

    @Test("trade.isWin / pnlPercent 正确")
    func tradeMetrics() {
        let win = BacktestTrade(entryBarIndex: 0, entryPrice: 100, exitBarIndex: 5, exitPrice: 120)
        #expect(win.pnl == 20)
        #expect(win.isWin)
        #expect(win.pnlPercent == Decimal(20) / Decimal(100))

        let loss = BacktestTrade(entryBarIndex: 0, entryPrice: 100, exitBarIndex: 5, exitPrice: 80)
        #expect(loss.pnl == -20)
        #expect(!loss.isWin)
    }

    @Test("formula 路径 · 找不到信号名抛错")
    func formulaSignalNotFound() throws {
        // 极简 formula："X: CLOSE;" 没有 BUY 输出 · 信号查找失败 → throw
        var lexer = Lexer(source: "X: CLOSE;")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let bars = [bar(close: 100), bar(close: 110)]
        #expect(throws: InterpreterError.self) {
            _ = try SimpleBacktestEngine.run(formula: formula, bars: bars, signalLineName: "BUY")
        }
    }

    @Test("formula 路径 · BUY: CLOSE > REF(CLOSE, 1) · 简易突破 · 端到端")
    func formulaEndToEnd() throws {
        // BUY 信号 = 当前 close > 前一根 close（突破上一根高）· REF 第一根回 nil → 0/false
        var lexer = Lexer(source: "BUY: IF(CLOSE > REF(CLOSE, 1), 1, 0);")
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let bars = [bar(close: 100), bar(close: 110), bar(close: 105), bar(close: 115)]
        let r = try SimpleBacktestEngine.run(formula: formula, bars: bars, signalLineName: "BUY")
        // 至少有交易（具体路径细节由 interpreter 决定 · 此测仅确保 end-to-end 不抛）
        #expect(r.equityCurve.count == bars.count)
    }
}
