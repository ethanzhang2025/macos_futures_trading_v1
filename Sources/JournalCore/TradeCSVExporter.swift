// WP-53 v15.18 · Trade CSV 导出（原始成交记录 · 与 ClosedPositionCSVExporter 互补）
//
// 设计取舍：
// - 输出 trade 流水原貌（开 + 平都在）· trader 操盘审计 / 报税附件
// - 与 ClosedPositionCSVExporter 同模式（UTF-8 BOM + CRLF · RFC 4180）
// - 字段：成交时间 / 合约 / 方向 / 开平 / 价格 / 手数 / 手续费 / 来源

import Foundation
import Shared

public enum TradeCSVExporter {

    public static let header = [
        "成交时间", "合约", "方向", "开平", "成交价", "手数",
        "手续费", "来源", "策略"
    ]

    public static func export(_ trades: [Trade], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = tz
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for t in trades {
            let row: [String] = [
                fmt.string(from: t.timestamp),
                t.instrumentID,
                t.direction == .buy ? "买" : "卖",
                t.offsetFlag.displayName,
                NSDecimalNumber(decimal: t.price).stringValue,
                String(t.volume),
                NSDecimalNumber(decimal: t.commission).stringValue,
                t.source.rawValue,
                t.setup ?? ""   // v15.98 · 复盘 v2 · 策略标签（nil/空 trader 未标）
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ trades: [Trade], timeZone: TimeZone? = nil) -> Data {
        export(trades, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    private static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
