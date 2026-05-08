// 麦语言扩展 · 第 11 批（v15.25 batch18 · ~99.99% → ~99.995% 兼容度）
//
// 7 个进阶价格组合 / 自适应均线 / 包络函数：
//   1. TYP()              — Typical Price = (H+L+C)/3（函数版 · 之前 TYP 是 var）
//   2. OC()               — Open-Close mid = (O+C)/2
//   3. ENVUP(X, N, M)     — Envelope Upper = MA(X, N) * (1 + M/100)
//   4. ENVDN(X, N, M)     — Envelope Lower = MA(X, N) * (1 - M/100)
//   5. KAMA(X, N)         — Kaufman Adaptive MA（fast=2 slow=30 经典参数）
//   6. ZLEMA(X, N)        — Zero Lag EMA · 减少滞后
//   7. NEAREST(X, T)      — 距常量 T 最近的 X 值（找支撑阻力位）

import Foundation

// MARK: - 1. TYP

/// TYP — Typical Price = (H+L+C)/3（函数版）
struct TYPFunction: BuiltinFunction {
    let name = "TYP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "TYP不需要参数")
        }
        return bars.map { Optional(($0.high + $0.low + $0.close) / 3) }
    }
}

// MARK: - 2. OC

/// OC — Open-Close mid = (O+C)/2
struct OCFunction: BuiltinFunction {
    let name = "OC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "OC不需要参数")
        }
        return bars.map { Optional(($0.open + $0.close) / 2) }
    }
}

// MARK: - 3. ENVUP

/// ENVUP — Envelope Upper = MA(X, N) * (1 + M/100)
/// M 单位为百分比（如 M=2 表示 2%）
struct ENVUPFunction: BuiltinFunction {
    let name = "ENVUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "ENVUP需要3个参数（X, N, M百分比）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal,
              let mVal = args[2].first, let m = mVal else {
            throw InterpreterError(message: "ENVUP的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ENVUP的周期必须为正整数")
        }
        let factor = (1 + m / 100)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = source[j] { sum += v; cnt += 1 }
            }
            guard cnt > 0 else { continue }
            result[i] = sum / Decimal(cnt) * factor
        }
        return result
    }
}

// MARK: - 4. ENVDN

/// ENVDN — Envelope Lower = MA(X, N) * (1 - M/100)
struct ENVDNFunction: BuiltinFunction {
    let name = "ENVDN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "ENVDN需要3个参数（X, N, M百分比）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal,
              let mVal = args[2].first, let m = mVal else {
            throw InterpreterError(message: "ENVDN的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ENVDN的周期必须为正整数")
        }
        let factor = (1 - m / 100)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = source[j] { sum += v; cnt += 1 }
            }
            guard cnt > 0 else { continue }
            result[i] = sum / Decimal(cnt) * factor
        }
        return result
    }
}

// MARK: - 5. KAMA

/// KAMA — Kaufman Adaptive Moving Average
/// 经典参数：fast=2 slow=30
/// 公式：
///   ER(i) = |C[i]-C[i-N]| / SUM(|C[j]-C[j-1]|, N)
///   SC(i) = (ER * (2/(fast+1) - 2/(slow+1)) + 2/(slow+1))^2
///   KAMA(i) = KAMA(i-1) + SC * (C[i] - KAMA(i-1))
/// 用途：高效率（趋势）时反应快 / 低效率（震荡）时滤噪
struct KAMAFunction: BuiltinFunction {
    let name = "KAMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KAMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "KAMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "KAMA的周期必须为正整数")
        }

        let count = source.count
        let fastSC = Decimal(2) / Decimal(2 + 1)   // fast=2
        let slowSC = Decimal(2) / Decimal(30 + 1)  // slow=30
        let scDiff = fastSC - slowSC

        var result = [Decimal?](repeating: nil, count: count)
        var prevKAMA: Decimal?
        for i in 0..<count {
            guard let curr = source[i] else { continue }
            if i < period {
                // 前 N 根用 SMA 作为种子
                let start = 0
                var sum: Decimal = 0
                var cnt = 0
                for j in start...i {
                    if let v = source[j] { sum += v; cnt += 1 }
                }
                if cnt > 0 {
                    prevKAMA = sum / Decimal(cnt)
                    result[i] = prevKAMA
                }
                continue
            }

            // ER 计算
            guard let nBack = source[i - period] else { continue }
            let direction = abs(curr - nBack)
            var volatility: Decimal = 0
            for j in (i - period + 1)...i {
                guard let cur = source[j], let prev = source[j - 1] else { continue }
                volatility += abs(cur - prev)
            }
            var er: Decimal = 0
            if volatility > 0 {
                er = direction / volatility
            }
            let scLin = er * scDiff + slowSC
            let sc = scLin * scLin
            if let prev = prevKAMA {
                prevKAMA = prev + sc * (curr - prev)
            } else {
                prevKAMA = curr
            }
            result[i] = prevKAMA
        }
        return result
    }
}

// MARK: - 6. ZLEMA

/// ZLEMA — Zero Lag EMA
/// 公式：
///   lag = (N - 1) / 2
///   adjusted = 2 * X[i] - X[i - lag]
///   ZLEMA = EMA(adjusted, N)
/// 用途：抵消 EMA 的滞后
struct ZLEMAFunction: BuiltinFunction {
    let name = "ZLEMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "ZLEMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "ZLEMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ZLEMA的周期必须为正整数")
        }
        let lag = (period - 1) / 2

        let count = source.count
        var adjusted = [Decimal?](repeating: nil, count: count)
        for i in lag..<count {
            guard let cur = source[i], let lagged = source[i - lag] else { continue }
            adjusted[i] = 2 * cur - lagged
        }

        // EMA(adjusted, N)
        let multiplier = Decimal(2) / Decimal(period + 1)
        var result = [Decimal?](repeating: nil, count: count)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = adjusted[i] else { continue }
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

// MARK: - 7. NEAREST

/// NEAREST — 距常量 target 最近的 X 值
/// 公式：扫描全部 X 找 |X[j] - target| 最小的 X[j]
/// 用途：找历史中最接近某价位（如圆整价 3500）的成交根 · trader 找支撑阻力
struct NEARESTFunction: BuiltinFunction {
    let name = "NEAREST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "NEAREST需要2个参数（X, target）")
        }
        let source = args[0]
        guard let tVal = args[1].first, let target = tVal else {
            throw InterpreterError(message: "NEAREST的target参数无效")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var bestVal: Decimal?
        var bestDist: Decimal?
        for i in 0..<count {
            if let v = source[i] {
                let dist = abs(v - target)
                if bestDist == nil || dist < bestDist! {
                    bestDist = dist
                    bestVal = v
                }
            }
            result[i] = bestVal
        }
        return result
    }
}
