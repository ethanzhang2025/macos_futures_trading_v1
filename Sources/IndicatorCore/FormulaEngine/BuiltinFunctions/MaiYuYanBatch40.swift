// 麦语言扩展 · 第 40 批（v15.25 batch47 · Hilbert 变换 · Ehlers 风格简化版）
//
// 7 个函数（TA-Lib HT_* 标配 · 用于周期分析）：
//   1. HT_TRENDLINE(X)   — 7 期加权 trendline（权重 1..7）
//   2. HT_PHASOR(X)      — 复数相量振幅 sqrt(I² + Q²)
//   3. HT_DCPHASE(X)     — 主导周期相位（度 · 范围 (-180, 180]）
//   4. HT_DCPERIOD(X)    — 主导周期长度（bars）
//   5. HT_SINE(X)        — 主导周期正弦 sin(DCPHASE)
//   6. HT_LEADSINE(X)    — 导引正弦 sin(DCPHASE + 45°)
//   7. HT_TRENDMODE(X)   — 趋势/周期模式（1=趋势 0=周期）
//
// 简化说明：完整 Ehlers Hilbert 变换需 4 阶 IIR 滤波器 + 状态机，本实现
// 用 4 期 in-phase / 90° 相位差 quadrature 近似（trader 实战足够）。

import Foundation

// MARK: - 共用 helper

/// 简化 Hilbert 变换：返回 (I, Q)
///   I = X[i] - X[i-3]      (in-phase 60° 滞后)
///   Q = X[i-1] - X[i-2]    (quadrature ~90° 滞后)
private func maiB40_iq(_ x: [Decimal?], at i: Int) -> (Decimal, Decimal)? {
    guard i >= 3 else { return nil }
    guard let p0 = x[i], let p1 = x[i-1], let p2 = x[i-2], let p3 = x[i-3] else { return nil }
    return (p0 - p3, p1 - p2)
}

/// DCPHASE 度数（用于多个函数共享）
private func maiB40_dcPhaseDegree(_ x: [Decimal?], at i: Int) -> Decimal? {
    guard let (iq, qq) = maiB40_iq(x, at: i) else { return nil }
    let dI = NSDecimalNumber(decimal: iq).doubleValue
    let dQ = NSDecimalNumber(decimal: qq).doubleValue
    if dI == 0 && dQ == 0 { return Decimal(0) }
    return Decimal(atan2(dQ, dI) * 180.0 / .pi)
}

// MARK: - 1. HT_TRENDLINE

/// HT_TRENDLINE(X) — 7 期加权趋势线（Ehlers 风格 · 权重 1..7 · 归一 1/28）
struct HT_TRENDLINEFunction: BuiltinFunction {
    let name = "HT_TRENDLINE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_TRENDLINE需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i >= 6 else { continue }
            var sum: Decimal = 0
            var ok = true
            for k in 0...6 {
                guard let v = x[i - 6 + k] else { ok = false; break }
                sum += Decimal(k + 1) * v
            }
            if ok { result[i] = sum / 28 }
        }
        return result
    }
}

// MARK: - 2. HT_PHASOR

/// HT_PHASOR(X) — 相量振幅 = sqrt(I² + Q²)
struct HT_PHASORFunction: BuiltinFunction {
    let name = "HT_PHASOR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_PHASOR需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let (iq, qq) = maiB40_iq(x, at: i) else { continue }
            let dI = NSDecimalNumber(decimal: iq).doubleValue
            let dQ = NSDecimalNumber(decimal: qq).doubleValue
            result[i] = Decimal((dI * dI + dQ * dQ).squareRoot())
        }
        return result
    }
}

// MARK: - 3. HT_DCPHASE

/// HT_DCPHASE(X) — 主导周期相位（度数 (-180, 180]）
struct HT_DCPHASEFunction: BuiltinFunction {
    let name = "HT_DCPHASE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_DCPHASE需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            result[i] = maiB40_dcPhaseDegree(x, at: i)
        }
        return result
    }
}

// MARK: - 4. HT_DCPERIOD

/// HT_DCPERIOD(X) — 主导周期长度（bars · 基于近 5 根相位差均值）
struct HT_DCPERIODFunction: BuiltinFunction {
    let name = "HT_DCPERIOD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_DCPERIOD需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var phases = [Double?](repeating: nil, count: count)
        for i in 0..<count {
            if let ph = maiB40_dcPhaseDegree(x, at: i) {
                phases[i] = NSDecimalNumber(decimal: ph).doubleValue
            }
        }
        var result = [Decimal?](repeating: nil, count: count)
        let lookback = 5
        for i in 0..<count {
            guard i >= lookback else { continue }
            var diffs: [Double] = []
            for k in (i - lookback + 1)...i {
                guard k >= 1, let cur = phases[k], let prev = phases[k - 1] else { continue }
                var d = cur - prev
                if d < 0 { d += 360 }
                if d > 0.0001 { diffs.append(d) }
            }
            guard !diffs.isEmpty else { continue }
            let mean = diffs.reduce(0, +) / Double(diffs.count)
            let period = 360.0 / mean
            // 限制 period 在 [6, 50] 区间（Ehlers 推荐）
            result[i] = Decimal(min(50.0, max(6.0, period)))
        }
        return result
    }
}

// MARK: - 5. HT_SINE

/// HT_SINE(X) — 主导周期正弦
struct HT_SINEFunction: BuiltinFunction {
    let name = "HT_SINE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_SINE需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let phDeg = maiB40_dcPhaseDegree(x, at: i) else { continue }
            let rad = NSDecimalNumber(decimal: phDeg).doubleValue * .pi / 180.0
            result[i] = Decimal(sin(rad))
        }
        return result
    }
}

// MARK: - 6. HT_LEADSINE

/// HT_LEADSINE(X) — 导引正弦 sin(DCPHASE + 45°)
struct HT_LEADSINEFunction: BuiltinFunction {
    let name = "HT_LEADSINE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_LEADSINE需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let phDeg = maiB40_dcPhaseDegree(x, at: i) else { continue }
            let rad = (NSDecimalNumber(decimal: phDeg).doubleValue + 45.0) * .pi / 180.0
            result[i] = Decimal(sin(rad))
        }
        return result
    }
}

// MARK: - 7. HT_TRENDMODE

/// HT_TRENDMODE(X) — 1=趋势 0=周期（基于 |X - HT_TRENDLINE| > STD(X, 20)）
struct HT_TRENDMODEFunction: BuiltinFunction {
    let name = "HT_TRENDMODE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HT_TRENDMODE需要1个参数（数据序列）") }
        let x = args[0]
        let count = x.count
        var trendline = [Decimal?](repeating: nil, count: count)
        for i in 6..<count {
            var sum: Decimal = 0
            var ok = true
            for k in 0...6 {
                guard let v = x[i - 6 + k] else { ok = false; break }
                sum += Decimal(k + 1) * v
            }
            if ok { trendline[i] = sum / 28 }
        }
        // 滚动 STD（20）
        let stdN = 20
        var std = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - stdN + 1)
            var vals: [Decimal] = []
            for j in s...i { if let v = x[j] { vals.append(v) } }
            guard vals.count >= 2 else { continue }
            let mean = vals.reduce(Decimal(0), +) / Decimal(vals.count)
            var ss: Decimal = 0
            for v in vals { let d = v - mean; ss += d * d }
            let variance = ss / Decimal(vals.count)
            let dv = NSDecimalNumber(decimal: variance).doubleValue
            std[i] = Decimal(dv.squareRoot())
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let xi = x[i], let tl = trendline[i], let sd = std[i] else { continue }
            let dev = abs(xi - tl)
            result[i] = (dev > sd) ? 1 : 0
        }
        return result
    }
}
