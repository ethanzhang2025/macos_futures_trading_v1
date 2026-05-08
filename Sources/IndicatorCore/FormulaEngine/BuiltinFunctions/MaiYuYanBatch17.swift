// 麦语言扩展 · 第 17 批（v15.25 batch24 · ICHIMOKU 一目均衡 + DONCHIAN 通道）
//
// 7 个 trader 进阶通道函数：
//   1. ICHITENKAN(N)         — Tenkan-sen 转折线（默认 N=9）
//   2. ICHIKIJUN(N)          — Kijun-sen 基准线（默认 N=26）
//   3. ICHISPANA(N1, N2)     — Senkou Span A 先行带 A = (Tenkan+Kijun)/2
//   4. ICHISPANB(N)          — Senkou Span B 先行带 B（默认 N=52）
//   5. DONCHIANU(N)          — Donchian 上轨 = HHV(H, N)
//   6. DONCHIANL(N)          — Donchian 下轨 = LLV(L, N)
//   7. DONCHIANM(N)          — Donchian 中线 = (Upper + Lower) / 2

import Foundation

// MARK: - 1. ICHITENKAN

/// ICHITENKAN — 一目均衡 Tenkan-sen 转折线
/// 公式：(HHV(H, N) + LLV(L, N)) / 2 · 默认 N=9
struct ICHITENKANFunction: BuiltinFunction {
    let name = "ICHITENKAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ICHITENKAN需要1个参数（周期N · 默认 9）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ICHITENKAN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ICHITENKAN的周期必须为正整数")
        }
        return MaiB17Channel.midRange(bars: bars, period: period)
    }
}

// MARK: - 2. ICHIKIJUN

/// ICHIKIJUN — 一目均衡 Kijun-sen 基准线
/// 公式：(HHV(H, N) + LLV(L, N)) / 2 · 默认 N=26
struct ICHIKIJUNFunction: BuiltinFunction {
    let name = "ICHIKIJUN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ICHIKIJUN需要1个参数（周期N · 默认 26）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ICHIKIJUN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ICHIKIJUN的周期必须为正整数")
        }
        return MaiB17Channel.midRange(bars: bars, period: period)
    }
}

// MARK: - 3. ICHISPANA

/// ICHISPANA — 一目均衡 Senkou Span A 先行带 A
/// 公式：(Tenkan(N1) + Kijun(N2)) / 2
/// 注：传统 ICHISPANA 是前移 N2 根 · 我们这里返当前根值（trader 自己 REF 移位）
struct ICHISPANAFunction: BuiltinFunction {
    let name = "ICHISPANA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "ICHISPANA需要2个参数（N1 转折期, N2 基准期）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "ICHISPANA的参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "ICHISPANA的周期必须为正整数")
        }

        let tenkan = MaiB17Channel.midRange(bars: bars, period: p1)
        let kijun = MaiB17Channel.midRange(bars: bars, period: p2)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let t = tenkan[i], let k = kijun[i] else { continue }
            result[i] = (t + k) / 2
        }
        return result
    }
}

// MARK: - 4. ICHISPANB

/// ICHISPANB — 一目均衡 Senkou Span B 先行带 B
/// 公式：(HHV(H, N) + LLV(L, N)) / 2 · 默认 N=52
struct ICHISPANBFunction: BuiltinFunction {
    let name = "ICHISPANB"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ICHISPANB需要1个参数（周期N · 默认 52）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ICHISPANB的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ICHISPANB的周期必须为正整数")
        }
        return MaiB17Channel.midRange(bars: bars, period: period)
    }
}

// MARK: - 5. DONCHIANU

/// DONCHIANU — Donchian 上轨 = HHV(HIGH, N)
struct DONCHIANUFunction: BuiltinFunction {
    let name = "DONCHIANU"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "DONCHIANU需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "DONCHIANU的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DONCHIANU的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
            }
            result[i] = hi
        }
        return result
    }
}

// MARK: - 6. DONCHIANL

/// DONCHIANL — Donchian 下轨 = LLV(LOW, N)
struct DONCHIANLFunction: BuiltinFunction {
    let name = "DONCHIANL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "DONCHIANL需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "DONCHIANL的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DONCHIANL的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var lo = bars[start].low
            for j in start...i {
                if bars[j].low < lo { lo = bars[j].low }
            }
            result[i] = lo
        }
        return result
    }
}

// MARK: - 7. DONCHIANM

/// DONCHIANM — Donchian 中线 = (Upper + Lower) / 2
struct DONCHIANMFunction: BuiltinFunction {
    let name = "DONCHIANM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "DONCHIANM需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "DONCHIANM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DONCHIANM的周期必须为正整数")
        }
        return MaiB17Channel.midRange(bars: bars, period: period)
    }
}

// MARK: - 内部 helper

/// 共用：(HHV(H, N) + LLV(L, N)) / 2 · 一目均衡 / Donchian 中线 都用
private enum MaiB17Channel {
    static func midRange(bars: [BarData], period: Int) -> [Decimal?] {
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
            result[i] = (hi + lo) / 2
        }
        return result
    }
}
