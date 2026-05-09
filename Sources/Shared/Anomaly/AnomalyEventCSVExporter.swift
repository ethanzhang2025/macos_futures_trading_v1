// 异常事件 CSV 导出（v15.64 · ⌘⌥A → 工具栏 export 按钮）
//
// trader 用法：归档历史异常 / 模式分析 / 报告生成
//
// 设计（与 AlertHistoryCSVExporter 同模式）：
// - UTF-8 BOM + CRLF（Excel 识别中文 + Windows 兼容）
// - 字段：检测时间 / 类型 / 严重度 / 品种 / 板块 / 说明
// - 时间 Asia/Shanghai · yyyy-MM-dd HH:mm:ss
// - RFC 4180 转义（含 , " \n \r 时外加引号 + 内部 " 双写）

import Foundation

public enum AnomalyEventCSVExporter {

    public static let header = [
        "检测时间", "类型", "严重度", "品种ID", "品种名", "板块", "说明"
    ]

    /// 导出 [AnomalyEvent] 为 CSV 字符串
    /// - Parameters:
    ///   - events: 事件列表（任意顺序 · CSV 按传入顺序）
    ///   - timeZone: 时区（默认 Asia/Shanghai · 注入便于测试）
    public static func export(_ events: [AnomalyEvent], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for e in events {
            let row: [String] = [
                formatter.string(from: e.detectedAt),
                e.kind.displayName,
                String(format: "%.0f", e.severity),
                e.instrumentID,
                e.instrumentName,
                e.sector.displayName,
                e.description
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ events: [AnomalyEvent], timeZone: TimeZone? = nil) -> Data {
        export(events, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
