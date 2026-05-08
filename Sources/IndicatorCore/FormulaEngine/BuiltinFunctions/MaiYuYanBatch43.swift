// 麦语言扩展 · 第 43 批（v15.25 batch50 · 现代量化指标）
//
// 7 个函数（trader 现代实战 · LazyBear/Connors/Coppock/Pring/Elder/Schaff）：
//   1. WAVETREND(X, N1, N2)             — LazyBear Wave Trend Oscillator wt1
//   2. SQUEEZEMOM(X, N)                 — LazyBear Squeeze Momentum 近似
//   3. CONNORSRSI(X, N1, N2, N3)        — Connors RSI 三因子均值
//   4. SCHAFFTC(X, fastN, slowN, cycN)  — Schaff Trend Cycle 简化
//   5. ELDERRAY(X, N)                   — Elder Ray Bull/Bear Power（综合）
//   6. COPPOCK(X, N1, N2, N3)           — Coppock Curve
//   7. KST(X, N)                        — Know Sure Thing（自适应 N/2N/3N/4N）

import Foundation

// MARK: - 共用 helper

private func maiB43_ema(_ x: [Decimal?], _ n: Int) -> [Decimal?] {
    let count = x.count
    var result = [Decimal?](repeating: nil, count: count)
    let alpha = Decimal(2) / Decimal(n + 1)
    var prev: Decimal?
    for i in 0..<count {
        guard let v = x[i] else { result[i] = prev; continue }
        if let p = prev {
            prev = alpha * v + (1 - alpha) * p
        } else {
            prev = v
        }
        result[i] = prev
    }
    return result
}

private func maiB43_sma(_ x: [Decimal?], _ n: Int) -> [Decimal?] {
    let count = x.count
    var result = [Decimal?](repeating: nil, count: count)
    for i in 0..<count {
        let s = max(0, i - n + 1)
        var sum: Decimal = 0
        var cnt = 0
        for j in s...i { if let v = x[j] { sum += v; cnt += 1 } }
        if cnt > 0 { result[i] = sum / Decimal(cnt) }
    }
    return result
}

private func maiB43_roc(_ x: [Decimal?], _ n: Int) -> [Decimal?] {
    let count = x.count
    var result = [Decimal?](repeating: nil, count: count)
    for i in n..<count {
        guard let cur = x[i], let prev = x[i - n], prev != 0 else { continue }
        result[i] = (cur - prev) / prev * 100
    }
    return result
}

// MARK: - 1. WAVETREND

/// WAVETREND(X, N1, N2) — LazyBear WT 主线 wt1
/// esa=EMA(X,N1) · d=EMA(|X-esa|,N1) · ci=(X-esa)/(0.015*d) · wt1=EMA(ci,N2)
struct WAVETRENDFunction: BuiltinFunction {
    let name = "WAVETREND"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "WAVETREND需要3个参数（数据, N1, N2）") }
        guard let n1v = args[1].first, let n1 = n1v,
              let n2v = args[2].first, let n2 = n2v else {
            throw InterpreterError(message: "WAVETREND的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0 && p2 > 0 else { throw InterpreterError(message: "WAVETREND的周期必须为正整数") }

        let x = args[0]
        let esa = maiB43_ema(x, p1)
        let absDiff: [Decimal?] = x.indices.map { i in
            guard let v = x[i], let e = esa[i] else { return nil }
            return abs(v - e)
        }
        let d = maiB43_ema(absDiff, p1)
        let ci: [Decimal?] = x.indices.map { i in
            guard let v = x[i], let e = esa[i], let dd = d[i], dd > 0 else { return nil }
            return (v - e) / (Decimal(string: "0.015")! * dd)
        }
        return maiB43_ema(ci, p2)
    }
}

// MARK: - 2. SQUEEZEMOM

/// SQUEEZEMOM(X, N) — Squeeze Momentum 简化版
/// = X - 0.5 * (HHV(X,N) + LLV(X,N)) - 0.5 * SMA(X, N)（去趋势化的振幅动量）
struct SQUEEZEMOMFunction: BuiltinFunction {
    let name = "SQUEEZEMOM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "SQUEEZEMOM需要2个参数（数据, 周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "SQUEEZEMOM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "SQUEEZEMOM的周期必须为正整数") }

        let x = args[0]
        let count = x.count
        let sma = maiB43_sma(x, period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i + 1 >= period, let xi = x[i], let smaI = sma[i] else { continue }
            var hi: Decimal? = nil
            var lo: Decimal? = nil
            var ok = true
            for j in (i - period + 1)...i {
                guard let v = x[j] else { ok = false; break }
                if hi == nil || v > hi! { hi = v }
                if lo == nil || v < lo! { lo = v }
            }
            guard ok, let h = hi, let l = lo else { continue }
            result[i] = xi - (h + l) / 2 / 2 - smaI / 2
        }
        return result
    }
}

// MARK: - 3. CONNORSRSI

/// CONNORSRSI(X, N1, N2, N3) — Connors RSI 三因子均值简化
/// = (RSI(X, N1) + RSI(streak, N2) + PercentRank(ROC, N3)) / 3
/// 其中 streak 是连续涨/跌天数（带符号）
struct CONNORSRSIFunction: BuiltinFunction {
    let name = "CONNORSRSI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 4 else { throw InterpreterError(message: "CONNORSRSI需要4个参数（数据, RSI周期, streak周期, ROC周期）") }
        guard let n1v = args[1].first, let n1 = n1v,
              let n2v = args[2].first, let n2 = n2v,
              let n3v = args[3].first, let n3 = n3v else {
            throw InterpreterError(message: "CONNORSRSI的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        let p3 = Int(truncating: n3 as NSDecimalNumber)
        guard p1 > 0 && p2 > 0 && p3 > 0 else { throw InterpreterError(message: "CONNORSRSI的周期必须为正整数") }

        let x = args[0]
        let count = x.count

        // RSI
        let rsi = maiB43_rsi(x, p1)

        // streak（连涨/连跌天数 · 带符号）
        var streak = [Decimal?](repeating: nil, count: count)
        var s = 0
        for i in 0..<count {
            guard let cur = x[i] else { streak[i] = Decimal(s); continue }
            if i > 0, let prev = x[i - 1] {
                if cur > prev { s = (s >= 0) ? s + 1 : 1 }
                else if cur < prev { s = (s <= 0) ? s - 1 : -1 }
                else { s = 0 }
            }
            streak[i] = Decimal(s)
        }
        let rsiStreak = maiB43_rsi(streak, p2)

        // ROC PercentRank
        let roc = maiB43_roc(x, 1)
        var rocPR = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i + 1 >= p3, let cur = roc[i] else { continue }
            var below = 0
            var total = 0
            for j in (i - p3 + 1)...i {
                if let v = roc[j] {
                    if v < cur { below += 1 }
                    total += 1
                }
            }
            if total > 0 { rocPR[i] = Decimal(below) / Decimal(total) * 100 }
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let r = rsi[i], let rs = rsiStreak[i], let pr = rocPR[i] else { continue }
            result[i] = (r + rs + pr) / 3
        }
        return result
    }
}

private func maiB43_rsi(_ x: [Decimal?], _ n: Int) -> [Decimal?] {
    let count = x.count
    var result = [Decimal?](repeating: nil, count: count)
    var avgGain: Decimal?
    var avgLoss: Decimal?
    let alpha = Decimal(1) / Decimal(n)
    for i in 1..<count {
        guard let cur = x[i], let prev = x[i - 1] else { continue }
        let diff = cur - prev
        let gain = max(diff, 0)
        let loss = max(-diff, 0)
        if let ag = avgGain, let al = avgLoss {
            avgGain = alpha * gain + (1 - alpha) * ag
            avgLoss = alpha * loss + (1 - alpha) * al
        } else {
            avgGain = gain
            avgLoss = loss
        }
        if let ag = avgGain, let al = avgLoss {
            if al == 0 { result[i] = 100 }
            else { result[i] = 100 - 100 / (1 + ag / al) }
        }
    }
    return result
}

// MARK: - 4. SCHAFFTC

/// SCHAFFTC(X, fastN, slowN, cycN) — Schaff Trend Cycle 简化
/// macd=EMA(X,fast)-EMA(X,slow); 然后在 cycN 内做 stochastic 双 stochastic
struct SCHAFFTCFunction: BuiltinFunction {
    let name = "SCHAFFTC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 4 else { throw InterpreterError(message: "SCHAFFTC需要4个参数（数据, 快EMA, 慢EMA, 周期）") }
        guard let fv = args[1].first, let fast = fv,
              let sv = args[2].first, let slow = sv,
              let cv = args[3].first, let cyc = cv else {
            throw InterpreterError(message: "SCHAFFTC的周期参数无效")
        }
        let pf = Int(truncating: fast as NSDecimalNumber)
        let ps = Int(truncating: slow as NSDecimalNumber)
        let pc = Int(truncating: cyc as NSDecimalNumber)
        guard pf > 0 && ps > 0 && pc > 0 else { throw InterpreterError(message: "SCHAFFTC的周期必须为正整数") }

        let x = args[0]
        let efast = maiB43_ema(x, pf)
        let eslow = maiB43_ema(x, ps)
        let count = x.count
        let macd: [Decimal?] = (0..<count).map { i in
            guard let f = efast[i], let s = eslow[i] else { return nil }
            return f - s
        }
        // stoch(macd, pc) → stoch1
        let stoch1 = maiB43_stoch(macd, pc)
        // stoch(stoch1, pc) → stoch2
        return maiB43_stoch(stoch1, pc)
    }
}

private func maiB43_stoch(_ x: [Decimal?], _ n: Int) -> [Decimal?] {
    let count = x.count
    var result = [Decimal?](repeating: nil, count: count)
    for i in 0..<count {
        guard i + 1 >= n, let cur = x[i] else { continue }
        var hi: Decimal?
        var lo: Decimal?
        var ok = true
        for j in (i - n + 1)...i {
            guard let v = x[j] else { ok = false; break }
            if hi == nil || v > hi! { hi = v }
            if lo == nil || v < lo! { lo = v }
        }
        guard ok, let h = hi, let l = lo else { continue }
        let range = h - l
        if range == 0 { result[i] = 50 } else { result[i] = (cur - l) / range * 100 }
    }
    return result
}

// MARK: - 5. ELDERRAY

/// ELDERRAY(X, N) — 综合 Elder Ray = X - EMA(X, N)
/// 正值 = bull power · 负值 = bear power
struct ELDERRAYFunction: BuiltinFunction {
    let name = "ELDERRAY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "ELDERRAY需要2个参数（数据, 周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "ELDERRAY的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "ELDERRAY的周期必须为正整数") }

        let x = args[0]
        let ema = maiB43_ema(x, period)
        var result = [Decimal?](repeating: nil, count: x.count)
        for i in 0..<x.count {
            guard let v = x[i], let e = ema[i] else { continue }
            result[i] = v - e
        }
        return result
    }
}

// MARK: - 6. COPPOCK

/// COPPOCK(X, N1, N2, N3) — Coppock Curve = WMA(ROC(X,N1)+ROC(X,N2), N3)
struct COPPOCKFunction: BuiltinFunction {
    let name = "COPPOCK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 4 else { throw InterpreterError(message: "COPPOCK需要4个参数（数据, N1, N2, WMA周期）") }
        guard let n1v = args[1].first, let n1 = n1v,
              let n2v = args[2].first, let n2 = n2v,
              let n3v = args[3].first, let n3 = n3v else {
            throw InterpreterError(message: "COPPOCK的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        let p3 = Int(truncating: n3 as NSDecimalNumber)
        guard p1 > 0 && p2 > 0 && p3 > 0 else { throw InterpreterError(message: "COPPOCK的周期必须为正整数") }

        let x = args[0]
        let r1 = maiB43_roc(x, p1)
        let r2 = maiB43_roc(x, p2)
        let count = x.count
        let combined: [Decimal?] = (0..<count).map { i in
            guard let a = r1[i], let b = r2[i] else { return nil }
            return a + b
        }
        // WMA(combined, p3)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i + 1 >= p3 else { continue }
            var sum: Decimal = 0
            var weight: Decimal = 0
            var ok = true
            for k in 0..<p3 {
                guard let v = combined[i - p3 + 1 + k] else { ok = false; break }
                let w = Decimal(k + 1)
                sum += w * v
                weight += w
            }
            if ok { result[i] = sum / weight }
        }
        return result
    }
}

// MARK: - 7. KST

/// KST(X, N) — Know Sure Thing 自适应版
/// = SMA(ROC(X,N),10) + 2*SMA(ROC(X,2N),10) + 3*SMA(ROC(X,3N),10) + 4*SMA(ROC(X,4N),15)
struct KSTFunction: BuiltinFunction {
    let name = "KST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "KST需要2个参数（数据, 基础周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "KST的周期参数无效")
        }
        let p = Int(truncating: n as NSDecimalNumber)
        guard p > 0 else { throw InterpreterError(message: "KST的周期必须为正整数") }

        let x = args[0]
        let r1 = maiB43_sma(maiB43_roc(x, p), 10)
        let r2 = maiB43_sma(maiB43_roc(x, 2 * p), 10)
        let r3 = maiB43_sma(maiB43_roc(x, 3 * p), 10)
        let r4 = maiB43_sma(maiB43_roc(x, 4 * p), 15)
        var result = [Decimal?](repeating: nil, count: x.count)
        for i in 0..<x.count {
            guard let a = r1[i], let b = r2[i], let c = r3[i], let d = r4[i] else { continue }
            result[i] = a + 2 * b + 3 * c + 4 * d
        }
        return result
    }
}
