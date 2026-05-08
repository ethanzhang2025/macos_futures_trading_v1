// 麦语言扩展 · 第 44 批（v15.25 batch51 · 信号过滤 · 收尾批）
//
// 7 个函数（信号去噪 / 平滑 / 滤波）：
//   1. KALMAN(X, Q, R)            — 一维 Kalman 滤波（简化）
//   2. HP_FILTER(X, lambda)       — Hodrick-Prescott 滤波（IIR 近似）
//   3. SAVITZKYGOLAY(X)           — 因果 5 期 SG 平滑（权重 [-3,12,17,12,-3]/35）
//   4. MEDIANFILTER(X, N)         — 滑动中位数
//   5. GAUSSFILTER(X, N)          — N 期高斯权重平滑（σ=N/2）
//   6. BUTTERWORTH(X, N)          — Ehlers 二阶 Butterworth 低通
//   7. EMAFILTER(X, alpha)        — 直接 alpha 控制 EMA（更灵活）

import Foundation

// MARK: - 1. KALMAN

/// KALMAN(X, Q, R) — 一维卡尔曼
/// 状态: x_est, P
/// 公式：
///   pred: x_pred = x_est, P_pred = P + Q
///   update: K = P_pred / (P_pred + R), x_est = x_pred + K*(z - x_pred), P = (1-K)*P_pred
struct KALMANFunction: BuiltinFunction {
    let name = "KALMAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "KALMAN需要3个参数（数据, 过程噪声Q, 观测噪声R）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var xEst: Decimal?
        var p: Decimal = 1
        for i in 0..<count {
            guard let z = x[i] else { result[i] = xEst; continue }
            guard let qi = args[1][safe: i], let q = qi,
                  let ri = args[2][safe: i], let r = ri,
                  q >= 0, r > 0 else {
                if xEst == nil { xEst = z }
                result[i] = xEst
                continue
            }
            if let prev = xEst {
                let pPred = p + q
                let k = pPred / (pPred + r)
                xEst = prev + k * (z - prev)
                p = (1 - k) * pPred
            } else {
                xEst = z
                p = r
            }
            result[i] = xEst
        }
        return result
    }
}

// MARK: - 2. HP_FILTER

/// HP_FILTER(X, lambda) — Hodrick-Prescott 简化 IIR 近似
/// 用一阶递归 trend[i] = (1-α)*X[i] + α*(2*trend[i-1] - trend[i-2])
/// α = lambda / (1 + lambda)  · lambda 越大越平滑
struct HP_FILTERFunction: BuiltinFunction {
    let name = "HP_FILTER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "HP_FILTER需要2个参数（数据, 平滑系数lambda）") }
        guard let lv = args[1].first, let lambda = lv, lambda >= 0 else {
            throw InterpreterError(message: "HP_FILTER的lambda必须非负")
        }
        let alpha = lambda / (1 + lambda)
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var prev1: Decimal?
        var prev2: Decimal?
        for i in 0..<count {
            guard let v = x[i] else { result[i] = prev1; continue }
            let trend: Decimal
            if let p1 = prev1, let p2 = prev2 {
                trend = (1 - alpha) * v + alpha * (2 * p1 - p2)
            } else if let p1 = prev1 {
                trend = (1 - alpha) * v + alpha * p1
            } else {
                trend = v
            }
            prev2 = prev1
            prev1 = trend
            result[i] = trend
        }
        return result
    }
}

// MARK: - 3. SAVITZKYGOLAY

/// SAVITZKYGOLAY(X) — 因果 5 期 SG 平滑
/// 权重 [-3, 12, 17, 12, -3] / 35（5 期窗口的对称中心 = 当前根）
/// 实际取过去 5 根（索引 i-4..i），用对称权重的因果版本
struct SAVITZKYGOLAYFunction: BuiltinFunction {
    let name = "SAVITZKYGOLAY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "SAVITZKYGOLAY需要1个参数（数据）") }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        // 因果版权重：左到右 [-3, 12, 17, 12, -3]
        let weights: [Decimal] = [-3, 12, 17, 12, -3]
        let denom: Decimal = 35
        for i in 4..<count {
            var sum: Decimal = 0
            var ok = true
            for k in 0..<5 {
                guard let v = x[i - 4 + k] else { ok = false; break }
                sum += weights[k] * v
            }
            if ok { result[i] = sum / denom }
        }
        return result
    }
}

// MARK: - 4. MEDIANFILTER

/// MEDIANFILTER(X, N) — 滑动中位数
struct MEDIANFILTERFunction: BuiltinFunction {
    let name = "MEDIANFILTER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "MEDIANFILTER需要2个参数（数据, 周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "MEDIANFILTER的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "MEDIANFILTER的周期必须为正整数") }

        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var window: [Decimal] = []
            for j in s...i { if let v = x[j] { window.append(v) } }
            guard !window.isEmpty else { continue }
            window.sort()
            let mid = window.count / 2
            if window.count % 2 == 1 {
                result[i] = window[mid]
            } else {
                result[i] = (window[mid - 1] + window[mid]) / 2
            }
        }
        return result
    }
}

// MARK: - 5. GAUSSFILTER

/// GAUSSFILTER(X, N) — N 期高斯权重平滑（σ=N/2）
/// w_k = exp(-(k - center)² / (2σ²))，归一化后加权
struct GAUSSFILTERFunction: BuiltinFunction {
    let name = "GAUSSFILTER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "GAUSSFILTER需要2个参数（数据, 周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "GAUSSFILTER的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "GAUSSFILTER的周期必须为正整数") }

        let x = args[0]
        let count = x.count
        // 预计算高斯权重（因果窗 · center=最右）
        let sigma = Double(period) / 2.0
        var weights = [Decimal](repeating: 0, count: period)
        var totalW: Decimal = 0
        for k in 0..<period {
            let dist = Double(period - 1 - k)
            let w = exp(-dist * dist / (2.0 * sigma * sigma))
            let dw = Decimal(w)
            weights[k] = dw
            totalW += dw
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i + 1 >= period else { continue }
            var sum: Decimal = 0
            var ok = true
            for k in 0..<period {
                guard let v = x[i - period + 1 + k] else { ok = false; break }
                sum += weights[k] * v
            }
            if ok { result[i] = sum / totalW }
        }
        return result
    }
}

// MARK: - 6. BUTTERWORTH

/// BUTTERWORTH(X, N) — Ehlers 二阶 Butterworth 低通
/// 公式（Ehlers）：
///   a = exp(-1.414*π/N)
///   b = 2 * a * cos(1.414*π/N)
///   c2 = b
///   c3 = -a*a
///   c1 = (1 - b + a*a) / 4
///   y[i] = c1*(X[i] + 2*X[i-1] + X[i-2]) + c2*y[i-1] + c3*y[i-2]
struct BUTTERWORTHFunction: BuiltinFunction {
    let name = "BUTTERWORTH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "BUTTERWORTH需要2个参数（数据, cutoff周期N）") }
        guard let nv = args[1].first, let n = nv else {
            throw InterpreterError(message: "BUTTERWORTH的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else { throw InterpreterError(message: "BUTTERWORTH的周期必须 > 1") }

        let dN = Double(period)
        let a = exp(-1.414 * .pi / dN)
        let b = 2.0 * a * cos(1.414 * .pi / dN)
        let c2 = b
        let c3 = -a * a
        let c1 = (1.0 - b + a * a) / 4.0

        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var y = [Double?](repeating: nil, count: count)
        for i in 0..<count {
            guard let xi = x[i] else { y[i] = nil; continue }
            let xd = NSDecimalNumber(decimal: xi).doubleValue
            if i >= 2,
               let xm1 = x[i - 1].map({ NSDecimalNumber(decimal: $0).doubleValue }),
               let xm2 = x[i - 2].map({ NSDecimalNumber(decimal: $0).doubleValue }),
               let ym1 = y[i - 1], let ym2 = y[i - 2] {
                let yi = c1 * (xd + 2.0 * xm1 + xm2) + c2 * ym1 + c3 * ym2
                y[i] = yi
                result[i] = Decimal(yi)
            } else {
                y[i] = xd
                result[i] = xi
            }
        }
        return result
    }
}

// MARK: - 7. EMAFILTER

/// EMAFILTER(X, alpha) — 直接 alpha 控制 EMA
/// y[i] = alpha * X[i] + (1 - alpha) * y[i-1]，alpha ∈ [0, 1]
struct EMAFILTERFunction: BuiltinFunction {
    let name = "EMAFILTER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "EMAFILTER需要2个参数（数据, alpha [0,1]）") }
        guard let av = args[1].first, let alpha = av, alpha >= 0, alpha <= 1 else {
            throw InterpreterError(message: "EMAFILTER的alpha必须在[0,1]")
        }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = x[i] else { result[i] = prev; continue }
            if let p = prev { prev = alpha * v + (1 - alpha) * p }
            else { prev = v }
            result[i] = prev
        }
        return result
    }
}

// MARK: - safe subscript helper（与其他批同名局部 helper · 命名前缀防冲突）

private extension Array {
    subscript(safe i: Int) -> Element? {
        return indices.contains(i) ? self[i] : nil
    }
}
