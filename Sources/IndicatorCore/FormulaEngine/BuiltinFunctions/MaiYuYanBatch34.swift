// 麦语言扩展 · 第 34 批（v15.25 batch41 · Heiken-Ashi K 线 + SAR 方向 + 价格行为）
//
// 7 个进阶 K 线变换 / 综合：
//   1. HAOPEN()       — Heiken-Ashi 开盘 = (HAOpen[i-1] + HAClose[i-1])/2
//   2. HAHIGH()       — Heiken-Ashi 最高 = max(H, HAOpen, HAClose)
//   3. HALOW()        — Heiken-Ashi 最低 = min(L, HAOpen, HAClose)
//   4. HACLOSE()      — Heiken-Ashi 收盘 = (O+H+L+C)/4
//   5. HADIR()        — Heiken-Ashi 方向（1=阳 -1=阴 0=十字）
//   6. SARDIR()       — PSAR 方向（close 在 SAR 上 = 1 · 下 = -1）
//   7. PRICEACTION(N) — 价格行为综合评分（趋势 + 动量 + 波动）

import Foundation

// MARK: - 1-4. Heiken-Ashi 系列

/// Heiken-Ashi 计算辅助（共享给 HAOPEN/HIGH/LOW/CLOSE/DIR）
private struct HAOHLC {
    var open: Decimal
    var high: Decimal
    var low: Decimal
    var close: Decimal
}

private enum HAComputer {
    static func compute(bars: [BarData]) -> [HAOHLC?] {
        let count = bars.count
        var result = [HAOHLC?](repeating: nil, count: count)
        guard count > 0 else { return result }

        // 第一根：HAOpen=O · HAClose=AVGPRICE
        let firstClose = (bars[0].open + bars[0].high + bars[0].low + bars[0].close) / 4
        var prevHAOpen = bars[0].open
        var prevHAClose = firstClose
        result[0] = HAOHLC(
            open: bars[0].open,
            high: bars[0].high,
            low: bars[0].low,
            close: firstClose
        )

        for i in 1..<count {
            let haClose = (bars[i].open + bars[i].high + bars[i].low + bars[i].close) / 4
            let haOpen = (prevHAOpen + prevHAClose) / 2
            let haHigh = max(bars[i].high, max(haOpen, haClose))
            let haLow = min(bars[i].low, min(haOpen, haClose))
            result[i] = HAOHLC(open: haOpen, high: haHigh, low: haLow, close: haClose)
            prevHAOpen = haOpen
            prevHAClose = haClose
        }
        return result
    }
}

/// HAOPEN()
struct HAOPENFunction: BuiltinFunction {
    let name = "HAOPEN"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HAOPEN不需要参数") }
        return HAComputer.compute(bars: bars).map { $0.map(\.open) }
    }
}

/// HAHIGH()
struct HAHIGHFunction: BuiltinFunction {
    let name = "HAHIGH"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HAHIGH不需要参数") }
        return HAComputer.compute(bars: bars).map { $0.map(\.high) }
    }
}

/// HALOW()
struct HALOWFunction: BuiltinFunction {
    let name = "HALOW"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HALOW不需要参数") }
        return HAComputer.compute(bars: bars).map { $0.map(\.low) }
    }
}

/// HACLOSE()
struct HACLOSEFunction: BuiltinFunction {
    let name = "HACLOSE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HACLOSE不需要参数") }
        return HAComputer.compute(bars: bars).map { $0.map(\.close) }
    }
}

// MARK: - 5. HADIR

/// HADIR() — Heiken-Ashi 方向（1=阳 -1=阴 0=十字）
struct HADIRFunction: BuiltinFunction {
    let name = "HADIR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HADIR不需要参数") }
        return HAComputer.compute(bars: bars).map { ha in
            guard let ha else { return nil }
            if ha.close > ha.open { return Decimal(1) }
            if ha.close < ha.open { return Decimal(-1) }
            return Decimal(0)
        }
    }
}

// MARK: - 6. SARDIR

/// SARDIR() — PSAR 方向（close 在 SAR 上 = 1 · 下 = -1）
/// 简化版（不重算 SAR · 直接对比 close 与 PSAR）
struct SARDIRFunction: BuiltinFunction {
    let name = "SARDIR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "SARDIR不需要参数") }
        let count = bars.count
        guard count >= 2 else {
            return [Decimal?](repeating: nil, count: count)
        }
        let afStart = Decimal(string: "0.02")!
        let afStep = Decimal(string: "0.02")!
        let afMax = Decimal(string: "0.20")!

        var sarSeries = [Decimal?](repeating: nil, count: count)
        var isLong = bars[1].close >= bars[0].close
        var sar: Decimal = isLong ? bars[0].low : bars[0].high
        var ep: Decimal = isLong ? bars[0].high : bars[0].low
        var af: Decimal = afStart
        sarSeries[0] = sar

        for i in 1..<count {
            sar = sar + af * (ep - sar)
            if isLong {
                let prevLow = bars[i - 1].low
                if sar > prevLow { sar = prevLow }
                if i >= 2 {
                    let prev2Low = bars[i - 2].low
                    if sar > prev2Low { sar = prev2Low }
                }
            } else {
                let prevHigh = bars[i - 1].high
                if sar < prevHigh { sar = prevHigh }
                if i >= 2 {
                    let prev2High = bars[i - 2].high
                    if sar < prev2High { sar = prev2High }
                }
            }
            if isLong && bars[i].low < sar {
                isLong = false
                sar = ep
                ep = bars[i].low
                af = afStart
            } else if !isLong && bars[i].high > sar {
                isLong = true
                sar = ep
                ep = bars[i].high
                af = afStart
            } else {
                if isLong {
                    if bars[i].high > ep { ep = bars[i].high; af = min(af + afStep, afMax) }
                } else {
                    if bars[i].low < ep { ep = bars[i].low; af = min(af + afStep, afMax) }
                }
            }
            sarSeries[i] = sar
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let s = sarSeries[i] else { continue }
            result[i] = bars[i].close > s ? 1 : -1
        }
        return result
    }
}

// MARK: - 7. PRICEACTION

/// PRICEACTION(N) — 综合价格行为评分
/// 公式：
///   1. 趋势分：close > MA(C, N) ? +1 : -1
///   2. 动量分：close > REF(close, N/2) ? +1 : -1
///   3. 多头根多分：GREENRATIO(N) > 0.5 ? +1 : -1
/// 总分 ∈ [-3, 3]
struct PRICEACTIONFunction: BuiltinFunction {
    let name = "PRICEACTION"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PRICEACTION需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PRICEACTION的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else {
            throw InterpreterError(message: "PRICEACTION的周期必须 > 1")
        }
        let halfPeriod = max(1, period / 2)

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in halfPeriod..<count {
            let s = max(0, i - period + 1)
            // MA
            var maSum: Decimal = 0
            for j in s...i { maSum += bars[j].close }
            let ma = maSum / Decimal(i - s + 1)
            // GREENRATIO
            var greens = 0
            for j in s...i {
                if bars[j].close > bars[j].open { greens += 1 }
            }
            let greenRate = Decimal(greens) / Decimal(i - s + 1)

            var score: Decimal = 0
            score += bars[i].close > ma ? 1 : -1
            score += bars[i].close > bars[i - halfPeriod].close ? 1 : -1
            score += greenRate > Decimal(string: "0.5")! ? 1 : -1
            result[i] = score
        }
        return result
    }
}
