// 麦语言扩展 · 第 19 批（v15.25 batch26 · Bill Williams + 统计归一化）
//
// 7 个统计归一化 + 趋势识别函数：
//   1. MARKETFI()        — Bill Williams Market Facilitation Index = (H-L)/V
//   2. CHOPPINESS(N)     — Choppiness Index · 趋势 vs 横盘判定
//   3. EFI(N)            — Elder Force Index = EMA((C-prevC)*V, N)
//   4. PERCENTRANK(X, N) — N 周期内当前 X 的百分位 · 范围 [0, 100]
//   5. ZSCORE(X, N)      — Z-score = (X - mean) / std
//   6. NORM(X, N)        — 归一化 [0, 1] = (X - LLV) / (HHV - LLV)
//   7. EMD(N1, N2)       — EMA Diff = EMA(C, N1) - EMA(C, N2)（与 MACDDIF 等价但参数语义不同）

import Foundation

// MARK: - 1. MARKETFI

/// MARKETFI — Bill Williams Market Facilitation Index
/// 公式：(HIGH - LOW) / VOLUME
/// 用途：与 V 配合判断市场效率（价动 vs 量小）
struct MARKETFIFunction: BuiltinFunction {
    let name = "MARKETFI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "MARKETFI不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let v = Decimal(bars[i].volume)
            guard v > 0 else { continue }
            result[i] = (bars[i].high - bars[i].low) / v
        }
        return result
    }
}

// MARK: - 2. CHOPPINESS

/// CHOPPINESS — Choppiness Index (Bill Dreiss)
/// 公式：CI = 100 * log10(SUM(TR, N) / (HHV(H, N) - LLV(L, N))) / log10(N)
/// 范围 [0, 100] · > 60 横盘 / < 38 强趋势
struct CHOPPINESSFunction: BuiltinFunction {
    let name = "CHOPPINESS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CHOPPINESS需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CHOPPINESS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else {
            throw InterpreterError(message: "CHOPPINESS的周期必须 > 1")
        }

        let count = bars.count
        // TR
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

        let logN = log10(Double(period))
        guard logN > 0 else { return tr }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var trSum: Decimal = 0
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if let t = tr[j] { trSum += t }
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0, trSum > 0 else { continue }
            let ratio = NSDecimalNumber(decimal: trSum / span).doubleValue
            guard ratio > 0 else { continue }
            let ci = 100 * log10(ratio) / logN
            result[i] = Decimal(ci)
        }
        return result
    }
}

// MARK: - 3. EFI

/// EFI — Elder Force Index
/// 公式：EMA((C - REF(C, 1)) * V, N)
/// 用途：量价综合 · 上穿 0 多头 / 下穿 0 空头
struct EFIFunction: BuiltinFunction {
    let name = "EFI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "EFI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "EFI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "EFI的周期必须为正整数")
        }

        let count = bars.count
        var raw = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            raw[i] = (bars[i].close - bars[i - 1].close) * Decimal(bars[i].volume)
        }
        return MaiB19EMA.ema(raw, period: period)
    }
}

// MARK: - 4. PERCENTRANK

/// PERCENTRANK — N 周期内 X 的百分位（含当前根）
/// 公式：count(X[j] <= X[i] for j in window) / N * 100
/// 范围 [0, 100]
struct PERCENTRANKFunction: BuiltinFunction {
    let name = "PERCENTRANK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "PERCENTRANK需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "PERCENTRANK的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PERCENTRANK的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let curr = source[i] else { continue }
            let start = max(0, i - period + 1)
            var leOrEq = 0
            var total = 0
            for j in start...i {
                guard let v = source[j] else { continue }
                total += 1
                if v <= curr { leOrEq += 1 }
            }
            guard total > 0 else { continue }
            result[i] = Decimal(leOrEq) / Decimal(total) * 100
        }
        return result
    }
}

// MARK: - 5. ZSCORE

/// ZSCORE — Z-score = (X - mean) / std
/// 用途：标准化 · 距均值多少个 std
struct ZSCOREFunction: BuiltinFunction {
    let name = "ZSCORE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "ZSCORE需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "ZSCORE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ZSCORE的周期必须为正整数")
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
            guard cnt >= 2 else { continue }
            let mean = sum / Decimal(cnt)
            var sqSum: Decimal = 0
            for j in start...i {
                if let v = source[j] { sqSum += (v - mean) * (v - mean) }
            }
            let variance = sqSum / Decimal(cnt)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD > 0 else { continue }
            let std = Decimal(sqrt(varD))
            guard std > 0 else { continue }
            result[i] = (curr - mean) / std
        }
        return result
    }
}

// MARK: - 6. NORM

/// NORM — 归一化到 [0, 1] = (X - LLV(X, N)) / (HHV(X, N) - LLV(X, N))
/// 与 CYCLE 思路类似但用任意 X · 不限 close
struct NORMFunction: BuiltinFunction {
    let name = "NORM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "NORM需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "NORM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "NORM的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let curr = source[i] else { continue }
            let start = max(0, i - period + 1)
            var hi: Decimal?
            var lo: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if hi == nil || v > hi! { hi = v }
                if lo == nil || v < lo! { lo = v }
            }
            guard let h = hi, let l = lo else { continue }
            let span = h - l
            guard span > 0 else {
                result[i] = 0.5  // 全相等时取中点
                continue
            }
            result[i] = (curr - l) / span
        }
        return result
    }
}

// MARK: - 7. EMD

/// EMD — EMA Diff = EMA(C, N1) - EMA(C, N2)
/// 与 MACDDIF 等价但参数语义不限于 12/26
struct EMDFunction: BuiltinFunction {
    let name = "EMD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "EMD需要2个参数（N1, N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "EMD的参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "EMD的周期必须为正整数")
        }

        let close = bars.map { Optional($0.close) }
        let e1 = MaiB19EMA.ema(close, period: p1)
        let e2 = MaiB19EMA.ema(close, period: p2)

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let v1 = e1[i], let v2 = e2[i] else { continue }
            result[i] = v1 - v2
        }
        return result
    }
}

// MARK: - 内部 EMA helper

private enum MaiB19EMA {
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
