// WP-41 第二批 · 趋势类 8 指标（除 MA/EMA 已在 MA.swift）
// WMA / DEMA / TEMA / HMA / VWAP / SAR / Supertrend / ADX

import Foundation

// MARK: - WMA · 加权移动平均

public enum WMA: Indicator {
    public static let identifier = "WMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "WMA period")
        return [IndicatorSeries(name: "WMA(\(n))", values: Kernels.wma(kline.closes, period: n))]
    }
}

// MARK: - DEMA · 双重 EMA = 2*EMA - EMA(EMA)

public enum DEMA: Indicator {
    public static let identifier = "DEMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "DEMA period")
        let e1 = Kernels.ema(kline.closes, period: n)
        let e2 = Kernels.nextEMA(e1, period: n)
        var out = [Decimal?](repeating: nil, count: kline.count)
        for i in 0..<kline.count {
            if let x1 = e1[i], let x2 = e2[i] {
                out[i] = Kernels.round8(Decimal(2) * x1 - x2)
            }
        }
        return [IndicatorSeries(name: "DEMA(\(n))", values: out)]
    }
}

// MARK: - TEMA · 三重 EMA = 3*EMA - 3*EMA(EMA) + EMA(EMA(EMA))

public enum TEMA: Indicator {
    public static let identifier = "TEMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "TEMA period")
        let e1 = Kernels.ema(kline.closes, period: n)
        let e2 = Kernels.nextEMA(e1, period: n)
        let e3 = Kernels.nextEMA(e2, period: n)
        var out = [Decimal?](repeating: nil, count: kline.count)
        for i in 0..<kline.count {
            if let x1 = e1[i], let x2 = e2[i], let x3 = e3[i] {
                out[i] = Kernels.round8(Decimal(3) * x1 - Decimal(3) * x2 + x3)
            }
        }
        return [IndicatorSeries(name: "TEMA(\(n))", values: out)]
    }
}

// MARK: - HMA · Hull 移动平均 = WMA(2*WMA(n/2) - WMA(n), √n)

public enum HMA: Indicator {
    public static let identifier = "HMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 16, minValue: 4, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 4, label: "HMA period")
        let halfN = max(1, n / 2)
        let sqrtN = max(1, Int(Double(n).squareRoot()))
        let wHalf = Kernels.wma(kline.closes, period: halfN)
        let wFull = Kernels.wma(kline.closes, period: n)
        var raw = [Decimal](repeating: 0, count: kline.count)
        for i in 0..<kline.count {
            if let h = wHalf[i], let f = wFull[i] {
                raw[i] = Decimal(2) * h - f
            }
        }
        let hma = Kernels.wma(raw, period: sqrtN)
        return [IndicatorSeries(name: "HMA(\(n))", values: hma)]
    }
}

// MARK: - VWAP · 成交量加权均价（日内累积）
// 无周期参数；从序列起始点累积 Σ(price * volume) / Σvolume

public enum VWAP: Indicator {
    public static let identifier = "VWAP"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        var cumPV: Decimal = 0
        var cumV: Decimal = 0
        for i in 0..<count {
            let typical = (kline.highs[i] + kline.lows[i] + kline.closes[i]) / Decimal(3)
            cumPV += typical * Decimal(kline.volumes[i])
            cumV += Decimal(kline.volumes[i])
            out[i] = cumV == 0 ? nil : Kernels.round8(cumPV / cumV)
        }
        return [IndicatorSeries(name: "VWAP", values: out)]
    }
}

// MARK: - SAR · 抛物线转向（Welles Wilder）
// 参数：加速因子初值 0.02 / 最大值 0.2

public enum SAR: Indicator {
    public static let identifier = "SAR"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "step", defaultValue: Decimal(string: "0.02")!, minValue: Decimal(string: "0.001")!, maxValue: 1),
        IndicatorParameter(name: "max", defaultValue: Decimal(string: "0.2")!, minValue: Decimal(string: "0.01")!, maxValue: 1)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("SAR 需要 2 参数（step / max）")
        }
        let step = params[0]
        let maxAF = params[1]
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        guard count >= 2 else { return [IndicatorSeries(name: "SAR", values: out)] }

        // 初始方向：首 2 根 close 比较
        var isLong = kline.closes[1] >= kline.closes[0]
        var ep = isLong ? kline.highs[0] : kline.lows[0]   // 极端点
        var af = step
        var sar = isLong ? kline.lows[0] : kline.highs[0]
        out[0] = Kernels.round8(sar)

        for i in 1..<count {
            sar = sar + af * (ep - sar)
            // 多头 SAR 不能超当前两根最低；空头反之
            if isLong {
                sar = min(sar, kline.lows[i - 1])
                if i >= 2 { sar = min(sar, kline.lows[i - 2]) }
                if kline.highs[i] > ep { ep = kline.highs[i]; af = min(af + step, maxAF) }
                if kline.lows[i] < sar {  // 反转
                    isLong = false
                    sar = ep
                    ep = kline.lows[i]
                    af = step
                }
            } else {
                sar = max(sar, kline.highs[i - 1])
                if i >= 2 { sar = max(sar, kline.highs[i - 2]) }
                if kline.lows[i] < ep { ep = kline.lows[i]; af = min(af + step, maxAF) }
                if kline.highs[i] > sar {
                    isLong = true
                    sar = ep
                    ep = kline.highs[i]
                    af = step
                }
            }
            out[i] = Kernels.round8(sar)
        }
        return [IndicatorSeries(name: "SAR", values: out)]
    }
}

// MARK: - Supertrend · 基于 ATR 的超级趋势
// 参数：period（10）/ multiplier（3）

public enum Supertrend: Indicator {
    public static let identifier = "Supertrend"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "multiplier", defaultValue: 3, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Supertrend 需要 2 参数（period / multiplier）")
        }
        let n = intValue(params[0])
        let mult = params[1]
        guard n >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("Supertrend 参数非法 period=\(n) mult=\(mult)")
        }
        let atr = try ATR.calculate(kline: kline, params: [Decimal(n)])[0].values
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        var upperBand: Decimal? = nil
        var lowerBand: Decimal? = nil
        var isUp = true
        for i in 0..<count {
            guard let a = atr[i] else { continue }
            let mid = (kline.highs[i] + kline.lows[i]) / Decimal(2)
            let rawUp = mid + mult * a
            let rawLow = mid - mult * a
            // 带状约束：上轨只降不升（除非上一根收盘击穿），保持趋势跟踪稳定性
            // 种子时（prev == nil）直接采用 raw；后续迭代下 i >= 1，closes[i-1] 合法
            let newUpper: Decimal
            if let prev = upperBand {
                newUpper = (rawUp < prev || kline.closes[i - 1] > prev) ? rawUp : prev
            } else {
                newUpper = rawUp
            }
            let newLower: Decimal
            if let prev = lowerBand {
                newLower = (rawLow > prev || kline.closes[i - 1] < prev) ? rawLow : prev
            } else {
                newLower = rawLow
            }
            upperBand = newUpper
            lowerBand = newLower
            if isUp, kline.closes[i] < newLower {
                isUp = false
            } else if !isUp, kline.closes[i] > newUpper {
                isUp = true
            }
            out[i] = Kernels.round8(isUp ? newLower : newUpper)
        }
        return [IndicatorSeries(name: "Supertrend", values: out)]
    }
}

// MARK: - ADX · 平均趋向指数（Wilder 方法，配 +DI/-DI）

public enum ADX: Indicator {
    public static let identifier = "ADX"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 2, label: "ADX period")
        let count = kline.count
        guard count >= 2 else { return emptyADX(count) }

        var plusDM = [Decimal](repeating: 0, count: count)
        var minusDM = [Decimal](repeating: 0, count: count)
        var tr = [Decimal](repeating: 0, count: count)
        tr[0] = kline.highs[0] - kline.lows[0]
        for i in 1..<count {
            let up = kline.highs[i] - kline.highs[i - 1]
            let dn = kline.lows[i - 1] - kline.lows[i]
            plusDM[i] = (up > dn && up > 0) ? up : 0
            minusDM[i] = (dn > up && dn > 0) ? dn : 0
            let hl = kline.highs[i] - kline.lows[i]
            let hc = abs(kline.highs[i] - kline.closes[i - 1])
            let lc = abs(kline.lows[i] - kline.closes[i - 1])
            tr[i] = max(hl, max(hc, lc))
        }
        let atr = Kernels.wilder(tr, period: n)
        let smPlusDM = Kernels.wilder(plusDM, period: n)
        let smMinusDM = Kernels.wilder(minusDM, period: n)
        var plusDI = [Decimal?](repeating: nil, count: count)
        var minusDI = [Decimal?](repeating: nil, count: count)
        var dx = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            if let a = atr[i], let pdm = smPlusDM[i], let mdm = smMinusDM[i], a > 0 {
                let pdi = Decimal(100) * pdm / a
                let mdi = Decimal(100) * mdm / a
                plusDI[i] = Kernels.round8(pdi)
                minusDI[i] = Kernels.round8(mdi)
                let sum = pdi + mdi
                dx[i] = sum == 0 ? 0 : Decimal(100) * abs(pdi - mdi) / sum
            }
        }
        let adx = Kernels.wilder(dx, period: n)
        return [
            IndicatorSeries(name: "ADX", values: adx),
            IndicatorSeries(name: "+DI", values: plusDI),
            IndicatorSeries(name: "-DI", values: minusDI)
        ]
    }

    private static func emptyADX(_ count: Int) -> [IndicatorSeries] {
        let empty = [Decimal?](repeating: nil, count: count)
        return [
            IndicatorSeries(name: "ADX", values: empty),
            IndicatorSeries(name: "+DI", values: empty),
            IndicatorSeries(name: "-DI", values: empty)
        ]
    }
}

// 共用 requireIntParam 已在 Indicator.swift 定义
