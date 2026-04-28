// WP-41 · RSI · 相对强弱指数（震荡类）· Wilder 经典方法
// 参数：period（默认 14）
// 公式：
//   U(i) = max(close(i) - close(i-1), 0)
//   D(i) = max(close(i-1) - close(i), 0)
//   AvgU = Wilder(U, N) / AvgD = Wilder(D, N)
//   RSI = 100 * AvgU / (AvgU + AvgD)
//
// WP-41 v2 commit 2/4：RSI 实现 IncrementalIndicator · processStep helper 共享 makeIncrementalState 与 stepIncremental

import Foundation
import Shared

public enum RSI: Indicator {
    public static let identifier = "RSI"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, min: 2, label: "RSI period")

        let closes = kline.closes
        let count = closes.count
        var gains = [Decimal](repeating: 0, count: count)
        var losses = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            let diff = closes[i] - closes[i - 1]
            if diff > 0 {
                gains[i] = diff
            } else if diff < 0 {
                losses[i] = -diff
            }
        }

        let avgU = Kernels.wilder(gains, period: n)
        let avgD = Kernels.wilder(losses, period: n)

        var rsi = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let u = avgU[i], let d = avgD[i] else { continue }
            let total = u + d
            if total == 0 {
                rsi[i] = 50
            } else {
                rsi[i] = Kernels.round8(Decimal(100) * u / total)
            }
        }
        return [IndicatorSeries(name: "RSI(\(n))", values: rsi)]
    }
}

// MARK: - WP-41 v2 commit 2/4 · RSI 增量 API

extension RSI: IncrementalIndicator {

    /// state：Wilder 平滑参数（n / n-1） + prevClose（diff 计算）+ warmUpGains/Losses（前 n 个 gain/loss 累加 = avgU/D 种子之 sum）
    /// + count（已处理 close 数 · 从 0 起）+ avgU/D（count >= period 后才有效 · 不 round8 状态）
    public struct IncrementalState: Sendable {
        public let period: Int
        public let nDec: Decimal
        public let nMinus1: Decimal
        public var prevClose: Decimal?
        public var warmUpGains: Decimal
        public var warmUpLosses: Decimal
        public var count: Int
        public var avgU: Decimal
        public var avgD: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, min: 2, label: "RSI period")
        var state = IncrementalState(
            period: n, nDec: Decimal(n), nMinus1: Decimal(n - 1),
            prevClose: nil,
            warmUpGains: 0, warmUpLosses: 0,
            count: 0,
            avgU: 0, avgD: 0
        )
        // 模拟 step 扫描 history（包括 warm-up 与 Wilder 平滑 · 与 calculate 算法一致）
        for close in kline.closes {
            _ = processStep(state: &state, close: close)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        let value = processStep(state: &state, close: newBar.close)
        return [value]
    }

    /// makeIncrementalState 与 stepIncremental 共享的核心逻辑：
    /// - 第 1 根：仅记录 prevClose · 返回 nil
    /// - 第 2..n-1 根：累加 warmUpGains/Losses · 返回 nil
    /// - 第 n 根：累加 + 计算种子 avgU/D = warmUpSum/n · 返回首个 RSI
    /// - 第 n+1 根起：Wilder 平滑 · 返回 RSI
    private static func processStep(state: inout IncrementalState, close: Decimal) -> Decimal? {
        state.count += 1
        if state.count == 1 {
            state.prevClose = close
            return nil
        }
        let prev = state.prevClose ?? close
        let diff = close - prev
        let gain: Decimal = diff > 0 ? diff : 0
        let loss: Decimal = diff < 0 ? -diff : 0
        state.prevClose = close

        if state.count < state.period {
            state.warmUpGains += gain
            state.warmUpLosses += loss
            return nil
        }
        if state.count == state.period {
            state.warmUpGains += gain
            state.warmUpLosses += loss
            state.avgU = state.warmUpGains / state.nDec
            state.avgD = state.warmUpLosses / state.nDec
        } else {
            state.avgU = (state.avgU * state.nMinus1 + gain) / state.nDec
            state.avgD = (state.avgD * state.nMinus1 + loss) / state.nDec
        }
        // calculate() 用 round8(avgU/avgD) 作 RSI 输入（Kernels.wilder 输出 = round8(prev) 数组）
        // 增量也必须 round8 snapshot · 否则与全量末位精度差 1-2 位（state.avgU 是流式未 round 状态）
        let uRounded = Kernels.round8(state.avgU)
        let dRounded = Kernels.round8(state.avgD)
        let total = uRounded + dRounded
        if total == 0 { return Decimal(50) }
        return Kernels.round8(Decimal(100) * uRounded / total)
    }
}

// 共用 requireIntParam 已在 Indicator.swift 定义（min: 2）
