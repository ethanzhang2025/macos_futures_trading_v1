// WP-50 v15.18 · ClosedPosition CSV 导出（trader 报税 / 复盘归档必备）
//
// 设计取舍：
// - 输出 UTF-8 BOM + CRLF 换行（Excel 识别中文 + Windows 兼容）
// - 字段顺序：日期 / 合约 / 方向 / 开仓价 / 平仓价 / 手数 / 盈亏 / 手续费 / 持仓时长（分钟）
// - 时间用 Asia/Shanghai · yyyy-MM-dd HH:mm:ss
// - 价格 / 盈亏 / 手续费用 NSDecimalNumber stringValue 保留原始精度
// - 字段值含逗号 / 引号 / 换行时按 RFC 4180 转义（外加引号 + 内部引号双写）

import Foundation
import Shared

public enum ClosedPositionCSVExporter {

    /// CSV 表头（中文 · 与字段顺序一致）
    public static let header = [
        "平仓时间", "合约", "方向", "开仓价", "平仓价", "手数",
        "盈亏", "手续费", "持仓分钟", "开仓时间"
    ]

    /// 导出为 UTF-8 String（含 BOM · CRLF）
    public static func export(_ positions: [ClosedPosition], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for p in positions {
            let durationMin = Int(p.holdingSeconds / 60)
            let row: [String] = [
                formatter.string(from: p.closeTime),
                p.instrumentID,
                p.side == .long ? "多" : "空",
                NSDecimalNumber(decimal: p.openPrice).stringValue,
                NSDecimalNumber(decimal: p.closePrice).stringValue,
                String(p.volume),
                NSDecimalNumber(decimal: p.realizedPnL).stringValue,
                NSDecimalNumber(decimal: p.totalCommission).stringValue,
                String(durationMin),
                formatter.string(from: p.openTime)
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        // BOM + CRLF（Excel 识别中文 / Windows 兼容）
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 导出为 Data（含 BOM · 写文件用）
    public static func exportData(_ positions: [ClosedPosition], timeZone: TimeZone? = nil) -> Data {
        let str = export(positions, timeZone: timeZone)
        return str.data(using: .utf8) ?? Data()
    }

    /// RFC 4180 字段转义：含 `,` / `"` / `\n` / `\r` 时外加引号 · 内部 `"` 双写
    private static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
