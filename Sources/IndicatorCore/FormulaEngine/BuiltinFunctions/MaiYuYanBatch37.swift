// 麦语言扩展 · 第 37 批（v15.25 batch44 · 高级均值 + 价格指数化）
//
// 7 个高级均值 / 标准化函数：
//   1. HARMONICMEAN(X, N)  — 调和平均 = N / sum(1/X)
//   2. GEOMEAN(X, N)       — 几何平均 = exp(mean(ln(X)))
//   3. POWMEAN(X, N, p)    — 幂均值 = (mean(X^p))^(1/p)
//   4. RMS(X, N)           — 平方根均值 = sqrt(mean(X²))
//   5. RANGEMID(N)         — 中价 (HHV+LLV)/2（与 ICHITENKAN 同公式 · 别名风格）
//   6. PRICESCORE(X, lo, hi) — X 在 [lo, hi] 内的标准化（0-1）
//   7. INDEXED(X, N)       — 指数化 = X[i] / X[i-N] * 100（基期=N 根前）

import Foundation

// MARK: - 1. HARMONICMEAN

struct HARMONICMEANFunction: BuiltinFunction {
    let name = "HARMONICMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "HARMONICMEAN需要2个参数（X, N）") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "HARMONICMEAN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "HARMONICMEAN的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var invSum: Decimal = 0
            var cnt = 0
            for j in s...i {
                guard let v = source[j], v != 0 else { continue }
                invSum += 1 / v
                cnt += 1
            }
            guard cnt > 0, invSum != 0 else { continue }
            result[i] = Decimal(cnt) / invSum
        }
        return result
    }
}

// MARK: - 2. GEOMEAN

struct GEOMEANFunction: BuiltinFunction {
    let name = "GEOMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "GEOMEAN需要2个参数（X, N）") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "GEOMEAN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "GEOMEAN的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var logSum: Double = 0
            var cnt = 0
            for j in s...i {
                guard let v = source[j], v > 0 else { continue }
                let vd = NSDecimalNumber(decimal: v).doubleValue
                logSum += log(vd)
                cnt += 1
            }
            guard cnt > 0 else { continue }
            result[i] = Decimal(exp(logSum / Double(cnt)))
        }
        return result
    }
}

// MARK: - 3. POWMEAN

/// POWMEAN(X, N, p) — 幂均值
/// p=1 算术 / p=-1 调和 / p=0 几何 / p=2 RMS
struct POWMEANFunction: BuiltinFunction {
    let name = "POWMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "POWMEAN需要3个参数（X, N, p）") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal,
              let pVal = args[2].first, let p = pVal else {
            throw InterpreterError(message: "POWMEAN的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "POWMEAN的周期必须为正整数") }
        let pD = NSDecimalNumber(decimal: p).doubleValue

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var values: [Double] = []
            for j in s...i {
                guard let v = source[j], v > 0 else { continue }
                values.append(NSDecimalNumber(decimal: v).doubleValue)
            }
            guard !values.isEmpty else { continue }

            if abs(pD) < 1e-9 {
                // p=0 几何均值
                var logSum: Double = 0
                for v in values { logSum += log(v) }
                result[i] = Decimal(exp(logSum / Double(values.count)))
            } else {
                var sum: Double = 0
                for v in values { sum += pow(v, pD) }
                let mean = sum / Double(values.count)
                guard mean >= 0 else { continue }
                result[i] = Decimal(pow(mean, 1.0 / pD))
            }
        }
        return result
    }
}

// MARK: - 4. RMS

struct RMSFunction: BuiltinFunction {
    let name = "RMS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "RMS需要2个参数（X, N）") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "RMS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "RMS的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sqSum: Decimal = 0
            var cnt = 0
            for j in s...i {
                if let v = source[j] {
                    sqSum += v * v
                    cnt += 1
                }
            }
            guard cnt > 0 else { continue }
            let mean = sqSum / Decimal(cnt)
            let meanD = NSDecimalNumber(decimal: mean).doubleValue
            guard meanD >= 0 else { continue }
            result[i] = Decimal(sqrt(meanD))
        }
        return result
    }
}

// MARK: - 5. RANGEMID

/// RANGEMID(N) — 中价 (HHV+LLV)/2 · 与 ICHITENKAN 等价
struct RANGEMIDFunction: BuiltinFunction {
    let name = "RANGEMID"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "RANGEMID需要1个参数（周期N）") }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "RANGEMID的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "RANGEMID的周期必须为正整数") }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var hi = bars[s].high
            var lo = bars[s].low
            for j in s...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            result[i] = (hi + lo) / 2
        }
        return result
    }
}

// MARK: - 6. PRICESCORE

/// PRICESCORE(X, lo, hi) — X 在 [lo, hi] 内标准化（< lo 返 0 / > hi 返 1 / 之间线性）
struct PRICESCOREFunction: BuiltinFunction {
    let name = "PRICESCORE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "PRICESCORE需要3个参数（X, lo, hi）") }
        let source = args[0]
        guard let loV = args[1].first, let lo = loV,
              let hiV = args[2].first, let hi = hiV else {
            throw InterpreterError(message: "PRICESCORE的参数无效")
        }
        let span = hi - lo
        guard span > 0 else { throw InterpreterError(message: "PRICESCORE的 hi 必须 > lo") }

        return source.map { v in
            guard let v else { return nil }
            if v <= lo { return 0 }
            if v >= hi { return 1 }
            return (v - lo) / span
        }
    }
}

// MARK: - 7. INDEXED

/// INDEXED(X, N) — 指数化 = X[i] / X[i-N] * 100（基期 = N 根前）
struct INDEXEDFunction: BuiltinFunction {
    let name = "INDEXED"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "INDEXED需要2个参数（X, N）") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "INDEXED的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period >= 0 else { throw InterpreterError(message: "INDEXED的周期必须 >= 0") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            guard let curr = source[i], let base = source[i - period], base != 0 else { continue }
            result[i] = curr / base * 100
        }
        return result
    }
}
