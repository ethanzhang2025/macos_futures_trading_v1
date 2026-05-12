// v17.49 D5 v2 · BacktestHistory CSV 导出（trader 月底导 Excel 分析）
//
// 设计（与 AlertHistoryCSVExporter 同模式）：
// - UTF-8 BOM + CRLF（Excel 识别中文 + Windows 兼容）
// - 14 字段全量：含成本配置 + 指标 + 元数据
// - 时间 Asia/Shanghai · yyyy-MM-dd HH:mm:ss
// - 数值 NSDecimalNumber stringValue 保留原始精度
// - RFC 4180 转义（含 , " \n \r 时外加引号 + 内部 " 双写）

import Foundation

public enum BacktestHistoryCSVExporter {

    public static let header = [
        "保存时间", "信号 line", "标的轨迹", "bars", "trades",
        "初始权益", "endingPnL", "maxDrawdown",
        "Sharpe", "Sortino", "Calmar",
        "胜率%", "期望/笔",
        "commission", "slippage", "allowShort"
    ]

    public static func export(_ entries: [BacktestHistoryEntry], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for e in entries {
            let row: [String] = [
                formatter.string(from: e.createdAt),
                e.signalLineName,
                trajectoryDisplay(e.trajectoryRaw),
                String(e.barCount),
                String(e.tradeCount),
                NSDecimalNumber(decimal: e.initialEquity).stringValue,
                NSDecimalNumber(decimal: e.endingPnL).stringValue,
                NSDecimalNumber(decimal: e.maxDrawdown).stringValue,
                String(format: "%.4f", e.sharpe),
                String(format: "%.4f", e.sortino),
                String(format: "%.4f", e.calmar),
                String(format: "%.2f", e.winRate * 100),
                NSDecimalNumber(decimal: e.expectancy).stringValue,
                NSDecimalNumber(decimal: e.commission).stringValue,
                NSDecimalNumber(decimal: e.slippage).stringValue,
                e.allowShort ? "1" : "0"
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ entries: [BacktestHistoryEntry], timeZone: TimeZone? = nil) -> Data {
        export(entries, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    private static func trajectoryDisplay(_ raw: String) -> String {
        switch raw {
        case "random":   return "随机游走"
        case "up":       return "上涨趋势"
        case "down":     return "下跌趋势"
        case "sideways": return "横盘震荡"
        default:         return raw
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
