// 麦语言扩展 · 第 8 批（v15.25 batch15 · ~99.95% → ~99.97% 兼容度）
//
// 7 个 trader 进阶 / 价格组合函数：
//   1. CMO(N)         — Chande Momentum Oscillator · [-100,100] · 与 RSI 类似但更敏感
//   2. AROONOSC(N)    — Aroon Oscillator · Up - Down · 趋势识别
//   3. VWMA(X, N)     — Volume Weighted MA · 量加权均线
//   4. NVI()          — Negative Volume Index · 聪明钱跟踪
//   5. AVGPRICE()     — 平均价 (O+H+L+C)/4
//   6. MEDPRICE()     — 中价 (H+L)/2
//   7. WC()           — Weighted Close (H+L+C+C)/4

import Foundation

// MARK: - 1. CMO

/// CMO — Chande Momentum Oscillator
/// 公式：
///   diff[i] = CLOSE[i] - CLOSE[i-1]
///   PMS = SUM(diff > 0 ? diff : 0, N)
///   NMS = SUM(diff < 0 ? -diff : 0, N)
///   CMO = (PMS - NMS) / (PMS + NMS) * 100
/// 范围 [-100, 100] · 经验：> 50 强势 / < -50 弱势
struct CMOFunction: BuiltinFunction {
    let name = "CMO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CMO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CMO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CMO的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var pms: Decimal = 0
            var nms: Decimal = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { pms += diff }
                else if diff < 0 { nms += abs(diff) }
            }
            let total = pms + nms
            guard total > 0 else { continue }
            result[i] = (pms - nms) / total * 100
        }
        return result
    }
}

// MARK: - 2. AROONOSC

/// AROONOSC — Aroon Oscillator
/// 公式：
///   AroonUp = (N - 距 N 周期最高的 bar 数) / N * 100
///   AroonDown = (N - 距 N 周期最低的 bar 数) / N * 100
///   AROONOSC = AroonUp - AroonDown
/// 范围 [-100, 100] · 经验：> 50 趋势上 / < -50 趋势下 / 0 附近震荡
struct AROONOSCFunction: BuiltinFunction {
    let name = "AROONOSC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AROONOSC需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AROONOSC的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AROONOSC的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var maxVal: Decimal = bars[start].high
            var minVal: Decimal = bars[start].low
            var maxIdx = start
            var minIdx = start
            for j in start...i {
                if bars[j].high > maxVal { maxVal = bars[j].high; maxIdx = j }
                if bars[j].low < minVal { minVal = bars[j].low; minIdx = j }
            }
            let len = i - start + 1
            let up = Decimal(len - 1 - (i - maxIdx)) / Decimal(len - 1 == 0 ? 1 : len - 1) * 100
            let down = Decimal(len - 1 - (i - minIdx)) / Decimal(len - 1 == 0 ? 1 : len - 1) * 100
            result[i] = up - down
        }
        return result
    }
}

// MARK: - 3. VWMA

/// VWMA — Volume Weighted Moving Average
/// 公式：VWMA(X, N) = SUM(X * V, N) / SUM(V, N)
/// 用途：量加权均线 · 大单方向更受重视
struct VWMAFunction: BuiltinFunction {
    let name = "VWMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "VWMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "VWMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "VWMA的周期必须为正整数")
        }
        guard source.count == bars.count else {
            throw InterpreterError(message: "VWMA的X长度必须与bars一致")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var pvSum: Decimal = 0
            var vSum: Decimal = 0
            for j in start...i {
                guard let x = source[j] else { continue }
                let v = Decimal(bars[j].volume)
                pvSum += x * v
                vSum += v
            }
            guard vSum > 0 else { continue }
            result[i] = pvSum / vSum
        }
        return result
    }
}

// MARK: - 4. NVI

/// NVI — Negative Volume Index 聪明钱指数
/// 公式：
///   NVI[0] = 1000
///   if V[i] < V[i-1]: NVI[i] = NVI[i-1] * (1 + (C[i]-C[i-1])/C[i-1])
///   else: NVI[i] = NVI[i-1]
/// 用途：缩量时记录价格变动 · 反映"聪明钱"行为
struct NVIFunction: BuiltinFunction {
    let name = "NVI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "NVI不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }
        var nvi: Decimal = 1000
        result[0] = nvi
        for i in 1..<count {
            if bars[i].volume < bars[i - 1].volume {
                let prevC = bars[i - 1].close
                if prevC != 0 {
                    let chg = (bars[i].close - prevC) / prevC
                    nvi = nvi * (1 + chg)
                }
            }
            result[i] = nvi
        }
        return result
    }
}

// MARK: - 5. AVGPRICE

/// AVGPRICE — 平均价 = (O + H + L + C) / 4
struct AVGPRICEFunction: BuiltinFunction {
    let name = "AVGPRICE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "AVGPRICE不需要参数")
        }
        return bars.map { Optional(($0.open + $0.high + $0.low + $0.close) / 4) }
    }
}

// MARK: - 6. MEDPRICE

/// MEDPRICE — 中价 = (H + L) / 2
struct MEDPRICEFunction: BuiltinFunction {
    let name = "MEDPRICE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "MEDPRICE不需要参数")
        }
        return bars.map { Optional(($0.high + $0.low) / 2) }
    }
}

// MARK: - 7. WC

/// WC — Weighted Close = (H + L + C + C) / 4 = (H + L + 2*C) / 4
/// 加权收盘价（C 权重 2 · 比 TYP 更重视收盘）
struct WCFunction: BuiltinFunction {
    let name = "WC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "WC不需要参数")
        }
        return bars.map { Optional(($0.high + $0.low + 2 * $0.close) / 4) }
    }
}
