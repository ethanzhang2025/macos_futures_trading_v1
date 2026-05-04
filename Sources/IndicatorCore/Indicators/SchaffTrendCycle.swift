// WP-41 v15.18 · Schaff Trend Cycle (STC) 复合趋势指标（trader 流行 · 比 MACD 反应更快）
//
// 算法（Doug Schaff）：
//   1. MACD line = EMA(close, fast) - EMA(close, slow)（默认 fast=23, slow=50）
//   2. K1 = 100 * (MACD - LowestMACD(period)) / (HighestMACD(period) - LowestMACD(period))
//   3. D1 = EMA(K1, smooth)（默认 smooth=10）
//   4. K2 = 100 * (D1 - LowestD1(period)) / (HighestD1(period) - LowestD1(period))
//   5. STC = EMA(K2, smooth)
//
// 输出值域 0-100 · 阈值 25 / 75 看趋势翻转
// - STC 跌穿 25 = 看跌信号
// - STC 突破 75 = 看涨信号

import Foundation
import Shared

public enum STC: Indicator {
    public static let identifier = "STC"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "fast", defaultValue: 23, minValue: 2, maxValue: 200),
        IndicatorParameter(name: "slow", defaultValue: 50, minValue: 5, maxValue: 500),
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 2, maxValue: 200),
        IndicatorParameter(name: "smooth", defaultValue: 10, minValue: 2, maxValue: 100)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 4 else {
            throw IndicatorError.invalidParameter("STC 需 4 参数：fast, slow, period, smooth")
        }
        let fast = intValue(params[0])
        let slow = intValue(params[1])
        let period = intValue(params[2])
        let smooth = intValue(params[3])
        guard fast >= 2, slow > fast, period >= 2, smooth >= 2 else {
            throw IndicatorError.invalidParameter("STC 参数非法 fast=\(fast) slow=\(slow) period=\(period) smooth=\(smooth) · 要求 slow > fast >= 2")
        }

        let closes = kline.closes
        let count = closes.count
        guard count > 0 else {
            return [IndicatorSeries(name: "STC", values: [])]
        }

        // Step 1: MACD line（unsmoothed · 不像 MACD 指标那样减去 signal line）
        let emaFast = Kernels.ema(closes, period: fast)
        let emaSlow = Kernels.ema(closes, period: slow)
        var macdLine = [Decimal](repeating: 0, count: count)
        var macdValid = [Bool](repeating: false, count: count)
        for i in 0..<count {
            if let f = emaFast[i], let s = emaSlow[i] {
                macdLine[i] = f - s
                macdValid[i] = true
            }
        }

        // Step 2: K1 = 100 × (MACD - LowestMACD) / (HighestMACD - LowestMACD)
        var k1 = [Decimal](repeating: 0, count: count)
        var k1Valid = [Bool](repeating: false, count: count)
        for i in 0..<count {
            guard macdValid[i], i >= period - 1 else { continue }
            let start = max(0, i - period + 1)
            var hh = macdLine[start]
            var ll = macdLine[start]
            var allValidInWindow = macdValid[start]
            for j in (start + 1)...i {
                guard macdValid[j] else { allValidInWindow = false; break }
                if macdLine[j] > hh { hh = macdLine[j] }
                if macdLine[j] < ll { ll = macdLine[j] }
            }
            guard allValidInWindow, hh > ll else { continue }
            k1[i] = (macdLine[i] - ll) / (hh - ll) * Decimal(100)
            k1Valid[i] = true
        }

        // Step 3: D1 = EMA(K1, smooth)（仅 valid 段）· 简化：先 zero-pad invalid 处再 EMA
        let d1Raw = Kernels.ema(k1, period: smooth)

        // Step 4: K2 = 100 × (D1 - LowestD1) / (HighestD1 - LowestD1)
        var k2 = [Decimal](repeating: 0, count: count)
        var k2Valid = [Bool](repeating: false, count: count)
        for i in 0..<count {
            guard let dCurr = d1Raw[i], i >= period - 1 else { continue }
            var hh = dCurr
            var ll = dCurr
            var ok = true
            for j in (i - period + 1)...i {
                guard let dj = d1Raw[j] else { ok = false; break }
                if dj > hh { hh = dj }
                if dj < ll { ll = dj }
            }
            guard ok, hh > ll else { continue }
            k2[i] = (dCurr - ll) / (hh - ll) * Decimal(100)
            k2Valid[i] = true
        }

        // Step 5: STC = EMA(K2, smooth)
        let stcRaw = Kernels.ema(k2, period: smooth)
        var stc = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            // 仅当 K2 有效且 EMA 已 seed 才输出
            if k2Valid[i], let v = stcRaw[i] {
                stc[i] = Kernels.round8(v)
            }
        }

        return [IndicatorSeries(name: "STC(\(fast),\(slow),\(period),\(smooth))", values: stc)]
    }
}
