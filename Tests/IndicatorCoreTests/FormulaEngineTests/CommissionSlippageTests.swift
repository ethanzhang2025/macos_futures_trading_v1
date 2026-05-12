// v17.46 D2 v2.2 · commission + slippage 单测

import Testing
import Foundation
@testable import IndicatorCore

private func mkBar(_ close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close,
            volume: 100, amount: 0, openInterest: 0, timestamp: nil)
}

@Suite("SimpleBacktestEngine · commission + slippage · v17.46 D2 v2.2")
struct CommissionSlippageTests {

    @Test("commission=0 + slippage=0 · 行为与 v1 完全一致（兼容）")
    func zeroCostMatchesV1() {
        let bars = [mkBar(100), mkBar(110), mkBar(120)]
        let r1 = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1], bars: bars, initialEquity: 100_000)
        let r2 = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1, 1], bars: bars,
            initialEquity: 100_000, commission: 0, slippage: 0)
        #expect(r1.endingPnL == r2.endingPnL)
        #expect(r1.trades == r2.trades)
    }

    @Test("commission=5/笔 · 单 trade 末平 · endingPnL -= 5")
    func commissionSingleTrade() {
        let bars = [mkBar(100), mkBar(110)]
        let withFee = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1], bars: bars,
            initialEquity: 100_000, commission: 5, slippage: 0)
        // 末根强平 · 不收第二次 · pnl = 110-100 = 10 · 减 commission 5 = 5
        #expect(withFee.endingPnL == 5)
        #expect(withFee.trades.count == 1)
    }

    @Test("commission · 多 trade · 累加扣减")
    func commissionMultipleTrades() {
        // 信号 [1,0,1,0] · 2 个完整 trade · 每个扣 commission=5 · 总 commission=10
        let bars = [mkBar(100), mkBar(110), mkBar(105), mkBar(115)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [1, 0, 1, 0], bars: bars,
            initialEquity: 100_000, commission: 5, slippage: 0)
        #expect(r.trades.count == 2)
        // trade1: 100→110 pnl=10 · trade2: 105→115 pnl=10 · total 20 - 10 commission = 10
        #expect(r.endingPnL == 10)
    }

    @Test("slippage · 开仓 +slip · 平仓 -slip · 双重不利")
    func slippageEffect() {
        let bars = [mkBar(100), mkBar(110)]
        // slippage=2 · entry=100+2=102 · exit=110-2=108 · pnl=6（vs 无 slip 时 10）
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1], bars: bars,
            initialEquity: 100_000, commission: 0, slippage: 2)
        #expect(r.endingPnL == 6)
        #expect(r.trades.first?.entryPrice == 102)
        #expect(r.trades.first?.exitPrice == 108)
    }

    @Test("commission + slippage · 复合效果")
    func compositeEffect() {
        let bars = [mkBar(100), mkBar(110)]
        // entry=101 · exit=109 · pnl=8 · -commission=3 → ending=5
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1], bars: bars,
            initialEquity: 100_000, commission: 3, slippage: 1)
        #expect(r.endingPnL == 5)
    }

    @Test("高 slippage 反转盈亏 · 原本盈利 → 反亏（trader 警示）")
    func highSlippageFlipsWinner() {
        // 盈 10 但 slip=8 · pnl=10-16=-6
        let bars = [mkBar(100), mkBar(110)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [1, 1], bars: bars,
            initialEquity: 100_000, commission: 0, slippage: 8)
        #expect(r.endingPnL == -6)
        #expect(r.winRate == 0)   // 不再盈利
    }

    @Test("无 trade · commission/slippage 都不扣（无成交）")
    func noTradeNoCost() {
        let bars = [mkBar(100), mkBar(110)]
        let r = SimpleBacktestEngine.runWithSignal(
            signal: [0, 0], bars: bars,
            initialEquity: 100_000, commission: 100, slippage: 50)
        #expect(r.endingPnL == 0)
        #expect(r.trades.isEmpty)
    }
}
