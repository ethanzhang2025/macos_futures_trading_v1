// v15.19 batch19 · AlertHistory CSV 导出（trader 复盘所有触发预警 · 报税 / 归档 / 模式分析）
//
// 设计取舍（与 ClosedPositionCSVExporter 同模式）：
// - UTF-8 BOM + CRLF（Excel 识别中文 + Windows 兼容）
// - 字段：触发时间 / 合约 / 预警名 / 条件 / 触发价 / 说明
// - 时间 Asia/Shanghai · yyyy-MM-dd HH:mm:ss
// - 价格 NSDecimalNumber stringValue 保留原始精度
// - RFC 4180 转义（含 , " \n \r 时外加引号 + 内部 " 双写）

import Foundation

public enum AlertHistoryCSVExporter {

    public static let header = [
        "触发时间", "合约", "预警名", "条件", "触发价", "说明"
    ]

    public static func export(_ entries: [AlertHistoryEntry], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for e in entries {
            let row: [String] = [
                formatter.string(from: e.triggeredAt),
                e.instrumentID,
                e.alertName,
                conditionLabel(e.conditionSnapshot),
                NSDecimalNumber(decimal: e.triggerPrice).stringValue,
                e.message
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ entries: [AlertHistoryEntry], timeZone: TimeZone? = nil) -> Data {
        export(entries, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    /// AlertCondition 简短中文标签（独立于 MainApp 的 displayDescription · CSV 不含动态价格 · 留 message 字段消化触发上下文）
    private static func conditionLabel(_ c: AlertCondition) -> String {
        switch c {
        case .priceAbove(let p):                return "价格 ≥ \(p)"
        case .priceBelow(let p):                return "价格 ≤ \(p)"
        case .priceCrossAbove(let p):           return "上穿 \(p)"
        case .priceCrossBelow(let p):           return "下穿 \(p)"
        case .priceBreakoutHigh(let p, let n):  return "突破 \(p.rawValue) 前 \(n) 根高"
        case .priceBreakoutLow(let p, let n):   return "跌破 \(p.rawValue) 前 \(n) 根低"
        case .horizontalLineTouched(_, let p):  return "触线 \(p)"
        case .volumeSpike(let m, let n):        return "成交量 ≥ \(m)× / \(n)期"
        case .openInterestSpike(let m, let n):  return "持仓量 ≥ \(m)× / \(n)期"
        case .priceMoveSpike(let p, let s):     return "急动 ≥ \(p)% / \(s)秒"
        case .indicator:                        return "指标条件"
        }
    }

    private static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
