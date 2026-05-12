// v17.124 · ChartTheme mode-aware PnL/candle 颜色单测（P2-1 deep review 收口）
//
// 防主题改造时静默改错配色方向：
// - PnL profit/loss 跟 K 线 candle 涨/跌一致（trader 直觉）
// - redUpGreenDown（中国）：涨红 = 赚 · 跌绿 = 亏
// - greenUpRedDown（国际）：涨绿 = 赚 · 跌红 = 亏
//
// Linux 端 SwiftUI 不可用 · 整个 file #if os(macOS) 守卫 · target 空跑 · macOS 实跑

#if canImport(SwiftUI) && os(macOS)

import Testing
import SwiftUI
@testable import MainApp
import Shared

@Suite("ChartTheme · v17.124 mode-aware PnL/candle 配色")
struct ChartThemeColorTests {

    // MARK: - chartProfit / chartLoss（PnL 跟 candle 一致）

    @Test("中国习惯：profit = 红 / loss = 绿")
    func profitLossRedUpMode() {
        #expect(ChartTheme.chartProfitColor(mode: .redUpGreenDown) == Color.red)
        #expect(ChartTheme.chartLossColor(mode: .redUpGreenDown) == Color.green)
    }

    @Test("国际习惯：profit = 绿 / loss = 红")
    func profitLossGreenUpMode() {
        #expect(ChartTheme.chartProfitColor(mode: .greenUpRedDown) == Color.green)
        #expect(ChartTheme.chartLossColor(mode: .greenUpRedDown) == Color.red)
    }

    @Test("两 mode profit/loss 互为反色")
    func profitLossSymmetric() {
        #expect(ChartTheme.chartProfitColor(mode: .redUpGreenDown) == ChartTheme.chartLossColor(mode: .greenUpRedDown))
        #expect(ChartTheme.chartLossColor(mode: .redUpGreenDown) == ChartTheme.chartProfitColor(mode: .greenUpRedDown))
    }

    // MARK: - Emphasized（hover 高亮 · 0.85 alpha）

    @Test("Emphasized = 基础色 + 0.85 alpha · redUp")
    func emphasizedRedUpMode() {
        #expect(ChartTheme.chartProfitEmphasizedColor(mode: .redUpGreenDown) == Color.red.opacity(0.85))
        #expect(ChartTheme.chartLossEmphasizedColor(mode: .redUpGreenDown) == Color.green.opacity(0.85))
    }

    @Test("Emphasized = 基础色 + 0.85 alpha · greenUp")
    func emphasizedGreenUpMode() {
        #expect(ChartTheme.chartProfitEmphasizedColor(mode: .greenUpRedDown) == Color.green.opacity(0.85))
        #expect(ChartTheme.chartLossEmphasizedColor(mode: .greenUpRedDown) == Color.red.opacity(0.85))
    }

    // MARK: - candleUp / candleDown（instance method · 用 candleBull/Bear 实体色）

    @Test("candleUp · redUp = bull / greenUp = bear")
    func candleUpSwap() {
        let dark = ChartTheme.dark
        #expect(dark.candleUp(mode: .redUpGreenDown) == dark.candleBull)
        #expect(dark.candleUp(mode: .greenUpRedDown) == dark.candleBear)
        let light = ChartTheme.light
        #expect(light.candleUp(mode: .redUpGreenDown) == light.candleBull)
        #expect(light.candleUp(mode: .greenUpRedDown) == light.candleBear)
    }

    @Test("candleDown · redUp = bear / greenUp = bull")
    func candleDownSwap() {
        let dark = ChartTheme.dark
        #expect(dark.candleDown(mode: .redUpGreenDown) == dark.candleBear)
        #expect(dark.candleDown(mode: .greenUpRedDown) == dark.candleBull)
        let light = ChartTheme.light
        #expect(light.candleDown(mode: .redUpGreenDown) == light.candleBear)
        #expect(light.candleDown(mode: .greenUpRedDown) == light.candleBull)
    }

    @Test("candleUp/Down 两 mode 互为反色")
    func candleSymmetric() {
        let dark = ChartTheme.dark
        #expect(dark.candleUp(mode: .redUpGreenDown) == dark.candleDown(mode: .greenUpRedDown))
        #expect(dark.candleDown(mode: .redUpGreenDown) == dark.candleUp(mode: .greenUpRedDown))
    }

    // MARK: - PnL × candle 方向一致性（核心 trader 直觉）

    @Test("PnL profit 方向 == candle 涨色（两 mode 都成立）")
    func pnlMatchesCandle() {
        // redUp：涨红 ↔ 赚红
        let dark = ChartTheme.dark
        #expect(ChartTheme.chartProfitColor(mode: .redUpGreenDown) == Color.red)
        #expect(dark.candleUp(mode: .redUpGreenDown) == dark.candleBull)   // bull = 中国红主色
        // greenUp：涨绿 ↔ 赚绿
        #expect(ChartTheme.chartProfitColor(mode: .greenUpRedDown) == Color.green)
        #expect(dark.candleUp(mode: .greenUpRedDown) == dark.candleBear)   // bear = 中国绿主色（被 swap 成涨色）
    }
}

#endif
