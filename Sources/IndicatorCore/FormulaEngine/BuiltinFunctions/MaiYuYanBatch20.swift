// 麦语言扩展 · 第 20 批（v15.25 batch27 · 实用辅助 + 累计函数）
//
// 7 个实用辅助函数（trader 写公式常用）：
//   1. CLAMPMIN(X, min)  — max(X, min) · 下限保护
//   2. CLAMPMAX(X, max)  — min(X, max) · 上限保护
//   3. SAFEDIV(X, Y, D)  — Y != 0 时 X/Y · 否则 D
//   4. NAFILL(X, D)      — nil 时返 D
//   5. CUMSUM(X)         — 累加（含 nil 跳过）
//   6. CUMPROD(X)        — 累乘
//   7. MAXIDX(X, N)      — N 内最大值的偏移（0=当前根 / N-1=N根前）

import Foundation

// MARK: - 1. CLAMPMIN

/// CLAMPMIN(X, min) = max(X, min)
struct CLAMPMINFunction: BuiltinFunction {
    let name = "CLAMPMIN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CLAMPMIN需要2个参数（X, min）")
        }
        let source = args[0]
        guard let mVal = args[1].first, let minVal = mVal else {
            throw InterpreterError(message: "CLAMPMIN的min参数无效")
        }
        return source.map { v in
            guard let v else { return nil }
            return v < minVal ? minVal : v
        }
    }
}

// MARK: - 2. CLAMPMAX

/// CLAMPMAX(X, max) = min(X, max)
struct CLAMPMAXFunction: BuiltinFunction {
    let name = "CLAMPMAX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CLAMPMAX需要2个参数（X, max）")
        }
        let source = args[0]
        guard let mVal = args[1].first, let maxVal = mVal else {
            throw InterpreterError(message: "CLAMPMAX的max参数无效")
        }
        return source.map { v in
            guard let v else { return nil }
            return v > maxVal ? maxVal : v
        }
    }
}

// MARK: - 3. SAFEDIV

/// SAFEDIV(X, Y, default) - Y != 0 时 X/Y · 否则 default
struct SAFEDIVFunction: BuiltinFunction {
    let name = "SAFEDIV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "SAFEDIV需要3个参数（X, Y, default）")
        }
        let x = args[0]
        let y = args[1]
        guard let dVal = args[2].first, let defaultVal = dVal else {
            throw InterpreterError(message: "SAFEDIV的default参数无效")
        }
        guard x.count == y.count else {
            throw InterpreterError(message: "SAFEDIV的X和Y长度必须一致")
        }

        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let xv = x[i] else { continue }
            if let yv = y[i], yv != 0 {
                result[i] = xv / yv
            } else {
                result[i] = defaultVal
            }
        }
        return result
    }
}

// MARK: - 4. NAFILL

/// NAFILL(X, default) - nil 时返 default
struct NAFILLFunction: BuiltinFunction {
    let name = "NAFILL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "NAFILL需要2个参数（X, default）")
        }
        let source = args[0]
        guard let dVal = args[1].first, let defaultVal = dVal else {
            throw InterpreterError(message: "NAFILL的default参数无效")
        }
        return source.map { v in v ?? defaultVal }
    }
}

// MARK: - 5. CUMSUM

/// CUMSUM(X) - 累加（nil 跳过）
struct CUMSUMFunction: BuiltinFunction {
    let name = "CUMSUM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CUMSUM需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var cum: Decimal = 0
        for i in 0..<count {
            if let v = source[i] {
                cum += v
            }
            result[i] = cum
        }
        return result
    }
}

// MARK: - 6. CUMPROD

/// CUMPROD(X) - 累乘（nil 跳过 · 起始 = 1）
struct CUMPRODFunction: BuiltinFunction {
    let name = "CUMPROD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CUMPROD需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var cum: Decimal = 1
        for i in 0..<count {
            if let v = source[i] {
                cum *= v
            }
            result[i] = cum
        }
        return result
    }
}

// MARK: - 7. MAXIDX

/// MAXIDX(X, N) - N 内最大值的偏移（0=当前根 · N-1=最早一根）
/// 用途：与 LASTPEAK 配合 · 找最近峰位置
struct MAXIDXFunction: BuiltinFunction {
    let name = "MAXIDX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAXIDX需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "MAXIDX的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MAXIDX的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var maxVal: Decimal?
            var maxJ: Int = start
            for j in start...i {
                guard let v = source[j] else { continue }
                if maxVal == nil || v > maxVal! { maxVal = v; maxJ = j }
            }
            guard maxVal != nil else { continue }
            result[i] = Decimal(i - maxJ)
        }
        return result
    }
}
