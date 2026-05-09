// 组合异常 CSV 导出（v15.71 · ⌘⌥A combo 视图工具栏 export）
//
// WHY: 与 AnomalyEventCSVExporter 一致的输出契约
// - UTF-8 BOM + CRLF（Excel 识别中文 + Windows 兼容）
// - 命中类型按 AnomalyKind.allCases 顺序（与 UI tag 顺序一致 · trader 肌肉记忆）
// - 时间 Asia/Shanghai · RFC 4180 转义

import Foundation

public enum ComboAnomalyCSVExporter {

    public static let header = [
        "排名", "品种ID", "品种名", "板块", "类型数", "命中类型", "avg严重度", "combo严重度", "检测时间"
    ]

    /// 导出 [ComboAnomaly] 为 CSV 字符串
    /// - Parameters:
    ///   - combos: combo 列表（按传入顺序 · 通常已 totalSeverity desc）
    ///   - timeZone: 时区（默认 Asia/Shanghai · 注入便于测试）
    public static func export(_ combos: [ComboAnomaly], timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = [header.map(escape).joined(separator: ",")]
        lines.reserveCapacity(combos.count + 1)
        for (idx, c) in combos.enumerated() {
            let kindsLabel = AnomalyKind.allCases
                .filter { c.kinds.contains($0) }
                .map(\.displayName)
                .joined(separator: " · ")
            let row: [String] = [
                String(idx + 1),
                c.instrumentID,
                c.instrumentName,
                c.sector.displayName,
                String(c.kindCount),
                kindsLabel,
                String(format: "%.1f", c.avgSeverity),
                String(format: "%.1f", c.totalSeverity),
                formatter.string(from: c.detectedAt)
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ combos: [ComboAnomaly], timeZone: TimeZone? = nil) -> Data {
        export(combos, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        guard needsQuote else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
