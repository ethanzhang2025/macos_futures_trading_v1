// WP-41 第二批 · 波动率/通道类 6 指标（除 BOLL/ATR 已在独立文件）
// KC / Donchian / StdDev / HV / PriceChannel / Envelopes

import Foundation

// MARK: - KC · 肯特纳通道 EMA ± mult * ATR

public enum KC: Indicator {
    public static let identifier = "KC"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "emaPeriod", defaultValue: 20, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "atrPeriod", defaultValue: 10, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "multiplier", defaultValue: 2, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("KC 需要 3 参数（emaPeriod / atrPeriod / multiplier）")
        }
        let emaN = intValue(params[0])
        let atrN = intValue(params[1])
        let mult = params[2]
        guard emaN >= 1, atrN >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("KC 参数非法 ema=\(emaN) atr=\(atrN) mult=\(mult)")
        }
        let ema = Kernels.ema(kline.closes, period: emaN)
        let atr = try ATR.calculate(kline: kline, params: [Decimal(atrN)])[0].values
        let count = kline.count
        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = ema[i], let a = atr[i] {
                upper[i] = Kernels.round8(m + mult * a)
                lower[i] = Kernels.round8(m - mult * a)
            }
        }
        return [
            IndicatorSeries(name: "KC-MID", values: ema),
            IndicatorSeries(name: "KC-UPPER", values: upper),
            IndicatorSeries(name: "KC-LOWER", values: lower)
        ]
    }
}

// MARK: - Donchian · 唐奇安通道

public enum Donchian: Indicator {
    public static let identifier = "DONCHIAN"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "Donchian period")
        let hhv = Kernels.hhv(kline.highs, period: n)
        let llv = Kernels.llv(kline.lows, period: n)
        let count = kline.count
        var mid = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let h = hhv[i], let l = llv[i] {
                mid[i] = Kernels.round8((h + l) / Decimal(2))
            }
        }
        return [
            IndicatorSeries(name: "DC-UPPER", values: hhv),
            IndicatorSeries(name: "DC-MID", values: mid),
            IndicatorSeries(name: "DC-LOWER", values: llv)
        ]
    }
}

// MARK: - StdDev · 标准差（直接暴露 Kernel）

public enum StdDev: Indicator {
    public static let identifier = "STDDEV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, min: 2, label: "StdDev period")
        return [IndicatorSeries(name: "STDDEV(\(n))", values: Kernels.stddev(kline.closes, period: n))]
    }
}

// MARK: - HV · 历史波动率（log 收益年化，默认 252 交易日）

public enum HV: Indicator {
    public static let identifier = "HV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500),
        IndicatorParameter(name: "annualDays", defaultValue: 252, minValue: 1, maxValue: 365)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 2, label: "HV period")
        let annual = params.count > 1 ? intValue(params[1]) : 252
        let count = kline.count
        var logRet = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            let prev = kline.closes[i - 1]
            if prev > 0 {
                let ratio = NSDecimalNumber(decimal: kline.closes[i] / prev).doubleValue
                logRet[i] = Decimal(Foundation.log(ratio))
            }
        }
        let sd = Kernels.stddev(logRet, period: n)
        let ann = Decimal(Double(annual).squareRoot())
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let v = sd[i] {
                out[i] = Kernels.round8(v * ann * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "HV(\(n))", values: out)]
    }
}

// MARK: - PriceChannel · 价格通道（基于 close 的 Donchian 变体）

public enum PriceChannel: Indicator {
    public static let identifier = "PC"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "PriceChannel period")
        let hhv = Kernels.hhv(kline.closes, period: n)
        let llv = Kernels.llv(kline.closes, period: n)
        return [
            IndicatorSeries(name: "PC-UPPER", values: hhv),
            IndicatorSeries(name: "PC-LOWER", values: llv)
        ]
    }
}

// MARK: - Envelopes · 包络线 MA ± k%

public enum Envelopes: Indicator {
    public static let identifier = "ENV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "percent", defaultValue: Decimal(string: "2.5")!, minValue: Decimal(string: "0.1")!, maxValue: 50)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Envelopes 需要 2 参数（period / percent）")
        }
        let n = intValue(params[0])
        let pct = params[1]
        let mid = Kernels.ma(kline.closes, period: n)
        let kFactor = pct / Decimal(100)
        let count = kline.count
        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = mid[i] {
                upper[i] = Kernels.round8(m * (Decimal(1) + kFactor))
                lower[i] = Kernels.round8(m * (Decimal(1) - kFactor))
            }
        }
        return [
            IndicatorSeries(name: "ENV-MID", values: mid),
            IndicatorSeries(name: "ENV-UPPER", values: upper),
            IndicatorSeries(name: "ENV-LOWER", values: lower)
        ]
    }
}
