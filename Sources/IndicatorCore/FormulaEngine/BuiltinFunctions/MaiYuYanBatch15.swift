// 麦语言扩展 · 第 15 批（v15.25 batch22 · KDJ/BOLL 配套 + K 线类型 + 角度）
//
// 7 个补完三件套 + trader 实用辅助：
//   1. KDJD(N, M)         — KDJ D 线 = SMA(K, M, 1)
//   2. KDJJ(N, M)         — KDJ J 线 = 3K - 2D
//   3. BOLLW(N, K)        — 布林带宽度 = (U - L) / M（squeeze 判定）
//   4. BOLLPCT(N, K)      — 布林带 %b = (C - L) / (U - L)
//   5. TYPING()           — K 线类型（1=阳 -1=阴 0=十字）
//   6. MAANGLE(X, N)      — MA 角度（atan(MA-REF(MA,1)) 度数）
//   7. RSIDIV(N1, N2)     — RSI 差 = RSI(N1) - RSI(N2)（双 RSI 系统）

import Foundation

// MARK: - 1. KDJD

/// KDJD — D = SMA(K, M, 1)
/// 等价 KDJK 的 SMA 平滑（M=3 trader 标准）
struct KDJDFunction: BuiltinFunction {
    let name = "KDJD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KDJD需要2个参数（N RSV周期, M 平滑周期）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "KDJD的参数无效")
        }
        let pn = Int(truncating: n as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pn > 0, pm > 0 else {
            throw InterpreterError(message: "KDJD的周期必须为正整数")
        }

        let k = MaiB15KDJ.computeK(bars: bars, periodN: pn, periodM: pm)
        return MaiB15KDJ.smooth(k, period: pm, weight: 1)
    }
}

// MARK: - 2. KDJJ

/// KDJJ — J = 3K - 2D
struct KDJJFunction: BuiltinFunction {
    let name = "KDJJ"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KDJJ需要2个参数（N, M）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "KDJJ的参数无效")
        }
        let pn = Int(truncating: n as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pn > 0, pm > 0 else {
            throw InterpreterError(message: "KDJJ的周期必须为正整数")
        }

        let k = MaiB15KDJ.computeK(bars: bars, periodN: pn, periodM: pm)
        let d = MaiB15KDJ.smooth(k, period: pm, weight: 1)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let kv = k[i], let dv = d[i] else { continue }
            result[i] = 3 * kv - 2 * dv
        }
        return result
    }
}

// MARK: - 3. BOLLW

/// BOLLW — 布林带宽度 = (U - L) / M
/// 用于 squeeze 判定（带宽极小时 → 即将爆发）
struct BOLLWFunction: BuiltinFunction {
    let name = "BOLLW"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "BOLLW需要2个参数（N, K）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let kVal = args[1].first, let k = kVal else {
            throw InterpreterError(message: "BOLLW的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BOLLW的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            let mean = sum / Decimal(i - start + 1)
            var sqSum: Decimal = 0
            for j in start...i {
                let d = bars[j].close - mean
                sqSum += d * d
            }
            let variance = sqSum / Decimal(i - start + 1)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0, mean != 0 else { continue }
            let std = Decimal(sqrt(varD))
            result[i] = (2 * k * std) / mean
        }
        return result
    }
}

// MARK: - 4. BOLLPCT

/// BOLLPCT — Bollinger %b = (C - L) / (U - L)
/// 0 = 触下轨 / 1 = 触上轨 / 0.5 = 中线
struct BOLLPCTFunction: BuiltinFunction {
    let name = "BOLLPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "BOLLPCT需要2个参数（N, K）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let kVal = args[1].first, let k = kVal else {
            throw InterpreterError(message: "BOLLPCT的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BOLLPCT的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            let mean = sum / Decimal(i - start + 1)
            var sqSum: Decimal = 0
            for j in start...i {
                let d = bars[j].close - mean
                sqSum += d * d
            }
            let variance = sqSum / Decimal(i - start + 1)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0 else { continue }
            let std = Decimal(sqrt(varD))
            let upper = mean + k * std
            let lower = mean - k * std
            let span = upper - lower
            guard span > 0 else { continue }
            result[i] = (bars[i].close - lower) / span
        }
        return result
    }
}

// MARK: - 5. TYPING

/// TYPING — K 线类型识别
/// 返回值：1=阳线（C>O）/ -1=阴线（C<O）/ 0=十字星（C=O）
struct TYPINGFunction: BuiltinFunction {
    let name = "TYPING"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "TYPING不需要参数")
        }
        return bars.map { bar in
            if bar.close > bar.open { return Optional(Decimal(1)) }
            if bar.close < bar.open { return Optional(Decimal(-1)) }
            return Optional(Decimal(0))
        }
    }
}

// MARK: - 6. MAANGLE

/// MAANGLE — MA 斜率角度（度数）
/// 公式：MA(X, N)[i] - MA(X, N)[i-1] · atan2 → 度
/// 注：x 单位是 1（一根 bar）· 实际度数依赖 y 量级 · trader 通常关心相对值
struct MAANGLEFunction: BuiltinFunction {
    let name = "MAANGLE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAANGLE需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "MAANGLE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MAANGLE的周期必须为正整数")
        }

        let count = source.count
        // MA
        var ma = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = source[j] { sum += v; cnt += 1 }
            }
            if cnt > 0 { ma[i] = sum / Decimal(cnt) }
        }

        // 角度（度数）
        let radToDeg = 180.0 / Double.pi
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = ma[i], let prev = ma[i - 1] else { continue }
            let dy = NSDecimalNumber(decimal: curr - prev).doubleValue
            let angle = atan(dy) * radToDeg
            result[i] = Decimal(angle)
        }
        return result
    }
}

// MARK: - 7. RSIDIV

/// RSIDIV — RSI 差 = RSI(N1) - RSI(N2)
/// 用法：双 RSI 系统 · 短期 RSI 偏离长期 RSI 的程度
struct RSIDIVFunction: BuiltinFunction {
    let name = "RSIDIV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "RSIDIV需要2个参数（N1, N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "RSIDIV的参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "RSIDIV的周期必须为正整数")
        }

        let rsi1 = MaiB15RSI.compute(bars: bars, period: p1)
        let rsi2 = MaiB15RSI.compute(bars: bars, period: p2)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let r1 = rsi1[i], let r2 = rsi2[i] else { continue }
            result[i] = r1 - r2
        }
        return result
    }
}

// MARK: - 内部 helpers

private enum MaiB15KDJ {
    static func computeK(bars: [BarData], periodN: Int, periodM: Int) -> [Decimal?] {
        let count = bars.count
        var rsv = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - periodN + 1)
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0 else { continue }
            rsv[i] = (bars[i].close - lo) / span * 100
        }
        return smooth(rsv, period: periodM, weight: 1)
    }

    static func smooth(_ src: [Decimal?], period: Int, weight: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, weight > 0, count > 0 else { return result }
        let nDec = Decimal(period)
        let mDec = Decimal(weight)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = (mDec * v + (nDec - mDec) * prev!) / nDec
            }
            result[i] = prev
        }
        return result
    }
}

private enum MaiB15RSI {
    static func compute(bars: [BarData], period: Int) -> [Decimal?] {
        let count = bars.count
        var gain = [Decimal?](repeating: nil, count: count)
        var loss = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let diff = bars[i].close - bars[i - 1].close
            gain[i] = diff > 0 ? diff : 0
            loss[i] = diff < 0 ? -diff : 0
        }
        let avgGain = wilder(gain, period: period)
        let avgLoss = wilder(loss, period: period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let g = avgGain[i], let l = avgLoss[i] else { continue }
            if l == 0 {
                result[i] = 100
            } else {
                let rs = g / l
                result[i] = 100 - 100 / (1 + rs)
            }
        }
        return result
    }

    static func wilder(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        let nDec = Decimal(period)
        let alpha = Decimal(1) / nDec
        let oneMinusAlpha = (nDec - 1) / nDec
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = prev! * oneMinusAlpha + v * alpha
            }
            result[i] = prev
        }
        return result
    }
}
