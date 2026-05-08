// 麦语言扩展 · 第 32 批（v15.25 batch39 · 线性回归 4 件套 + 加权平均）
//
// 7 个回归 / 加权函数：
//   1. LINREGR(X, N)        — 线性回归在 i 处的预测值（与 FORCAST 同模式但内部独立）
//   2. LINREGSLOPE(X, N)    — 线性回归斜率
//   3. LINREGINT(X, N)      — 线性回归截距
//   4. LINREGR2(X, N)       — 决定系数 R²（拟合优度）
//   5. TRIMA(X, N)          — 三角加权移动平均（中间根权重大）
//   6. EXPSMOOTHING(X, A)   — 指数平滑（与 EMA 类似但 alpha 直接给）
//   7. WEIGHTEDMEAN(X, W, N) — 加权平均（X 是 series · W 是 series 权重）

import Foundation

// MARK: - 1. LINREGR

/// LINREGR(X, N) — 线性回归在 i 处的预测值
/// 公式：a*i_local + b · 其中 (a, b) 是 N 个点的回归系数
struct LINREGRFunction: BuiltinFunction {
    let name = "LINREGR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "LINREGR需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LINREGR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LINREGR的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            guard let coef = MaiB32Reg.linreg(source: source, start: start, end: i) else { continue }
            let len = i - start + 1
            // 在 i_local = len - 1 处的预测
            result[i] = coef.slope * Decimal(len - 1) + coef.intercept
        }
        return result
    }
}

// MARK: - 2. LINREGSLOPE

/// LINREGSLOPE(X, N) — 线性回归斜率
struct LINREGSLOPEFunction: BuiltinFunction {
    let name = "LINREGSLOPE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "LINREGSLOPE需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LINREGSLOPE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LINREGSLOPE的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            guard let coef = MaiB32Reg.linreg(source: source, start: start, end: i) else { continue }
            result[i] = coef.slope
        }
        return result
    }
}

// MARK: - 3. LINREGINT

/// LINREGINT(X, N) — 线性回归截距（窗口起点的预测值）
struct LINREGINTFunction: BuiltinFunction {
    let name = "LINREGINT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "LINREGINT需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LINREGINT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LINREGINT的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            guard let coef = MaiB32Reg.linreg(source: source, start: start, end: i) else { continue }
            result[i] = coef.intercept
        }
        return result
    }
}

// MARK: - 4. LINREGR2

/// LINREGR2(X, N) — 决定系数 R²
/// 公式：R² = 1 - SSres / SStot
/// 范围 [0, 1] · 越接近 1 拟合越好
struct LINREGR2Function: BuiltinFunction {
    let name = "LINREGR2"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "LINREGR2需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LINREGR2的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LINREGR2的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            guard let coef = MaiB32Reg.linreg(source: source, start: start, end: i) else { continue }
            // 收集 values
            var values: [(Int, Decimal)] = []
            for j in start...i {
                if let v = source[j] {
                    values.append((j - start, v))
                }
            }
            guard values.count >= 2 else { continue }
            let nDec = Decimal(values.count)
            let yMean = values.map(\.1).reduce(Decimal(0), +) / nDec
            var ssRes: Decimal = 0
            var ssTot: Decimal = 0
            for (xi, y) in values {
                let yhat = coef.slope * Decimal(xi) + coef.intercept
                let resid = y - yhat
                ssRes += resid * resid
                let tot = y - yMean
                ssTot += tot * tot
            }
            guard ssTot > 0 else { continue }
            result[i] = 1 - ssRes / ssTot
        }
        return result
    }
}

// MARK: - 5. TRIMA

/// TRIMA(X, N) — 三角加权移动平均
/// 公式：权重 1, 2, ..., (N+1)/2, ..., 2, 1（中间最大）
struct TRIMAFunction: BuiltinFunction {
    let name = "TRIMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "TRIMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "TRIMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TRIMA的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            let len = i - start + 1
            var sum: Decimal = 0
            var weightSum: Decimal = 0
            for k in 0..<len {
                guard let v = source[start + k] else { continue }
                // 三角权重：min(k+1, len-k)
                let weight = Decimal(min(k + 1, len - k))
                sum += v * weight
                weightSum += weight
            }
            guard weightSum > 0 else { continue }
            result[i] = sum / weightSum
        }
        return result
    }
}

// MARK: - 6. EXPSMOOTHING

/// EXPSMOOTHING(X, alpha) — 指数平滑（alpha 直接给 · alpha ∈ (0, 1]）
/// 公式：S[i] = alpha * X[i] + (1 - alpha) * S[i-1]
/// 等价 EMA 但 alpha 直接控制（EMA 是 alpha = 2/(N+1)）
struct EXPSMOOTHINGFunction: BuiltinFunction {
    let name = "EXPSMOOTHING"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "EXPSMOOTHING需要2个参数（X, alpha）")
        }
        let source = args[0]
        guard let aV = args[1].first, let alpha = aV else {
            throw InterpreterError(message: "EXPSMOOTHING的alpha参数无效")
        }
        guard alpha > 0, alpha <= 1 else {
            throw InterpreterError(message: "EXPSMOOTHING的alpha必须 ∈ (0, 1]")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var prev: Decimal?
        let oneMinusAlpha = 1 - alpha
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = alpha * v + oneMinusAlpha * prev!
            }
            result[i] = prev
        }
        return result
    }
}

// MARK: - 7. WEIGHTEDMEAN

/// WEIGHTEDMEAN(X, W, N) — N 内 SUM(X*W) / SUM(W)
struct WEIGHTEDMEANFunction: BuiltinFunction {
    let name = "WEIGHTEDMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "WEIGHTEDMEAN需要3个参数（X, W, N）")
        }
        let x = args[0]
        let w = args[1]
        guard let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "WEIGHTEDMEAN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "WEIGHTEDMEAN的周期必须为正整数")
        }
        guard x.count == w.count else {
            throw InterpreterError(message: "WEIGHTEDMEAN的X和W长度必须一致")
        }

        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var xwSum: Decimal = 0
            var wSum: Decimal = 0
            for j in start...i {
                guard let xv = x[j], let wv = w[j] else { continue }
                xwSum += xv * wv
                wSum += wv
            }
            guard wSum != 0 else { continue }
            result[i] = xwSum / wSum
        }
        return result
    }
}

// MARK: - 内部 helpers

/// 线性回归（简单 OLS · 用于 LINREGR 系列）
private enum MaiB32Reg {
    /// 返回 (slope, intercept) · X 系列从 start 到 end · 自变量是 i_local = j - start
    /// nil 表示数据不足或 sumXX 为 0
    static func linreg(source: [Decimal?], start: Int, end: Int) -> (slope: Decimal, intercept: Decimal)? {
        var values: [(Int, Decimal)] = []
        for j in start...end {
            if let v = source[j] {
                values.append((j - start, v))
            }
        }
        guard values.count >= 2 else { return nil }
        let nDec = Decimal(values.count)
        let xMean = values.map { Decimal($0.0) }.reduce(Decimal(0), +) / nDec
        let yMean = values.map(\.1).reduce(Decimal(0), +) / nDec
        var num: Decimal = 0
        var den: Decimal = 0
        for (xi, y) in values {
            let dx = Decimal(xi) - xMean
            let dy = y - yMean
            num += dx * dy
            den += dx * dx
        }
        guard den != 0 else { return nil }
        let slope = num / den
        let intercept = yMean - slope * xMean
        return (slope, intercept)
    }
}
