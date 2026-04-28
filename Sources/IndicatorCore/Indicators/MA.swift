// WP-41 · MA · 简单移动平均（趋势类）
// 参数：period（默认 20）
// WP-41 v2 commit 1/4：MA 实现 IncrementalIndicator · 环形 buffer + 滑动 sum · O(1) per step

import Foundation
import Shared

public enum MA: Indicator {
    public static let identifier = "MA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "MA period")
        let values = Kernels.ma(kline.closes, period: n)
        return [IndicatorSeries(name: "MA(\(n))", values: values)]
    }
}

extension MA: IncrementalIndicator {

    /// 环形 buffer + 滑动 sum 实现 O(1) per step
    /// - period：窗口大小
    /// - ring：容量 period 的环形 buffer · head 是下一个写入位置（被覆盖的是 period 步前的值）
    /// - count：已写入数量（≤ period）· 达到 period 后 ring 满 · 之后每步替换 ring[head] · sum 增量更新
    public struct IncrementalState: Sendable {
        public let period: Int
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "MA period")
        let closes = kline.closes
        // 取 history 末尾 ≤ n 个 close 装入 ring · 重建 sum 与 calculate() 末值一致
        let startIdx = max(0, closes.count - n)
        var ring = [Decimal](repeating: Decimal(0), count: n)
        var head = 0
        var count = 0
        var sum = Decimal(0)
        for v in closes[startIdx...] {
            ring[head] = v
            head = (head + 1) % n
            count = min(count + 1, n)
            sum += v
        }
        return IncrementalState(period: n, ring: ring, head: head, count: count, sum: sum)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // ring 已满时 head 位置存的是 period 步前的旧值 · 需先从 sum 中扣除
        // ring 未满时 head 位置是初始 0 · 不必扣除
        if state.count == state.period {
            state.sum -= state.ring[state.head]
        } else {
            state.count += 1
        }
        state.ring[state.head] = newBar.close
        state.head = (state.head + 1) % state.period
        state.sum += newBar.close

        guard state.count == state.period else { return [nil] }
        return [Kernels.round8(state.sum / Decimal(state.period))]
    }
}

public enum EMA: Indicator {
    public static let identifier = "EMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 12, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "EMA period")
        let values = Kernels.ema(kline.closes, period: n)
        return [IndicatorSeries(name: "EMA(\(n))", values: values)]
    }
}

// MARK: - WP-41 v2 commit 2/4 · EMA 增量 API

extension EMA: IncrementalIndicator {

    /// state：α=2/(n+1) 平滑系数 + warmUpSum（warm-up 期累加 · 第 n 步用作 SMA 种子）+ prevEMA（不 round 状态 · 输出 round8）
    public struct IncrementalState: Sendable {
        public let period: Int
        public let alpha: Decimal
        public let oneMinusAlpha: Decimal
        public var warmUpSum: Decimal
        public var count: Int
        public var prevEMA: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "EMA period")
        let alpha = Decimal(2) / Decimal(n + 1)
        let oneMinusAlpha = Decimal(1) - alpha
        let closes = kline.closes
        let count = closes.count
        if count >= n {
            // 已过 warm-up · 重建 prevEMA（与 calculate 内部状态一致 · 不 round8）
            let seedSum = closes.prefix(n).reduce(Decimal(0), +)
            var prev = seedSum / Decimal(n)
            for i in n..<count {
                prev = alpha * closes[i] + oneMinusAlpha * prev
            }
            return IncrementalState(period: n, alpha: alpha, oneMinusAlpha: oneMinusAlpha,
                                    warmUpSum: 0, count: count, prevEMA: prev)
        }
        // warm-up 期 · 累加 sum
        let warmUpSum = closes.reduce(Decimal(0), +)
        return IncrementalState(period: n, alpha: alpha, oneMinusAlpha: oneMinusAlpha,
                                warmUpSum: warmUpSum, count: count, prevEMA: Decimal(0))
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        state.count += 1
        if state.count < state.period {
            state.warmUpSum += newBar.close
            return [nil]
        }
        if state.count == state.period {
            // 这一根恰好达 period · 用 SMA 种子
            state.warmUpSum += newBar.close
            state.prevEMA = state.warmUpSum / Decimal(state.period)
        } else {
            state.prevEMA = state.alpha * newBar.close + state.oneMinusAlpha * state.prevEMA
        }
        return [Kernels.round8(state.prevEMA)]
    }
}

// 共用 requireIntParam 已在 Indicator.swift 定义
