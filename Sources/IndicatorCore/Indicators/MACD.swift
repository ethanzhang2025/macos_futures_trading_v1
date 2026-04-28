// WP-41 · MACD · 指数平滑异同移动平均（震荡类）
// 参数：fast（12）/ slow（26）/ signal（9）
// 公式：
//   DIF  = EMA(close, fast) - EMA(close, slow)
//   DEA  = EMA(DIF, signal)
//   MACD = 2 * (DIF - DEA)   // 柱状；系数 2 是 A 股习惯，与文华一致
//
// WP-41 v2 commit 3/4：MACD 实现 IncrementalIndicator · 内嵌 3 个 EMA.IncrementalState（fast/slow on close · signal on DIF）
//                       借助 EMA.IncrementalState.advance(close:) 复用算法 · 整体 O(1) per step

import Foundation
import Shared

public enum MACD: Indicator {
    public static let identifier = "MACD"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "fast", defaultValue: 12, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "slow", defaultValue: 26, minValue: 2, maxValue: 500),
        IndicatorParameter(name: "signal", defaultValue: 9, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("MACD 需要 3 个参数（fast / slow / signal）")
        }
        let fast = intValue(params[0])
        let slow = intValue(params[1])
        let signal = intValue(params[2])
        guard fast > 0, slow > fast, signal > 0 else {
            throw IndicatorError.invalidParameter("MACD 参数非法: fast=\(fast) slow=\(slow) signal=\(signal)")
        }

        let emaFast = Kernels.ema(kline.closes, period: fast)
        let emaSlow = Kernels.ema(kline.closes, period: slow)
        let count = kline.count

        // DIF：两条 EMA 之差，两者都有值时才计算
        var difValues = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let f = emaFast[i], let s = emaSlow[i] {
                difValues[i] = Kernels.round8(f - s)
            }
        }

        // DEA：DIF 的 signal 周期 EMA（从 DIF 首个非 nil 处开始）
        // 切片前把 nil 填 0（DIF 首个非 nil 之前的位置不会被 EMA 使用）
        let firstDIFIdx = difValues.firstIndex(where: { $0 != nil }) ?? count
        let difSlice = difValues[firstDIFIdx..<count].map { $0 ?? 0 }
        let deaSlice = Kernels.ema(difSlice, period: signal)
        var deaValues = [Decimal?](repeating: nil, count: count)
        for (offset, v) in deaSlice.enumerated() {
            deaValues[firstDIFIdx + offset] = v
        }

        // MACD 柱：2 * (DIF - DEA)
        var macdValues = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let d = difValues[i], let e = deaValues[i] {
                macdValues[i] = Kernels.round8(Decimal(2) * (d - e))
            }
        }

        return [
            IndicatorSeries(name: "DIF", values: difValues),
            IndicatorSeries(name: "DEA", values: deaValues),
            IndicatorSeries(name: "MACD", values: macdValues)
        ]
    }
}

// MARK: - WP-41 v2 commit 3/4 · MACD 增量 API

extension MACD: IncrementalIndicator {

    /// state：3 个 EMA.IncrementalState（fast/slow 接 close · signal 接 DIF · DIF 出现前 signal 不推进）
    public struct IncrementalState: Sendable {
        public var fastEMA: EMA.IncrementalState
        public var slowEMA: EMA.IncrementalState
        public var deaEMA: EMA.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let (fast, slow, signal) = try Self.requireParams(params)
        var fastState = try emptyEMAState(period: fast)
        var slowState = try emptyEMAState(period: slow)
        var deaState  = try emptyEMAState(period: signal)

        // 注意：每步必须独立 advance fast 与 slow（state.count 必须每步递增 · 不能用 if-let 链短路）
        for close in kline.closes {
            let fv = fastState.advance(close: close)
            let sv = slowState.advance(close: close)
            if let fv, let sv {
                let dif = Kernels.round8(fv - sv)
                _ = deaState.advance(close: dif)
            }
        }
        return IncrementalState(fastEMA: fastState, slowEMA: slowState, deaEMA: deaState)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // 注意：每步必须独立 advance fast 与 slow（state.count 必须每步递增 · 不能短路）
        let fv = state.fastEMA.advance(close: newBar.close)
        let sv = state.slowEMA.advance(close: newBar.close)
        guard let fv, let sv else { return [nil, nil, nil] }
        let dif = Kernels.round8(fv - sv)
        guard let dea = state.deaEMA.advance(close: dif) else { return [dif, nil, nil] }
        let macd = Kernels.round8(Decimal(2) * (dif - dea))
        return [dif, dea, macd]
    }

    /// 三个内嵌 EMA state 都用空 history 起步 · 历史数据由 makeIncrementalState 自己扫一遍 advance
    private static func emptyEMAState(period: Int) throws -> EMA.IncrementalState {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        return try EMA.makeIncrementalState(kline: empty, params: [Decimal(period)])
    }

    /// 共享参数校验（calculate / makeIncrementalState 都用）
    fileprivate static func requireParams(_ params: [Decimal]) throws -> (fast: Int, slow: Int, signal: Int) {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("MACD 需要 3 个参数（fast / slow / signal）")
        }
        let fast = intValue(params[0])
        let slow = intValue(params[1])
        let signal = intValue(params[2])
        guard fast > 0, slow > fast, signal > 0 else {
            throw IndicatorError.invalidParameter("MACD 参数非法: fast=\(fast) slow=\(slow) signal=\(signal)")
        }
        return (fast, slow, signal)
    }
}
