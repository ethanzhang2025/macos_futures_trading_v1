// WP-41 · OBV · 累积能量潮（量价类）
// 无周期参数
// 公式：
//   OBV(0) = volume(0)
//   OBV(i) = OBV(i-1) + volume(i)   （close 上涨）
//          = OBV(i-1) - volume(i)   （close 下跌）
//          = OBV(i-1)               （close 平）
//
// WP-41 v3 第 2 批 commit 1/4：OBV 实现 IncrementalIndicator · O(1) per step（最简累加）

import Foundation
import Shared

public enum OBV: Indicator {
    public static let identifier = "OBV"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let closes = kline.closes
        let volumes = kline.volumes
        let count = closes.count

        var out = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return [IndicatorSeries(name: "OBV", values: out)] }

        var running = Decimal(volumes[0])
        out[0] = running
        for i in 1..<count {
            if closes[i] > closes[i - 1] {
                running += Decimal(volumes[i])
            } else if closes[i] < closes[i - 1] {
                running -= Decimal(volumes[i])
            }
            out[i] = running
        }
        return [IndicatorSeries(name: "OBV", values: out)]
    }
}

// MARK: - WP-41 v3 第 2 批 commit 1/4 · OBV 增量 API

extension OBV: IncrementalIndicator {

    /// state：仅 prev close + 累积 running · 第一根 = Decimal(volume) · 之后按 close 涨跌累加/扣减/不变
    /// 无 warm-up · 无周期参数 · 流式 Decimal 累加（与 calculate 整数 volume → Decimal 一致 · 不 round）
    public struct IncrementalState: Sendable {
        public var prevClose: Decimal?
        public var running: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(prevClose: nil, running: 0)
        let count = kline.closes.count
        for i in 0..<count {
            _ = processStep(state: &state, close: kline.closes[i], volume: kline.volumes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close, volume: newBar.volume)]
    }

    /// makeIncrementalState 与 stepIncremental 共享：
    /// - 第 1 根：running = Decimal(volume) · prevClose = close（与 calculate out[0] = volumes[0] 一致）
    /// - 第 2 根起：close > prev → +volume / close < prev → -volume / 平 → 不变（与 calculate 一致）
    private static func processStep(state: inout IncrementalState, close: Decimal, volume: Int) -> Decimal? {
        let volDec = Decimal(volume)
        if let prev = state.prevClose {
            if close > prev {
                state.running += volDec
            } else if close < prev {
                state.running -= volDec
            }
        } else {
            state.running = volDec
        }
        state.prevClose = close
        return state.running
    }
}
