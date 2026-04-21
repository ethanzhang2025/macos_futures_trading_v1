import Foundation

/// 统一的数字格式化工具，替代 KLineChartView/TimelineChartView/OrderBookPanel 里三份重复实现
enum Formatters {
    /// 价格：≥1000 取整；≥10 保留 1 位；否则 2 位
    static func price(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    /// 涨跌幅（绝对值），带正负号，取整
    static func change(_ c: Decimal) -> String {
        String(format: "%+.0f", NSDecimalNumber(decimal: c).doubleValue)
    }

    /// 涨跌幅百分比，带正负号，保留 2 位 + %
    static func percent(_ p: Decimal) -> String {
        String(format: "%+.2f%%", NSDecimalNumber(decimal: p).doubleValue)
    }

    /// 金额千分位（账户权益/保证金等，取整）
    static func money(_ v: Decimal) -> String {
        grouped(NSDecimalNumber(decimal: v).doubleValue, fractionDigits: 0)
    }

    /// 金额带正负号（盈亏用，千分位，取整）
    static func signedMoney(_ v: Decimal) -> String {
        let d = NSDecimalNumber(decimal: v).doubleValue
        let s = grouped(abs(d), fractionDigits: 0)
        return d >= 0 ? "+\(s)" : "-\(s)"
    }

    /// 大整数千分位（成交量/持仓量等）
    static func bigNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func grouped(_ d: Double, fractionDigits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: d)) ?? "\(d)"
    }
}
