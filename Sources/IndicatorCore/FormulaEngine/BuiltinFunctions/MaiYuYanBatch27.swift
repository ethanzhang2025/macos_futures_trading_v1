// 麦语言扩展 · 第 27 批（v15.25 batch34 · 数据预处理 + 高级统计）
//
// 7 个数据预处理 / 高级统计函数：
//   1. PCTRETURN(X, N)   — N 周期百分比收益 = (X - REF(X,N)) / REF(X,N)
//   2. LOGRETURN(X)      — log return = ln(X / REF(X,1))
//   3. DETREND(X, N)     — 去趋势 = X - MA(X, N)
//   4. KURT(X, N)        — 峰度（Excess Kurtosis）
//   5. SKEW(X, N)        — 偏度
//   6. SHARPE(X, N)      — 简化 Sharpe = mean(returns) / std(returns)
//   7. ANNUALSTD(X, N)   — 年化标准差 = STD(X, N) * sqrt(252)

import Foundation

// MARK: - 1. PCTRETURN

/// PCTRETURN(X, N) — N 周期百分比收益
struct PCTRETURNFunction: BuiltinFunction {
    let name = "PCTRETURN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "PCTRETURN需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "PCTRETURN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PCTRETURN的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            guard let curr = source[i], let prev = source[i - period], prev != 0 else { continue }
            result[i] = (curr - prev) / prev
        }
        return result
    }
}

// MARK: - 2. LOGRETURN

/// LOGRETURN(X) — log return = ln(X / REF(X, 1))
struct LOGRETURNFunction: BuiltinFunction {
    let name = "LOGRETURN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "LOGRETURN需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1], prev > 0 else { continue }
            let ratio = curr / prev
            let ratioD = NSDecimalNumber(decimal: ratio).doubleValue
            guard ratioD > 0 else { continue }
            result[i] = Decimal(log(ratioD))
        }
        return result
    }
}

// MARK: - 3. DETREND

/// DETREND(X, N) — 去趋势 = X - MA(X, N)
struct DETRENDFunction: BuiltinFunction {
    let name = "DETREND"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "DETREND需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "DETREND的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DETREND的周期必须为正整数")
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
            result[i] = curr - ma
        }
        return result
    }
}

// MARK: - 4. KURT

/// KURT(X, N) — 峰度（Excess Kurtosis · 正态分布峰度=0 · 厚尾>0 · 平峰<0）
struct KURTFunction: BuiltinFunction {
    let name = "KURT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KURT需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "KURT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "KURT的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var values: [Decimal] = []
            for j in start...i {
                if let v = source[j] { values.append(v) }
            }
            guard values.count >= 4 else { continue }
            let nDec = Decimal(values.count)
            let mean = values.reduce(Decimal(0), +) / nDec
            var m2: Decimal = 0
            var m4: Decimal = 0
            for v in values {
                let d = v - mean
                let d2 = d * d
                m2 += d2
                m4 += d2 * d2
            }
            m2 /= nDec
            m4 /= nDec
            guard m2 > 0 else { continue }
            // Excess kurtosis = m4/m2² - 3
            result[i] = m4 / (m2 * m2) - 3
        }
        return result
    }
}

// MARK: - 5. SKEW

/// SKEW(X, N) — 偏度（正偏=右尾长 · 负偏=左尾长 · 正态=0）
struct SKEWFunction: BuiltinFunction {
    let name = "SKEW"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SKEW需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "SKEW的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "SKEW的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var values: [Decimal] = []
            for j in start...i {
                if let v = source[j] { values.append(v) }
            }
            guard values.count >= 3 else { continue }
            let nDec = Decimal(values.count)
            let mean = values.reduce(Decimal(0), +) / nDec
            var m2: Decimal = 0
            var m3: Decimal = 0
            for v in values {
                let d = v - mean
                m2 += d * d
                m3 += d * d * d
            }
            m2 /= nDec
            m3 /= nDec
            guard m2 > 0 else { continue }
            // skewness = m3 / m2^(3/2)
            let m2D = NSDecimalNumber(decimal: m2).doubleValue
            let denom = pow(m2D, 1.5)
            guard denom > 0 else { continue }
            let m3D = NSDecimalNumber(decimal: m3).doubleValue
            result[i] = Decimal(m3D / denom)
        }
        return result
    }
}

// MARK: - 6. SHARPE

/// SHARPE(X, N) — 简化 Sharpe = mean(returns) / std(returns)
/// 注：未减无风险收益（trader 自己若需要可减）
struct SHARPEFunction: BuiltinFunction {
    let name = "SHARPE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SHARPE需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "SHARPE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "SHARPE的周期必须为正整数")
        }

        // 先算 returns = (X - REF(X,1)) / REF(X,1)
        let count = source.count
        var ret = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1], prev != 0 else { continue }
            ret[i] = (curr - prev) / prev
        }

        // mean / std
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(1, i - period + 1)
            guard start <= i else { continue }
            var values: [Decimal] = []
            for j in start...i {
                if let v = ret[j] { values.append(v) }
            }
            guard values.count >= 2 else { continue }
            let nDec = Decimal(values.count)
            let mean = values.reduce(Decimal(0), +) / nDec
            var sq: Decimal = 0
            for v in values { sq += (v - mean) * (v - mean) }
            let variance = sq / nDec
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD > 0 else { continue }
            let std = Decimal(sqrt(varD))
            guard std > 0 else { continue }
            result[i] = mean / std
        }
        return result
    }
}

// MARK: - 7. ANNUALSTD

/// ANNUALSTD(X, N) — 年化标准差 = STD(X, N) * sqrt(252)
/// 期货 / 股票按 252 个交易日年化
struct ANNUALSTDFunction: BuiltinFunction {
    let name = "ANNUALSTD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "ANNUALSTD需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "ANNUALSTD的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ANNUALSTD的周期必须为正整数")
        }

        let count = source.count
        let annualFactor = Decimal(sqrt(252.0))
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var values: [Decimal] = []
            for j in start...i {
                if let v = source[j] { values.append(v) }
            }
            guard values.count >= 2 else { continue }
            let nDec = Decimal(values.count)
            let mean = values.reduce(Decimal(0), +) / nDec
            var sq: Decimal = 0
            for v in values { sq += (v - mean) * (v - mean) }
            let variance = sq / nDec
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0 else { continue }
            let std = Decimal(sqrt(varD))
            result[i] = std * annualFactor
        }
        return result
    }
}
