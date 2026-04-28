// WP-41 · ATR · 真实波幅均值（波动率类）· Wilder 方法
// 参数：period（14）
// 公式：
//   TR(i) = max(high(i)-low(i), |high(i)-close(i-1)|, |low(i)-close(i-1)|)
//   ATR  = Wilder(TR, N)
//
// WP-41 v3 commit 3/4：ATR 实现 IncrementalIndicator · Wilder 平滑 O(1) per step（同 RSI 模式）

import Foundation
import Shared

public enum ATR: Indicator {
    public static let identifier = "ATR"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard let first = params.first else {
            throw IndicatorError.invalidParameter("缺少 period 参数")
        }
        let n = intValue(first)
        guard n >= 1 else {
            throw IndicatorError.invalidParameter("ATR period 必须 >= 1，实际 \(n)")
        }

        let highs = kline.highs
        let lows = kline.lows
        let closes = kline.closes
        let count = closes.count

        var tr = [Decimal](repeating: 0, count: count)
        // 第 0 根 TR = high - low（无 prevClose）
        if count > 0 { tr[0] = highs[0] - lows[0] }
        for i in 1..<count {
            let hl = highs[i] - lows[i]
            // Decimal 通过 SignedNumeric 支持 Swift.abs，无需自定义辅助
            let hc = abs(highs[i] - closes[i - 1])
            let lc = abs(lows[i] - closes[i - 1])
            tr[i] = max(hl, max(hc, lc))
        }

        let atr = Kernels.wilder(tr, period: n)
        return [IndicatorSeries(name: "ATR(\(n))", values: atr)]
    }
}

// MARK: - WP-41 v3 commit 3/4 · ATR 增量 API

extension ATR: IncrementalIndicator {

    /// state：n + Wilder 系数（n / n-1）+ prevClose（TR 计算用 · 第一根 nil）
    /// + warmUpSum（前 n 个 TR 累加 · 第 n 步用作 seed）+ count + atr（流式未 round · 输出 round8）
    public struct IncrementalState: Sendable {
        public let period: Int
        public let nDec: Decimal
        public let nMinus1: Decimal
        public var prevClose: Decimal?
        public var warmUpSum: Decimal
        public var count: Int
        public var atr: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "ATR period")
        var state = IncrementalState(
            period: n, nDec: Decimal(n), nMinus1: Decimal(n - 1),
            prevClose: nil,
            warmUpSum: 0,
            count: 0,
            atr: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)]
    }

    /// makeIncrementalState 与 stepIncremental 共享的核心：
    /// - 第 1 根：prevClose 为 nil → TR = high - low（与 calculate tr[0] 语义一致）· 之后 prevClose = close
    /// - 第 2..n-1 根：累加 warmUpSum · 返回 nil
    /// - 第 n 根：累加 + atr = warmUpSum / n（seed · 与 wilder 内部 seedSum/nDec 一致）· 返回首个 ATR
    /// - 第 n+1 根起：Wilder 平滑 atr = (atr*(n-1) + tr) / n · 返回 ATR
    /// - state.atr 是流式未 round（与 Kernels.wilder 内部 prev 一致）· 输出 round8
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> Decimal? {
        let tr: Decimal
        if let pc = state.prevClose {
            let hl = high - low
            let hc = abs(high - pc)
            let lc = abs(low - pc)
            tr = max(hl, max(hc, lc))
        } else {
            tr = high - low
        }
        state.prevClose = close
        state.count += 1

        if state.count < state.period {
            state.warmUpSum += tr
            return nil
        }
        if state.count == state.period {
            state.warmUpSum += tr
            state.atr = state.warmUpSum / state.nDec
        } else {
            state.atr = (state.atr * state.nMinus1 + tr) / state.nDec
        }
        return Kernels.round8(state.atr)
    }
}
