// 麦语言扩展 · 第 18 批（v15.25 batch25 · Keltner / Starc 通道 + 比率 + 周期能量）
//
// 7 个 trader 进阶通道 + 比率函数：
//   1. KELCHM(N)             — Keltner 中线 = EMA(C, N)
//   2. KELCHU(N, M)          — Keltner 上轨 = EMA + M*ATR
//   3. KELCHL(N, M)          — Keltner 下轨 = EMA - M*ATR
//   4. STARCU(N, M)          — Starc 上轨 = MA(C,N) + M*ATR
//   5. STARCL(N, M)          — Starc 下轨 = MA(C,N) - M*ATR
//   6. MAR(X, N)             — Moving Arithmetic Ratio = X / MA(X, N)
//   7. CYCLE(N)              — 周期能量 = (C - LLV(L,N)) / (HHV(H,N) - LLV(L,N))
//
// Keltner vs Starc：Keltner 用 EMA + ATR · Starc 用 SMA + ATR · 二者都比 BOLL 平滑

import Foundation

// MARK: - 1. KELCHM

/// KELCHM — Keltner 中线 = EMA(CLOSE, N)
struct KELCHMFunction: BuiltinFunction {
    let name = "KELCHM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "KELCHM需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "KELCHM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "KELCHM的周期必须为正整数")
        }
        let close = bars.map { Optional($0.close) }
        return MaiB18EMA.ema(close, period: period)
    }
}

// MARK: - 2. KELCHU

/// KELCHU — Keltner 上轨 = EMA(C, N) + M * ATR(N)
struct KELCHUFunction: BuiltinFunction {
    let name = "KELCHU"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KELCHU需要2个参数（N, M）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "KELCHU的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "KELCHU的周期必须为正整数")
        }
        return MaiB18Channel.combine(bars: bars, period: period, multiplier: m, useEMA: true, isUpper: true)
    }
}

// MARK: - 3. KELCHL

/// KELCHL — Keltner 下轨 = EMA(C, N) - M * ATR(N)
struct KELCHLFunction: BuiltinFunction {
    let name = "KELCHL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KELCHL需要2个参数（N, M）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "KELCHL的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "KELCHL的周期必须为正整数")
        }
        return MaiB18Channel.combine(bars: bars, period: period, multiplier: m, useEMA: true, isUpper: false)
    }
}

// MARK: - 4. STARCU

/// STARCU — Starc 上轨 = MA(C, N) + M * ATR(N)
/// 与 Keltner 的差别：Starc 用 SMA · Keltner 用 EMA
struct STARCUFunction: BuiltinFunction {
    let name = "STARCU"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "STARCU需要2个参数（N, M）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "STARCU的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "STARCU的周期必须为正整数")
        }
        return MaiB18Channel.combine(bars: bars, period: period, multiplier: m, useEMA: false, isUpper: true)
    }
}

// MARK: - 5. STARCL

/// STARCL — Starc 下轨 = MA(C, N) - M * ATR(N)
struct STARCLFunction: BuiltinFunction {
    let name = "STARCL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "STARCL需要2个参数（N, M）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "STARCL的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "STARCL的周期必须为正整数")
        }
        return MaiB18Channel.combine(bars: bars, period: period, multiplier: m, useEMA: false, isUpper: false)
    }
}

// MARK: - 6. MAR

/// MAR — Moving Arithmetic Ratio = X / MA(X, N)
/// 1.0 = 等于均线 / > 1 = 高于均线 / < 1 = 低于
/// 与 BIAS 相比 · MAR 是比率（1 周围）· BIAS 是百分比（0 周围）
struct MARFunction: BuiltinFunction {
    let name = "MAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAR需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "MAR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MAR的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let curr = source[i] else { continue }
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = source[j] { sum += v; cnt += 1 }
            }
            guard cnt > 0 else { continue }
            let ma = sum / Decimal(cnt)
            guard ma != 0 else { continue }
            result[i] = curr / ma
        }
        return result
    }
}

// MARK: - 7. CYCLE

/// CYCLE — 周期能量 = (C - LLV(L, N)) / (HHV(H, N) - LLV(L, N))
/// 范围 [0, 1] · 与 STOCH 关系：CYCLE * 100 = STOCH
struct CYCLEFunction: BuiltinFunction {
    let name = "CYCLE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CYCLE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CYCLE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CYCLE的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0 else { continue }
            result[i] = (bars[i].close - lo) / span
        }
        return result
    }
}

// MARK: - 内部 helpers

private enum MaiB18EMA {
    static func ema(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        let multiplier = Decimal(2) / Decimal(period + 1)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = multiplier * v + (1 - multiplier) * prev!
            }
            result[i] = prev
        }
        return result
    }
}

/// Keltner / Starc 通用：mid ± M*ATR · mid 由 EMA 或 SMA 决定
private enum MaiB18Channel {
    static func combine(
        bars: [BarData],
        period: Int,
        multiplier: Decimal,
        useEMA: Bool,
        isUpper: Bool
    ) -> [Decimal?] {
        let count = bars.count

        // mid
        let close = bars.map { Optional($0.close) }
        var mid: [Decimal?]
        if useEMA {
            mid = MaiB18EMA.ema(close, period: period)
        } else {
            mid = [Decimal?](repeating: nil, count: count)
            for i in 0..<count {
                let start = max(0, i - period + 1)
                var sum: Decimal = 0
                for j in start...i { sum += bars[j].close }
                mid[i] = sum / Decimal(i - start + 1)
            }
        }

        // ATR
        var tr = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let h = bars[i].high
            let l = bars[i].low
            if i == 0 {
                tr[i] = h - l
            } else {
                let prevC = bars[i - 1].close
                let hl = h - l
                let hPrevC = abs(h - prevC)
                let lPrevC = abs(l - prevC)
                tr[i] = max(max(hl, hPrevC), lPrevC)
            }
        }
        var atr = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = tr[j] { sum += v; cnt += 1 }
            }
            if cnt > 0 { atr[i] = sum / Decimal(cnt) }
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let m = mid[i], let a = atr[i] else { continue }
            result[i] = isUpper ? (m + multiplier * a) : (m - multiplier * a)
        }
        return result
    }
}
