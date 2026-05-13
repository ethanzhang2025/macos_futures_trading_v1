// v17.139 · SuperTrend · 基于 ATR 的趋势止损线（主图 overlay · 短中线趋势跟随）
// 参数：period（默认 10）/ multiplier（默认 3.0）
// 公式：
//   atr      = ATR(period)
//   hl2(i)   = (high(i) + low(i)) / 2
//   upBand(i)   = hl2(i) + mult * atr(i)
//   downBand(i) = hl2(i) - mult * atr(i)
//
//   flip 判定（本根之前用 prev close vs prev ST）：
//     wasLong & prevClose < prevST → 翻空
//     !wasLong & prevClose > prevST → 翻多
//
//   rolling lock（标准 SuperTrend · 与麦语言 SUPERTREND() 实现一致 · trader 不会看到两个版本结果）：
//     long  时 ST = max(downBand, prevST)   只升不降
//     short 时 ST = min(upBand,   prevST)   只降不升
//
// 输出：
//   - SUPERTREND：单条线（多头时 = downBand 滚锁 / 空头时 = upBand 滚锁 · trader 看价格相对其位置）
//   - SUPERTREND-DIR：方向标记（+1 = 多 / -1 = 空 · 渲染层可用色彩区分 · 本期暂不画 · 留扩展）

import Foundation
import Shared

public enum SuperTrend: Indicator {
    public static let identifier = "SUPERTREND"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period",     defaultValue: 10, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "multiplier", defaultValue: 3,  minValue: 1, maxValue: 20)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let (n, mult) = try Self.requireParams(params)
        let count = kline.count

        var st  = [Decimal?](repeating: nil, count: count)
        var dir = [Decimal?](repeating: nil, count: count)
        guard count > 0 else {
            return [
                IndicatorSeries(name: "SUPERTREND", values: st),
                IndicatorSeries(name: "SUPERTREND-DIR", values: dir)
            ]
        }

        // 1) ATR · Wilder · warm-up 期 < n 返回 nil
        let atrSeries = try ATR.calculate(kline: kline, params: [Decimal(n)])
        let atr = atrSeries[0].values

        // 2) upBand / downBand · 仅 atr 非 nil 才有效
        var upBand   = [Decimal?](repeating: nil, count: count)
        var downBand = [Decimal?](repeating: nil, count: count)
        let highs = kline.highs
        let lows  = kline.lows
        let closes = kline.closes
        let two = Decimal(2)
        for i in 0..<count {
            guard let a = atr[i] else { continue }
            let hl2 = (highs[i] + lows[i]) / two
            upBand[i]   = hl2 + mult * a
            downBand[i] = hl2 - mult * a
        }

        // 3) SuperTrend & dir · flip + rolling lock · 与麦语言 SUPERTRENDFunction 算法一致
        var trendIsLong = true
        var firstValid: Int? = nil
        for i in 0..<count {
            guard let up = upBand[i], let dn = downBand[i] else { continue }
            if firstValid == nil {
                trendIsLong = true
                st[i]  = Kernels.round8(dn)
                dir[i] = Decimal(1)
                firstValid = i
                continue
            }
            let wasLong = trendIsLong
            // 翻转判定：用前一根 close 与前一根 ST 比较（与麦语言版一致）
            if let prevST = st[i - 1] {
                if wasLong && closes[i - 1] < prevST {
                    trendIsLong = false
                } else if !wasLong && closes[i - 1] > prevST {
                    trendIsLong = true
                }
            }
            // rolling lock
            if trendIsLong {
                if wasLong, let prevST = st[i - 1] {
                    st[i] = Kernels.round8(max(dn, prevST))
                } else {
                    st[i] = Kernels.round8(dn)
                }
            } else {
                if !wasLong, let prevST = st[i - 1] {
                    st[i] = Kernels.round8(min(up, prevST))
                } else {
                    st[i] = Kernels.round8(up)
                }
            }
            dir[i] = trendIsLong ? Decimal(1) : Decimal(-1)
        }

        return [
            IndicatorSeries(name: "SUPERTREND",     values: st),
            IndicatorSeries(name: "SUPERTREND-DIR", values: dir)
        ]
    }

    fileprivate static func requireParams(_ params: [Decimal]) throws -> (n: Int, mult: Decimal) {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("SuperTrend 需要 2 个参数（period / multiplier）")
        }
        let n = intValue(params[0])
        let mult = params[1]
        guard n >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("SuperTrend 参数非法: period=\(n) mult=\(mult)")
        }
        return (n, mult)
    }
}

// MARK: - v17.155 · SuperTrend 增量 API（内嵌 ATR + 状态机 prevST/trendIsLong/prevClose · 主图 overlay 增量化）
//
// 与 Trend.swift 中老 Supertrend 增量的关键差异：
// - 翻转判定用前一根 close vs 前一根 ST（calculate `closes[i-1] < st[i-1]`）· 老版用当前 close vs 新 band
// - rolling lock：long 时 ST = max(downBand, prevST)（只升不降）· short 时 ST = min(upBand, prevST)（只降不升）
//   老版是 newUpper = (rawUp < prev || closes[i-1] > prev) ? rawUp : prev 不同范式
// - 输出 2 列 [SUPERTREND, SUPERTREND-DIR]（老版仅 1 列）
// - 首个有效 atr 根 trendIsLong = true / ST = round8(dn) / DIR = 1（与 calculate firstValid 一致）
//
// 与 calculate 关键对齐：
// - warm-up 期 atr nil → 输出 [nil, nil] · 不更新 trend/prevST · prevClose 持续更新（calculate 中 `closes[i-1]` 索引语义）
// - 首根有效 atr 直接 round8(dn) · 后续看 prevClose 决定翻转 · rolling lock 用上一根 prevST（已 round8）

extension SuperTrend: IncrementalIndicator {

    /// state：multiplier + 内嵌 ATR.IncrementalState + 翻转/锁定所需的 5 个值
    /// - prevST：上一根 ST（已 round8 · nil 表示前面都在 warm-up）
    /// - prevClose：上一根 close（每根更新 · 翻转判定要用）
    /// - trendIsLong：当前趋势方向（默认 true · 与 calculate `var trendIsLong = true` 一致）
    /// - firstValidSet：首个有效 atr 根标记（对应 calculate `firstValid == nil` 判定）
    public struct IncrementalState: Sendable {
        public let multiplier: Decimal
        public var atrState: ATR.IncrementalState
        public var prevST: Decimal?
        public var prevClose: Decimal?
        public var trendIsLong: Bool
        public var firstValidSet: Bool
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let (n, mult) = try Self.requireParams(params)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            multiplier: mult,
            atrState: try ATR.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            prevST: nil,
            prevClose: nil,
            trendIsLong: true,
            firstValidSet: false
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            let bar = KLine(
                instrumentID: "", period: .minute1,
                openTime: Date(timeIntervalSinceReferenceDate: 0),
                open: kline.opens[i], high: kline.highs[i], low: kline.lows[i], close: kline.closes[i],
                volume: kline.volumes[i], openInterest: 0, turnover: 0
            )
            _ = processStep(state: &state, bar: bar)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, bar: newBar)
    }

    /// 单步推进（与 calculate 主循环逐根等价）：
    /// 1. 推进 ATR · atr nil → warm-up（仅更新 prevClose · 返回 [nil, nil]）
    /// 2. atr 有值且首次（firstValidSet == false）→ trendIsLong = true / ST = round8(dn) / DIR = 1
    /// 3. atr 有值且非首次：用 prevClose vs prevST 判翻转 · 然后 rolling lock 出新 ST
    /// 注：calculate 中 `if let prevST = st[i-1]` 在前一根是 firstValid 之后必然非 nil（一旦 firstValid 后 atr 不会回 nil）
    private static func processStep(state: inout IncrementalState, bar: KLine) -> [Decimal?] {
        let atrRow = ATR.stepIncremental(state: &state.atrState, newBar: bar)
        let close = bar.close

        guard let a = atrRow[0] else {
            // ATR warm-up · 仅推进 prevClose（calculate 中 closes[i-1] 全局索引语义 · 即使当前根 atr nil）
            state.prevClose = close
            return [nil, nil]
        }

        let two = Decimal(2)
        let mid = (bar.high + bar.low) / two
        let up = mid + state.multiplier * a
        let dn = mid - state.multiplier * a

        if !state.firstValidSet {
            // 首个有效 atr 根 · 与 calculate firstValid 分支等价
            state.trendIsLong = true
            let st0 = Kernels.round8(dn)
            state.prevST = st0
            state.firstValidSet = true
            state.prevClose = close
            return [st0, Decimal(1)]
        }

        // 已 seeded · 翻转判定用 prevST + prevClose（calculate 用 st[i-1] + closes[i-1]）
        let wasLong = state.trendIsLong
        if let prevST = state.prevST, let pc = state.prevClose {
            if wasLong && pc < prevST {
                state.trendIsLong = false
            } else if !wasLong && pc > prevST {
                state.trendIsLong = true
            }
        }

        // rolling lock（与 calculate 完全一致）
        let newST: Decimal
        if state.trendIsLong {
            if wasLong, let prevST = state.prevST {
                newST = Kernels.round8(max(dn, prevST))
            } else {
                // 刚翻多（wasLong=false → trendIsLong=true）· 直接采用 dn（无锁定）
                newST = Kernels.round8(dn)
            }
        } else {
            if !wasLong, let prevST = state.prevST {
                newST = Kernels.round8(min(up, prevST))
            } else {
                // 刚翻空 · 直接采用 up
                newST = Kernels.round8(up)
            }
        }

        state.prevST = newST
        state.prevClose = close
        return [newST, state.trendIsLong ? Decimal(1) : Decimal(-1)]
    }
}
