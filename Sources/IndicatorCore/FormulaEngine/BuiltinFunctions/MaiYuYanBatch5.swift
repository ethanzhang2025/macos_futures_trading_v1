// 麦语言扩展 · 第 5 批（v15.25 batch12 · ~99.5% → ~99.8% 兼容度）
//
// 7 个 trader 主流核心指标（之前批次漏的）：
//   1. CCI(N)         — Commodity Channel Index · 顺势指标（期货标配 N=14）
//   2. WR(N)          — Williams %R · 超买超卖（与 KDJ 互补）
//   3. ROC(N)         — Rate of Change · 变化率
//   4. MOM(N)         — Momentum · 动量（C - REF(C, N)）
//   5. OBV            — On Balance Volume · 量能累计（期货量价分析核心）
//   6. MFI(N)         — Money Flow Index · 量价 RSI（典型 N=14）
//   7. TEMA(N)        — Triple EMA · 三重指数 = 3*E1 - 3*E2 + E3（与 TRIX 同根但返均线值）
//
// 全部为标准公式 · trader 实际使用频率 ≥ DMI（第 4 批做了但实际期货 trader 用得少）

import Foundation

// MARK: - 1. CCI

/// CCI — Commodity Channel Index
/// 公式：
///   TYP = (HIGH + LOW + CLOSE) / 3
///   MA = MA(TYP, N)
///   AVEDEV = MA(|TYP - MA|, N)
///   CCI = (TYP - MA) / (0.015 * AVEDEV)
/// 经验阈值：> 100 强势 / < -100 弱势 / [-100, 100] 震荡
struct CCIFunction: BuiltinFunction {
    let name = "CCI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CCI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CCI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CCI的周期必须为正整数")
        }

        let count = bars.count
        // TYP
        var typ = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            typ[i] = (bars[i].high + bars[i].low + bars[i].close) / 3
        }

        // MA(TYP, N)
        var maTyp = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += typ[j] }
            maTyp[i] = sum / Decimal(i - start + 1)
        }

        // AVEDEV(TYP, N) = MA(|TYP - MA(TYP,N)|, N)
        var aveDev = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                guard let m = maTyp[j] else { continue }
                sum += abs(typ[j] - m)
            }
            aveDev[i] = sum / Decimal(i - start + 1)
        }

        // CCI = (TYP - MA) / (0.015 * AVEDEV)
        let factor = Decimal(string: "0.015")!
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let m = maTyp[i], let dev = aveDev[i], dev > 0 else { continue }
            result[i] = (typ[i] - m) / (factor * dev)
        }
        return result
    }
}

// MARK: - 2. WR

/// WR — Williams %R
/// 公式：WR = (HHV(HIGH, N) - CLOSE) / (HHV(HIGH, N) - LLV(LOW, N)) * 100
/// 范围 [0, 100] · 经验阈值：> 80 超卖 / < 20 超买（注意方向与 KDJ 反）
struct WRFunction: BuiltinFunction {
    let name = "WR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "WR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "WR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "WR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hhv = bars[start].high
            var llv = bars[start].low
            for j in start...i {
                if bars[j].high > hhv { hhv = bars[j].high }
                if bars[j].low < llv { llv = bars[j].low }
            }
            let span = hhv - llv
            guard span > 0 else { continue }
            result[i] = (hhv - bars[i].close) / span * 100
        }
        return result
    }
}

// MARK: - 3. ROC

/// ROC — Rate of Change
/// 公式：ROC = (CLOSE - REF(CLOSE, N)) / REF(CLOSE, N) * 100
/// 经验：与 0 轴比较 · 上穿 0 入场 / 下穿 0 离场
struct ROCFunction: BuiltinFunction {
    let name = "ROC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ROC需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ROC的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ROC的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            let prev = bars[i - period].close
            guard prev != 0 else { continue }
            result[i] = (bars[i].close - prev) / prev * 100
        }
        return result
    }
}

// MARK: - 4. MOM

/// MOM — Momentum
/// 公式：MOM = CLOSE - REF(CLOSE, N)
struct MOMFunction: BuiltinFunction {
    let name = "MOM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "MOM需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "MOM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MOM的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            result[i] = bars[i].close - bars[i - period].close
        }
        return result
    }
}

// MARK: - 5. OBV

/// OBV — On Balance Volume
/// 公式：
///   OBV[0] = 0
///   OBV[i] = OBV[i-1] + (if C[i] > C[i-1] then V[i] else if C[i] < C[i-1] then -V[i] else 0)
/// trader 量价分析核心 · 顺势加码 / 背离信号
struct OBVFunction: BuiltinFunction {
    let name = "OBV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "OBV不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }

        var cumOBV: Decimal = 0
        result[0] = 0
        for i in 1..<count {
            let v = Decimal(bars[i].volume)
            if bars[i].close > bars[i - 1].close {
                cumOBV += v
            } else if bars[i].close < bars[i - 1].close {
                cumOBV -= v
            }
            // 等价不变
            result[i] = cumOBV
        }
        return result
    }
}

// MARK: - 6. MFI

/// MFI — Money Flow Index（量价 RSI）
/// 公式：
///   TYP = (HIGH + LOW + CLOSE) / 3
///   MF = TYP * VOLUME
///   PMF[i] = sum of MF[j] for j in (i-N+1...i) where TYP[j] > TYP[j-1]
///   NMF[i] = sum of MF[j] for j in (i-N+1...i) where TYP[j] < TYP[j-1]
///   MR = PMF / NMF
///   MFI = 100 - 100 / (1 + MR)
/// 经验阈值：> 80 超买 / < 20 超卖
struct MFIFunction: BuiltinFunction {
    let name = "MFI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "MFI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "MFI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MFI的周期必须为正整数")
        }

        let count = bars.count
        // TYP + MF
        var typ = [Decimal](repeating: 0, count: count)
        var mf = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            typ[i] = (bars[i].high + bars[i].low + bars[i].close) / 3
            mf[i] = typ[i] * Decimal(bars[i].volume)
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            guard start <= i else { continue }
            var pmf: Decimal = 0
            var nmf: Decimal = 0
            for j in start...i {
                if typ[j] > typ[j - 1] {
                    pmf += mf[j]
                } else if typ[j] < typ[j - 1] {
                    nmf += mf[j]
                }
            }
            if nmf == 0 {
                result[i] = pmf > 0 ? 100 : 50
            } else {
                let mr = pmf / nmf
                result[i] = 100 - 100 / (1 + mr)
            }
        }
        return result
    }
}

// MARK: - 7. TEMA

/// TEMA — Triple Exponential Moving Average
/// 公式：
///   E1 = EMA(X, N)
///   E2 = EMA(E1, N)
///   E3 = EMA(E2, N)
///   TEMA = 3*E1 - 3*E2 + E3
/// 与 TRIX 同根但返均线值（trader 减少滞后的均线选择）
struct TEMAFunction: BuiltinFunction {
    let name = "TEMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "TEMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "TEMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TEMA的周期必须为正整数")
        }

        let e1 = TEMAEMASmoother.ema(source, period: period)
        let e2 = TEMAEMASmoother.ema(e1, period: period)
        let e3 = TEMAEMASmoother.ema(e2, period: period)

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let v1 = e1[i], let v2 = e2[i], let v3 = e3[i] else { continue }
            result[i] = 3 * v1 - 3 * v2 + v3
        }
        return result
    }
}

// MARK: - 内部 EMA helper（与 batch4 EMASmoother 隔离 · 避免命名冲突）

private enum TEMAEMASmoother {
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
