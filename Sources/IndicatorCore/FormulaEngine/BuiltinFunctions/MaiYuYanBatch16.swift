// 麦语言扩展 · 第 16 批（v15.25 batch23 · 量价进阶 + 中国市场 + 统计配对）
//
// 7 个 trader 进阶量价 + 中国市场 + 配对统计：
//   1. CMF(N)              — Chaikin Money Flow（量价货币流）
//   2. ADL()               — Accumulation Distribution Line（量价累计）
//   3. BR(N)               — 中国市场 BR 中庸（高于昨日收盘的振幅强度）
//   4. AR(N)               — 中国市场 AR 中庸（开盘动力指标）
//   5. KVO(N1, N2)         — Klinger Volume Oscillator（量能简化版）
//   6. RVI(N)              — Relative Vigor Index（实体强度比）
//   7. BETA(X, Y, N)       — Beta 系数 = COV(X,Y,N) / VAR(Y,N)

import Foundation

// MARK: - 1. CMF

/// CMF — Chaikin Money Flow
/// 公式：
///   MFM = ((C-L) - (H-C)) / (H-L)
///   MFV = MFM * V
///   CMF = SUM(MFV, N) / SUM(V, N)
/// 范围 [-1, 1] · 经验：> 0.25 多头 / < -0.25 空头
struct CMFFunction: BuiltinFunction {
    let name = "CMF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CMF需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CMF的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CMF的周期必须为正整数")
        }

        let count = bars.count
        // MFV per bar
        var mfv = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            let span = bars[i].high - bars[i].low
            guard span > 0 else { continue }
            let mfm = ((bars[i].close - bars[i].low) - (bars[i].high - bars[i].close)) / span
            mfv[i] = mfm * Decimal(bars[i].volume)
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var mfvSum: Decimal = 0
            var vSum: Decimal = 0
            for j in start...i {
                mfvSum += mfv[j]
                vSum += Decimal(bars[j].volume)
            }
            guard vSum > 0 else { continue }
            result[i] = mfvSum / vSum
        }
        return result
    }
}

// MARK: - 2. ADL

/// ADL — Accumulation Distribution Line
/// 公式：AD[i] = AD[i-1] + ((C-L) - (H-C)) / (H-L) * V
struct ADLFunction: BuiltinFunction {
    let name = "ADL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ADL不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }
        var cum: Decimal = 0
        for i in 0..<count {
            let span = bars[i].high - bars[i].low
            if span > 0 {
                let mfm = ((bars[i].close - bars[i].low) - (bars[i].high - bars[i].close)) / span
                cum += mfm * Decimal(bars[i].volume)
            }
            result[i] = cum
        }
        return result
    }
}

// MARK: - 3. BR

/// BR — 中国市场中庸指标（高于昨日收盘的振幅强度）
/// 公式：BR(N) = SUM(MAX(0, H-REF(C,1)), N) / SUM(MAX(0, REF(C,1)-L), N) * 100
struct BRFunction: BuiltinFunction {
    let name = "BR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "BR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "BR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var up: Decimal = 0
            var down: Decimal = 0
            for j in start...i {
                let prevC = bars[j - 1].close
                let upTerm = bars[j].high - prevC
                let downTerm = prevC - bars[j].low
                if upTerm > 0 { up += upTerm }
                if downTerm > 0 { down += downTerm }
            }
            if down > 0 {
                result[i] = up / down * 100
            } else {
                result[i] = up > 0 ? Decimal(string: "999")! : 0
            }
        }
        return result
    }
}

// MARK: - 4. AR

/// AR — 中国市场开盘动力指标
/// 公式：AR(N) = SUM(H-O, N) / SUM(O-L, N) * 100
struct ARFunction: BuiltinFunction {
    let name = "AR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var up: Decimal = 0
            var down: Decimal = 0
            for j in start...i {
                up += bars[j].high - bars[j].open
                down += bars[j].open - bars[j].low
            }
            if down > 0 {
                result[i] = up / down * 100
            } else {
                result[i] = up > 0 ? Decimal(string: "999")! : 0
            }
        }
        return result
    }
}

// MARK: - 5. KVO

/// KVO — Klinger Volume Oscillator（简化版）
/// 公式：
///   VF = ((C - L) - (H - C)) / (H - L) * V
///   KVO = EMA(VF, N1) - EMA(VF, N2)
/// 用途：量价摆动 · 与 CHO 类似但用于较短周期
struct KVOFunction: BuiltinFunction {
    let name = "KVO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KVO需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "KVO的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "KVO的周期必须为正整数")
        }

        let count = bars.count
        var vf = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let span = bars[i].high - bars[i].low
            guard span > 0 else { continue }
            let factor = ((bars[i].close - bars[i].low) - (bars[i].high - bars[i].close)) / span
            vf[i] = factor * Decimal(bars[i].volume)
        }
        let ema1 = MaiB16EMA.ema(vf, period: p1)
        let ema2 = MaiB16EMA.ema(vf, period: p2)

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let e1 = ema1[i], let e2 = ema2[i] else { continue }
            result[i] = e1 - e2
        }
        return result
    }
}

// MARK: - 6. RVI

/// RVI — Relative Vigor Index
/// 公式：
///   numerator   = (C-O) + 2*(REF(C-O,1)) + 2*(REF(C-O,2)) + (REF(C-O,3))  / 6
///   denominator = (H-L) + 2*(REF(H-L,1)) + 2*(REF(H-L,2)) + (REF(H-L,3))  / 6
///   RVI = SUM(numerator, N) / SUM(denominator, N)
/// 用途：实体强度 / 振幅比 · 上穿信号线买入
struct RVIFunction: BuiltinFunction {
    let name = "RVI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RVI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "RVI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "RVI的周期必须为正整数")
        }

        let count = bars.count
        // co = C - O · hl = H - L
        let co: [Decimal] = bars.map { $0.close - $0.open }
        let hl: [Decimal] = bars.map { $0.high - $0.low }

        // 4-period weighted average (1, 2, 2, 1) / 6
        var num = [Decimal?](repeating: nil, count: count)
        var den = [Decimal?](repeating: nil, count: count)
        for i in 3..<count {
            num[i] = (co[i] + 2 * co[i - 1] + 2 * co[i - 2] + co[i - 3]) / 6
            den[i] = (hl[i] + 2 * hl[i - 1] + 2 * hl[i - 2] + hl[i - 3]) / 6
        }

        // SUM(num, N) / SUM(den, N)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(3, i - period + 1)
            guard start <= i else { continue }
            var nSum: Decimal = 0
            var dSum: Decimal = 0
            for j in start...i {
                if let nv = num[j] { nSum += nv }
                if let dv = den[j] { dSum += dv }
            }
            guard dSum != 0 else { continue }
            result[i] = nSum / dSum
        }
        return result
    }
}

// MARK: - 7. BETA

/// BETA — Beta 系数 = COV(X, Y, N) / VAR(Y, N)
/// 用途：套期保值 · 资产对市场敏感度
struct BETAFunction: BuiltinFunction {
    let name = "BETA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "BETA需要3个参数（X, Y, N）")
        }
        let x = args[0]
        let y = args[1]
        guard let nVal = args[2].first, let n = nVal else {
            throw InterpreterError(message: "BETA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BETA的周期必须为正整数")
        }
        guard x.count == y.count else {
            throw InterpreterError(message: "BETA的X和Y长度必须一致")
        }

        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var xs: [Decimal] = []
            var ys: [Decimal] = []
            for j in start...i {
                guard let xv = x[j], let yv = y[j] else { continue }
                xs.append(xv)
                ys.append(yv)
            }
            guard xs.count >= 2 else { continue }
            let nDec = Decimal(xs.count)
            let meanX = xs.reduce(Decimal(0), +) / nDec
            let meanY = ys.reduce(Decimal(0), +) / nDec
            var cov: Decimal = 0
            var varY: Decimal = 0
            for k in 0..<xs.count {
                let dx = xs[k] - meanX
                let dy = ys[k] - meanY
                cov += dx * dy
                varY += dy * dy
            }
            cov /= nDec
            varY /= nDec
            guard varY > 0 else { continue }
            result[i] = cov / varY
        }
        return result
    }
}

// MARK: - 内部 EMA helper

private enum MaiB16EMA {
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
