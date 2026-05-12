// v17.47 D2 v2.3 · short-side 双向回测单测

import Testing
import Foundation
@testable import IndicatorCore

private func mkBar(_ close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close,
            volume: 100, amount: 0, openInterest: 0, timestamp: nil)
}

@Suite("BacktestTrade · direction · v17.47 D2 v2.3")
struct BacktestTradeDirectionTests {

    @Test("default direction = .long · 与 v1 兼容")
    func defaultLong() {
        let t = BacktestTrade(entryBarIndex: 0, entryPrice: 100,
                              exitBarIndex: 1, exitPrice: 110)
        #expect(t.direction == .long)
        #expect(t.pnl == 10)
        #expect(t.isWin == true)
    }

    @Test("short direction · pnl = entry - exit")
    func shortPnL() {
        let t = BacktestTrade(entryBarIndex: 0, entryPrice: 100,
                              exitBarIndex: 1, exitPrice: 90,
                              direction: .short)
        #expect(t.pnl == 10)        // 卖高 100 买低 90 · 赚 10
        #expect(t.isWin == true)
    }

    @Test("short direction 反亏 · entry < exit → 负 PnL")
    func shortLoss() {
        let t = BacktestTrade(entryBarIndex: 0, entryPrice: 100,
                              exitBarIndex: 1, exitPrice: 110,
                              direction: .short)
        #expect(t.pnl == -10)
        #expect(t.isWin == false)
    }

    @Test("pnlPercent · short 也按 entry 归一化")
    func shortPnLPercent() {
        let t = BacktestTrade(entryBarIndex: 0, entryPrice: 100,
                              exitBarIndex: 1, exitPrice: 90,
                              direction: .short)
        #expect(t.pnlPercent == Decimal(string: "0.1")!)
    }
}

@Suite("SimpleBacktestEngine · short-side · v17.47 D2 v2.3")
struct ShortSideEngineTests {

    @Test("allowShort=false（默认）· 负信号忽略 · 同 v1 long-only")
    func defaultLongOnly() {
        let bars = [mkBar(100), mkBar(90), mkBar(80)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1, -1], bars: bars, initialEquity: 100_000)
        #expect(r.trades.isEmpty)   // 负信号被忽略
        #expect(r.endingPnL == 0)
    }

    @Test("allowShort=true · 负信号开空 · 跌价盈利")
    func shortOnDownward() {
        let bars = [mkBar(100), mkBar(90), mkBar(80)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1, -1], bars: bars,
            initialEquity: 100_000, allowShort: true)
        #expect(r.trades.count == 1)
        #expect(r.trades[0].direction == .short)
        #expect(r.trades[0].entryPrice == 100)
        #expect(r.trades[0].exitPrice == 80)
        #expect(r.endingPnL == 20)   // 卖 100 买 80 · 赚 20
    }

    @Test("反手：多 → 空 自动反向（无中间空仓）")
    func flipLongToShort() {
        // 100 → 110（长） · 105（信号变 -1 反手）· 95（空一直持有）
        let bars = [mkBar(100), mkBar(110), mkBar(105), mkBar(95)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1, -1, -1], bars: bars,
            initialEquity: 100_000, allowShort: true)
        #expect(r.trades.count == 2)
        #expect(r.trades[0].direction == .long)
        #expect(r.trades[0].entryPrice == 100)
        #expect(r.trades[0].exitPrice == 105)
        #expect(r.trades[0].pnl == 5)
        #expect(r.trades[1].direction == .short)
        #expect(r.trades[1].entryPrice == 105)
        #expect(r.trades[1].exitPrice == 95)
        #expect(r.trades[1].pnl == 10)
        #expect(r.endingPnL == 15)
    }

    @Test("反手：空 → 多 自动反向")
    func flipShortToLong() {
        let bars = [mkBar(100), mkBar(90), mkBar(95), mkBar(110)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1, 1, 1], bars: bars,
            initialEquity: 100_000, allowShort: true)
        #expect(r.trades.count == 2)
        #expect(r.trades[0].direction == .short)
        #expect(r.trades[0].pnl == 5)   // 100 → 95
        #expect(r.trades[1].direction == .long)
        #expect(r.trades[1].pnl == 15)  // 95 → 110
        #expect(r.endingPnL == 20)
    }

    @Test("short + commission + slippage 复合（空头 slippage 不利方向相反）")
    func shortWithCosts() {
        // slip=1 · 空头开仓 entry=close-slip · 平仓 exit=close+slip · pnl=(entry-exit)
        // bars 100 → 90 · entry=99 · exit=91 · pnl=8 · -commission 3 = 5
        let bars = [mkBar(100), mkBar(90)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1], bars: bars,
            initialEquity: 100_000,
            commission: 3, slippage: 1, allowShort: true)
        #expect(r.trades.count == 1)
        #expect(r.trades[0].entryPrice == 99)
        #expect(r.trades[0].exitPrice == 91)
        #expect(r.trades[0].pnl == 8)
        #expect(r.endingPnL == 5)
    }

    @Test("空 + 0 信号 · 平仓不反开")
    func shortToFlat() {
        let bars = [mkBar(100), mkBar(90), mkBar(85), mkBar(85)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1, 0, 0], bars: bars,
            initialEquity: 100_000, allowShort: true)
        #expect(r.trades.count == 1)
        #expect(r.trades[0].direction == .short)
        #expect(r.trades[0].pnl == 15)   // 100 → 85
        #expect(r.endingPnL == 15)
    }

    @Test("末尾空仓持仓 · 强平含 slippage + commission")
    func shortEndOfBarsExit() {
        let bars = [mkBar(100), mkBar(90)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [-1, -1], bars: bars,
            initialEquity: 100_000,
            commission: 0, slippage: 0, allowShort: true)
        // 末尾强平 · close=90 · 空头 pnl=10
        #expect(r.trades.count == 1)
        #expect(r.endingPnL == 10)
    }
}
