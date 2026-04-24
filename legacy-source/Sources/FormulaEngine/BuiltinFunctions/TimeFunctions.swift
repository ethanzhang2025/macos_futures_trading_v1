import Foundation

/// DATE — 日期（YYMMDD格式数值）
/// 通达信DATE返回的是从1900年开始的YYMMDD格式
/// 这里简化为返回bar索引对应的日期（需要外部BarData扩展）
/// 当前实现：返回bar序号作为占位，实际使用时由K线数据提供
struct DATEFunction: BuiltinFunction {
    let name = "DATE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        // DATE无参数，返回每根K线的日期
        // 实际应从bars的时间信息获取，当前返回索引占位
        return bars.enumerated().map { Decimal($0.offset) as Decimal? }
    }
}

/// TIME — 时间（HHMM格式数值）
struct TIMEFunction: BuiltinFunction {
    let name = "TIME"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { Decimal($0.offset) as Decimal? }
    }
}

/// HOUR — 小时
struct HOURFunction: BuiltinFunction {
    let name = "HOUR"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { Decimal($0.offset) as Decimal? }
    }
}

/// MINUTE — 分钟
struct MINUTEFunction: BuiltinFunction {
    let name = "MINUTE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        return bars.enumerated().map { Decimal($0.offset) as Decimal? }
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
