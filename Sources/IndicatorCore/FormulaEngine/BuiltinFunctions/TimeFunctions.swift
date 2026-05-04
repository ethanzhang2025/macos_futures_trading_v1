// WP-62 · 麦语言时间函数真实化（v15.18）
//
// 设计取舍：
// - bars[i].timestamp 有值时 · 按麦语言/通达信 spec 返回真时间数值
// - timestamp == nil 时回退占位（bar 序号）· 兼容老调用方（不传时间也能跑）
// - 通达信 DATE 格式 = (年-1900)*10000 + 月*100 + 日 → 例如 2026-05-03 = 126_05_03 = 1_260_503
// - TIME 格式 = HH*10000 + MM*100 + SS（HHMMSS）· spec 习惯 6 位整数
// - HOUR / MINUTE 直接返回 24 小时小时 / 分钟（0-23 / 0-59）

import Foundation

/// UTC Calendar 单例（公式引擎不依赖本地时区 · 期货市场通常按交易所 UTC+8 但函数侧统一 UTC 由调用方对齐）
private let _utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .current
    return c
}()

/// DATE — 日期 · 通达信格式 (年-1900)*10000 + 月*100 + 日
struct DATEFunction: BuiltinFunction {
    let name = "DATE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { (idx, bar) in
            guard let ts = bar.timestamp else { return Decimal(idx) as Decimal? }
            let comps = _utcCalendar.dateComponents([.year, .month, .day], from: ts)
            let y = (comps.year ?? 1900) - 1900
            let m = comps.month ?? 0
            let d = comps.day ?? 0
            return Decimal(y * 10_000 + m * 100 + d) as Decimal?
        }
    }
}

/// TIME — 时间 · HHMMSS 格式（HH*10000 + MM*100 + SS）
struct TIMEFunction: BuiltinFunction {
    let name = "TIME"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { (idx, bar) in
            guard let ts = bar.timestamp else { return Decimal(idx) as Decimal? }
            let comps = _utcCalendar.dateComponents([.hour, .minute, .second], from: ts)
            let h = comps.hour ?? 0
            let m = comps.minute ?? 0
            let s = comps.second ?? 0
            return Decimal(h * 10_000 + m * 100 + s) as Decimal?
        }
    }
}

/// HOUR — 小时 · 0-23
struct HOURFunction: BuiltinFunction {
    let name = "HOUR"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { (idx, bar) in
            guard let ts = bar.timestamp else { return Decimal(idx) as Decimal? }
            return Decimal(_utcCalendar.component(.hour, from: ts)) as Decimal?
        }
    }
}

/// MINUTE — 分钟 · 0-59
struct MINUTEFunction: BuiltinFunction {
    let name = "MINUTE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { (idx, bar) in
            guard let ts = bar.timestamp else { return Decimal(idx) as Decimal? }
            return Decimal(_utcCalendar.component(.minute, from: ts)) as Decimal?
        }
    }
}

/// ISLASTBAR — 是否最后一根K线
struct ISLASTBARFunction: BuiltinFunction {
    let name = "ISLASTBAR"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        let count = bars.count
        var result = [Decimal?](repeating: Decimal(0), count: count)
        if count > 0 { result[count - 1] = 1 }
        return result
    }
}

/// BARPOS — 当前K线位置（从1开始）
struct BARPOSFunction: BuiltinFunction {
    let name = "BARPOS"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { Decimal($0.offset + 1) as Decimal? }
    }
}
