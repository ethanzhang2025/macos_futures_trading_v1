// 麦语言扩展 · 第 31 批（v15.25 batch38 · K 线细节统计 + 距离/振幅）
//
// 7 个 K 线细节函数：
//   1. GAPSIZE()           — 跳空大小 = O - REF(C, 1)（正=向上跳 · 负=向下跳）
//   2. BODYPCT()           — 实体百分比 = (C - O) / O * 100（正=阳 · 负=阴）
//   3. UPPERWICK()         — 上影线长度 = H - max(O, C)
//   4. LOWERWICK()         — 下影线长度 = min(O, C) - L
//   5. WICKRATIO()         — 上影 / 下影（防 0）
//   6. PRICEDIST(X, T)     — abs(X - T) 距离
//   7. RANGEPCT(N)         — N 内振幅百分比 = (HHV-LLV) / LLV * 100

import Foundation

// MARK: - 1. GAPSIZE

/// GAPSIZE() — 跳空大小（O - REF(C, 1)）· 正=向上跳 · 负=向下跳
struct GAPSIZEFunction: BuiltinFunction {
    let name = "GAPSIZE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "GAPSIZE不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = bars[i].open - bars[i - 1].close
        }
        return result
    }
}

// MARK: - 2. BODYPCT

/// BODYPCT() — 实体百分比 = (C - O) / O * 100
struct BODYPCTFunction: BuiltinFunction {
    let name = "BODYPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "BODYPCT不需要参数")
        }
        return bars.map { bar in
            guard bar.open != 0 else { return nil }
            return (bar.close - bar.open) / bar.open * 100
        }
    }
}

// MARK: - 3. UPPERWICK

/// UPPERWICK() — 上影线长度
struct UPPERWICKFunction: BuiltinFunction {
    let name = "UPPERWICK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "UPPERWICK不需要参数")
        }
        return bars.map { bar in
            let bodyTop = max(bar.open, bar.close)
            return bar.high - bodyTop
        }
    }
}

// MARK: - 4. LOWERWICK

/// LOWERWICK() — 下影线长度
struct LOWERWICKFunction: BuiltinFunction {
    let name = "LOWERWICK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "LOWERWICK不需要参数")
        }
        return bars.map { bar in
            let bodyBottom = min(bar.open, bar.close)
            return bodyBottom - bar.low
        }
    }
}

// MARK: - 5. WICKRATIO

/// WICKRATIO() — 上影 / 下影（防 0）· 下影=0 时返大数 999
struct WICKRATIOFunction: BuiltinFunction {
    let name = "WICKRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "WICKRATIO不需要参数")
        }
        return bars.map { bar in
            let upper = bar.high - max(bar.open, bar.close)
            let lower = min(bar.open, bar.close) - bar.low
            if lower == 0 {
                return upper > 0 ? Decimal(string: "999")! : 0
            }
            return upper / lower
        }
    }
}

// MARK: - 6. PRICEDIST

/// PRICEDIST(X, target) — abs(X - target)
struct PRICEDISTFunction: BuiltinFunction {
    let name = "PRICEDIST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "PRICEDIST需要2个参数（X, target）")
        }
        let source = args[0]
        guard let tV = args[1].first, let target = tV else {
            throw InterpreterError(message: "PRICEDIST的target参数无效")
        }
        return source.map { v in
            guard let v else { return nil }
            return abs(v - target)
        }
    }
}

// MARK: - 7. RANGEPCT

/// RANGEPCT(N) — N 内振幅百分比 = (HHV - LLV) / LLV * 100
struct RANGEPCTFunction: BuiltinFunction {
    let name = "RANGEPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RANGEPCT需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "RANGEPCT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "RANGEPCT的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            guard lo > 0 else { continue }
            result[i] = (hi - lo) / lo * 100
        }
        return result
    }
}
