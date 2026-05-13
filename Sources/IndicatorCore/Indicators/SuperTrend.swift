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
