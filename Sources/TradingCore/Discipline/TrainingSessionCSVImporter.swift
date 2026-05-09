// v16.24 · 训练 session 历史 CSV 导入（与 TrainingSessionCSVExporter 配套）
//
// 用途：
// - trader 跨设备同步训练历史（A 机导出 → B 机导入）
// - 备份恢复（UserDefaults 损坏 / 升级丢失时还原）
//
// 设计：
// - 输入：CSV 字符串（容忍 BOM 前缀 · 容忍 \r\n 或 \n 行分隔）
// - 输出：解析后的 [TrainingSession]（调用方决定 merge 还是 overwrite）
// - 错误处理：行级跳过（单行字段不全 / 数值无法解析 → 静默丢弃 · 不抛）· 文件级仅 header 缺失才返回空
// - 字段映射：通过 header 行的中文标题 → 列索引（与 exporter header 严格对齐）

import Foundation

public enum TrainingSessionCSVImporter {

    /// 导入 CSV 为 TrainingSession 数组（无 score · 调用方 addSession 自动评分）
    public static func parse(_ csv: String, timeZone: TimeZone? = nil) -> [TrainingSession] {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        // 容忍 UTF-8 BOM
        var content = csv
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }
        // 容忍 \r\n / \n
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return [] }

        // header → 字段索引
        let headerCols = parseLine(lines[0])
        guard let idx = buildIndex(headerCols) else { return [] }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = tz
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var result: [TrainingSession] = []
        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let cols = parseLine(line)
            guard let session = decodeRow(cols, idx: idx, fmt: fmt) else { continue }
            result.append(session)
        }
        return result
    }

    // MARK: - 列索引解析

    struct ColumnIndex {
        let endedAt: Int
        let durationMin: Int
        let scenarioName: Int
        let pattern: Int?
        let initialBalance: Int
        let finalBalance: Int
        let errors: Int?
        let warnings: Int?
        let tradeCount: Int?
    }

    static func buildIndex(_ header: [String]) -> ColumnIndex? {
        func find(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let endedAt = find("训练结束时间"),
              let durationMin = find("时长(分)"),
              let scenarioName = find("场景"),
              let initialBalance = find("初始资金"),
              let finalBalance = find("最终资金") else { return nil }
        return ColumnIndex(
            endedAt: endedAt,
            durationMin: durationMin,
            scenarioName: scenarioName,
            pattern: find("形态"),
            initialBalance: initialBalance,
            finalBalance: finalBalance,
            errors: find("违规数"),
            warnings: find("警告数"),
            tradeCount: find("交易笔数")
        )
    }

    // MARK: - 单行解析

    static func decodeRow(_ cols: [String], idx: ColumnIndex, fmt: DateFormatter) -> TrainingSession? {
        guard cols.count > max(idx.endedAt, idx.durationMin, idx.scenarioName,
                               idx.initialBalance, idx.finalBalance) else { return nil }
        guard let endedAt = fmt.date(from: cols[idx.endedAt]),
              let durationMin = Int(cols[idx.durationMin]),
              let initial = Decimal(string: cols[idx.initialBalance]),
              let final = Decimal(string: cols[idx.finalBalance]) else { return nil }
        let startedAt = endedAt.addingTimeInterval(TimeInterval(-durationMin * 60))
        let scenarioName = cols[idx.scenarioName]
        let pattern: TrainingScenarioPattern? = idx.pattern.flatMap {
            cols.indices.contains($0) ? matchPatternByName(cols[$0]) : nil
        }
        // 违规重建（severity + count · 详细 message 不还原 · message 仅评分用 count）
        var violations: [DisciplineViolation] = []
        if let ei = idx.errors, cols.indices.contains(ei),
           let n = Int(cols[ei]) {
            for _ in 0..<n {
                violations.append(DisciplineViolation(
                    ruleID: UUID(), ruleKind: .stopLossPercent, occurredAt: endedAt,
                    severity: .error, message: ""))
            }
        }
        if let wi = idx.warnings, cols.indices.contains(wi),
           let n = Int(cols[wi]) {
            for _ in 0..<n {
                violations.append(DisciplineViolation(
                    ruleID: UUID(), ruleKind: .maxHoldingMinutes, occurredAt: endedAt,
                    severity: .warning, message: ""))
            }
        }
        return TrainingSession(
            startedAt: startedAt, endedAt: endedAt,
            initialBalance: initial, finalBalance: final,
            violations: violations,
            scenarioName: scenarioName,
            scenarioPattern: pattern
        )
    }

    /// 中文 displayName 反查 pattern · 不命中返回 nil
    static func matchPatternByName(_ name: String) -> TrainingScenarioPattern? {
        guard !name.isEmpty else { return nil }
        return TrainingScenarioPattern.allCases.first { $0.displayName == name }
    }

    // MARK: - CSV 行解析（RFC 4180 简化 · 处理引号转义）

    /// 解析单行 CSV → 字段数组
    /// - 字段以 `,` 分隔
    /// - `"` 包围的字段允许内嵌 `,` / `\n` · `""` 转义为 `"`
    static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
