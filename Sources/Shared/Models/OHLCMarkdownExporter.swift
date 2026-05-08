import Foundation

/// v15.21 batch87 · OHLC 切片转 Markdown 表格 · trader 复盘聊天/邮件/Notion 分享
public enum OHLCMarkdownExporter {
    /// 列：时间 / 开 / 高 / 低 / 收 / 量 / 持仓 / 涨跌%（涨跌% = (close-open)/open · 2 位小数 + 符号）
    public static func render(_ bars: [KLine], dateFormat: String = "yyyy-MM-dd HH:mm") -> String {
        guard !bars.isEmpty else { return "" }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = dateFormat
        var lines: [String] = []
        lines.append("| 时间 | 开 | 高 | 低 | 收 | 量 | 持仓 | 涨跌% |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for bar in bars {
            let t = dateFmt.string(from: bar.openTime)
            let o = NSDecimalNumber(decimal: bar.open).stringValue
            let h = NSDecimalNumber(decimal: bar.high).stringValue
            let l = NSDecimalNumber(decimal: bar.low).stringValue
            let c = NSDecimalNumber(decimal: bar.close).stringValue
            let oi = NSDecimalNumber(decimal: bar.openInterest).stringValue
            let pct = formatChangePercent(open: bar.open, close: bar.close)
            lines.append("| \(t) | \(o) | \(h) | \(l) | \(c) | \(bar.volume) | \(oi) | \(pct) |")
        }
        return lines.joined(separator: "\n")
    }

    /// (close-open)/open × 100 · 2 位小数 · 含符号 · open=0 显示 "—"
    public static func formatChangePercent(open: Decimal, close: Decimal) -> String {
        guard open != 0 else { return "—" }
        let openD = NSDecimalNumber(decimal: open).doubleValue
        let closeD = NSDecimalNumber(decimal: close).doubleValue
        let pct = (closeD - openD) / openD * 100
        let sign = pct > 0 ? "+" : (pct < 0 ? "" : "")  // 负值 String(format) 自带 "-"
        return String(format: "\(sign)%.2f%%", pct)
    }
}
