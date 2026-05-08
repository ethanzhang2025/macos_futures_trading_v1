// 麦语言扩展 · 第 7 批（v15.25 batch14 · ~99.9% → ~99.95% 兼容度）
//
// 7 个量价 / 反转 / 多空综合函数：
//   1. VWAP(N)       — Volume Weighted Average Price（量加权均价 · trader 进场参考）
//   2. EMV(N)        — Ease of Movement（量价摆动 · 量小价动 = 趋势强）
//   3. MASS(N1, N2)  — Mass Index（趋势反转 · HL 比值累加）
//   4. CHO(N1, N2)   — Chaikin Oscillator（量价摆动）
//   5. VHF(N)        — Vertical Horizontal Filter（趋势 vs 震荡）
//   6. BBI()         — Bull Bear Index 多空指数（中国市场常用）
//   7. PVT()         — Price Volume Trend（OBV 改进版）

import Foundation

// MARK: - 1. VWAP

/// VWAP — Volume Weighted Average Price
/// 公式：VWAP(N) = SUM(TYP * V, N) / SUM(V, N) · TYP = (H+L+C)/3
/// 用途：trader 大单进场基准 · 期货也用
struct VWAPFunction: BuiltinFunction {
    let name = "VWAP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "VWAP需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "VWAP的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "VWAP的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var pvSum: Decimal = 0
            var vSum: Decimal = 0
            for j in start...i {
                let typ = (bars[j].high + bars[j].low + bars[j].close) / 3
                let v = Decimal(bars[j].volume)
                pvSum += typ * v
                vSum += v
            }
            guard vSum > 0 else { continue }
            result[i] = pvSum / vSum
        }
        return result
    }
}

// MARK: - 2. EMV

/// EMV — Ease of Movement
/// 公式：
///   MID = (H+L)/2 - REF((H+L)/2, 1)
///   BR = V / (H - L)
///   EMV[i] = MID / BR
///   EMV(N) = MA(EMV, N)
/// 用途：量小价动 → EMV 大 → 趋势强 / 量大价动 → EMV 小 → 趋势弱
struct EMVFunction: BuiltinFunction {
    let name = "EMV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "EMV需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "EMV的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "EMV的周期必须为正整数")
        }

        let count = bars.count
        // EMV 原始
        var emv = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let mid = (bars[i].high + bars[i].low) / 2 - (bars[i - 1].high + bars[i - 1].low) / 2
            let span = bars[i].high - bars[i].low
            let v = Decimal(bars[i].volume)
            guard v > 0, span > 0 else { continue }
            let br = v / span
            emv[i] = mid / br
        }

        // MA(EMV, N)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = emv[j] {
                    sum += v
                    cnt += 1
                }
            }
            if cnt > 0 {
                result[i] = sum / Decimal(cnt)
            }
        }
        return result
    }
}

// MARK: - 3. MASS

/// MASS — Mass Index 趋势反转
/// 公式：
///   HL = HIGH - LOW
///   E1 = EMA(HL, N1)
///   E2 = EMA(E1, N1)
///   MASS = SUM(E1 / E2, N2)
/// 经验：MASS > 27 警示反转
struct MASSFunction: BuiltinFunction {
    let name = "MASS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MASS需要2个参数（N1, N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "MASS的周期参数无效")
        }
        let period1 = Int(truncating: n1 as NSDecimalNumber)
        let period2 = Int(truncating: n2 as NSDecimalNumber)
        guard period1 > 0, period2 > 0 else {
            throw InterpreterError(message: "MASS的周期必须为正整数")
        }

        let count = bars.count
        // HL
        let hl: [Decimal?] = bars.map { Optional($0.high - $0.low) }
        let e1 = MaiB7EMA.ema(hl, period: period1)
        let e2 = MaiB7EMA.ema(e1, period: period1)

        // ratio = E1 / E2
        var ratio = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let v1 = e1[i], let v2 = e2[i], v2 != 0 else { continue }
            ratio[i] = v1 / v2
        }

        // SUM(ratio, N2)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period2 + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = ratio[j] {
                    sum += v
                    cnt += 1
                }
            }
            if cnt > 0 {
                result[i] = sum
            }
        }
        return result
    }
}

// MARK: - 4. CHO

/// CHO — Chaikin Oscillator
/// 公式：
///   AD[i] = ((C - L) - (H - C)) / (H - L) * V
///   CHO = EMA(累计AD, N1) - EMA(累计AD, N2)
/// 用途：量价摆动 · 上穿 0 多头 / 下穿 0 空头
struct CHOFunction: BuiltinFunction {
    let name = "CHO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CHO需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "CHO的周期参数无效")
        }
        let period1 = Int(truncating: n1 as NSDecimalNumber)
        let period2 = Int(truncating: n2 as NSDecimalNumber)
        guard period1 > 0, period2 > 0 else {
            throw InterpreterError(message: "CHO的周期必须为正整数")
        }

        let count = bars.count
        // 累积 AD
        var ad = [Decimal?](repeating: nil, count: count)
        var cumAD: Decimal = 0
        for i in 0..<count {
            let span = bars[i].high - bars[i].low
            guard span > 0 else {
                ad[i] = cumAD
                continue
            }
            let mfm = ((bars[i].close - bars[i].low) - (bars[i].high - bars[i].close)) / span
            cumAD += mfm * Decimal(bars[i].volume)
            ad[i] = cumAD
        }

        let ema1 = MaiB7EMA.ema(ad, period: period1)
        let ema2 = MaiB7EMA.ema(ad, period: period2)

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let e1 = ema1[i], let e2 = ema2[i] else { continue }
            result[i] = e1 - e2
        }
        return result
    }
}

// MARK: - 5. VHF

/// VHF — Vertical Horizontal Filter
/// 公式：
///   HCP = HHV(CLOSE, N)
///   LCP = LLV(CLOSE, N)
///   VHF = (HCP - LCP) / SUM(|CLOSE - REF(CLOSE,1)|, N)
/// 经验：VHF 升高 → 趋势强 / VHF 低 → 震荡
struct VHFFunction: BuiltinFunction {
    let name = "VHF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "VHF需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "VHF的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "VHF的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        // i=0 没有 prev close 可用 · 跳过
        for i in 1..<count {
            let start = max(0, i - period + 1)
            var hcp: Decimal = bars[start].close
            var lcp: Decimal = bars[start].close
            for j in start...i {
                if bars[j].close > hcp { hcp = bars[j].close }
                if bars[j].close < lcp { lcp = bars[j].close }
            }
            // SUM(|C - REF(C,1)|, N) · 从 max(start,1) 起算（避开 j-1 越界）
            let trStart = max(start, 1)
            guard trStart <= i else { continue }
            var trSum: Decimal = 0
            for j in trStart...i {
                trSum += abs(bars[j].close - bars[j - 1].close)
            }
            guard trSum > 0 else { continue }
            result[i] = (hcp - lcp) / trSum
        }
        return result
    }
}

// MARK: - 6. BBI

/// BBI — Bull Bear Index 多空指数
/// 公式：BBI = (MA(CLOSE,3) + MA(CLOSE,6) + MA(CLOSE,12) + MA(CLOSE,24)) / 4
/// 用途：综合 4 条均线 · trader 多空判定
struct BBIFunction: BuiltinFunction {
    let name = "BBI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "BBI不需要参数（固定 3/6/12/24）")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        let periods = [3, 6, 12, 24]
        for i in 0..<count {
            var maSum: Decimal = 0
            for p in periods {
                let start = max(0, i - p + 1)
                var sum: Decimal = 0
                for j in start...i { sum += bars[j].close }
                maSum += sum / Decimal(i - start + 1)
            }
            result[i] = maSum / 4
        }
        return result
    }
}

// MARK: - 7. PVT

/// PVT — Price Volume Trend (OBV 改进版)
/// 公式：
///   PVT[0] = 0
///   PVT[i] = PVT[i-1] + (C[i]-C[i-1])/C[i-1] * V[i]
/// 比 OBV 更精细 · 不止考虑方向 · 还考虑变化率
struct PVTFunction: BuiltinFunction {
    let name = "PVT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "PVT不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }
        result[0] = 0
        var cum: Decimal = 0
        for i in 1..<count {
            let prev = bars[i - 1].close
            guard prev != 0 else {
                result[i] = cum
                continue
            }
            let chg = (bars[i].close - prev) / prev
            cum += chg * Decimal(bars[i].volume)
            result[i] = cum
        }
        return result
    }
}

// MARK: - 内部 EMA helper

private enum MaiB7EMA {
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
