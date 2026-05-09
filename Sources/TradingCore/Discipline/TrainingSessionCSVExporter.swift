// v16.20 · 训练 session 历史 CSV 导出（trader 离线 Excel/Numbers 分析）
//
// 设计：
// - 一行一 session · UTF-8 BOM + CRLF · RFC 4180（与 TradeCSVExporter / ClosedPositionCSVExporter 同模式）
// - 字段含 v1 主分（pnl/discipline）+ v2 五维子分（含 weakest）+ 违规/警告/交易数
// - subScores 为 nil（老 session）时输出空值 · trader 用 Excel 公式可过滤
// - 时区默认 Asia/Shanghai · 与 trader 实际生活对齐

import Foundation

public enum TrainingSessionCSVExporter {

    public static let header = [
        "训练结束时间", "时长(分)", "场景", "形态",
        "初始资金", "最终资金", "盈亏率%",
        "总分", "等级", "盈亏子分", "纪律子分",
        "维度_盈亏", "维度_纪律", "维度_胜率", "维度_风险", "维度_效率", "最弱维度",
        "违规数", "警告数", "交易笔数",
    ]

    public static func export(_ log: TrainingSessionLog, timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = tz
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        // 时间降序（最新在前 · trader 习惯）
        let sorted = log.sessions.sorted { $0.endedAt > $1.endedAt }
        for s in sorted {
            let score = log.score(for: s.id)
            let sub = score?.subScores
            let errors = s.violations.filter { $0.severity == .error }.count
            let warnings = s.violations.filter { $0.severity == .warning }.count
            let row: [String] = [
                fmt.string(from: s.endedAt),
                String(s.durationMinutes),
                s.scenarioName,
                s.scenarioPattern?.displayName ?? "",
                NSDecimalNumber(decimal: s.initialBalance).stringValue,
                NSDecimalNumber(decimal: s.finalBalance).stringValue,
                String(format: "%.2f", (s.pnlPercent as NSDecimalNumber).doubleValue),
                score.map { String($0.totalScore) } ?? "",
                score?.grade.rawValue ?? "",
                score.map { String($0.pnlScore) } ?? "",
                score.map { String($0.disciplineScore) } ?? "",
                sub.map { String($0.pnl) } ?? "",
                sub.map { String($0.discipline) } ?? "",
                sub.map { String($0.winRate) } ?? "",
                sub.map { String($0.risk) } ?? "",
                sub.map { String($0.efficiency) } ?? "",
                sub?.weakest.displayName ?? "",
                String(errors),
                String(warnings),
                String(s.trades.count),
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ log: TrainingSessionLog, timeZone: TimeZone? = nil) -> Data {
        export(log, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    private static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
