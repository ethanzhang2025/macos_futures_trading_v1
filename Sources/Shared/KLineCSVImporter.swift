// v17.169 · CSV K 线导入器（trader 加自己历史数据 · 券商 / Tushare / Wind / 通达信 / 文华 CSV 通吃）
//
// 核心难点：CSV 列顺序 / 时间格式 / 表头存在性 不一定 · 需自动嗅探
//
// 自动嗅探策略：
// 1. 表头检测：第 1 行 token 含字母（且不能完全 parse 为 Decimal）→ 当表头
// 2. 列映射：表头时按关键词（time/date · open · high · low · close · volume）→ 列 index
//    无表头时按 trader 常见顺序猜：[timestamp, open, high, low, close, volume]
// 3. 时间格式：依次尝试 4 种格式 · 第一根成功的 format 锁定全文件
//    - "yyyy-MM-dd HH:mm:ss"（最常见 daily/minute · 文华）
//    - "yyyy-MM-dd"（daily 简化）
//    - "yyyyMMdd HHmmss"（Tushare 风格）
//    - "yyyyMMdd"（daily 紧凑）
//    - Unix timestamp（10 位秒 / 13 位毫秒）
// 4. 数值列：Decimal(string:) · 失败行 → 加入 errors 不中断
//
// 输出：解析结果 + 错误清单（哪一行第几列哪个字段失败）· caller 决定是否接受部分成功

import Foundation

public struct KLineCSVImportResult: Sendable {
    public let bars: [KLine]
    public let errors: [String]   // 人类可读错误消息（"第 N 行: 时间无法解析 'XYZ'"）
    public let detectedFormat: String   // 调试用 · 显示检测出的时间格式

    public init(bars: [KLine], errors: [String], detectedFormat: String) {
        self.bars = bars
        self.errors = errors
        self.detectedFormat = detectedFormat
    }
}

public enum KLineCSVImporter {

    public enum ImportError: Error, Equatable {
        case emptyFile
        case noValidRows
        case timeFormatNotDetected   // 前 N 行所有时间格式都试不通
    }

    /// 从 CSV 内容解析 · instrumentID/period 由 caller 提供（CSV 不一定带这些元信息）
    public static func parse(
        csv: String,
        instrumentID: String,
        period: KLinePeriod
    ) throws -> KLineCSVImportResult {
        let lines = csv.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw ImportError.emptyFile }

        // 1. 表头检测
        let (hasHeader, columnMap) = detectHeaderAndColumns(firstLine: lines[0])
        let dataLines = hasHeader ? Array(lines.dropFirst()) : lines
        guard !dataLines.isEmpty else { throw ImportError.noValidRows }

        // 2. 时间格式嗅探（前 5 行任意成功即锁定）
        let cols = columnMap
        guard let timeFormat = detectTimeFormat(rows: Array(dataLines.prefix(5)), timeCol: cols.time) else {
            throw ImportError.timeFormatNotDetected
        }

        // 3. 逐行解析
        var bars: [KLine] = []
        var errors: [String] = []
        let dateFormatter = makeFormatter(timeFormat)
        let lineNumberOffset = hasHeader ? 2 : 1

        for (i, line) in dataLines.enumerated() {
            let fields = splitFields(line)
            let lineNum = i + lineNumberOffset
            guard fields.count > cols.maxIndex else {
                errors.append("第 \(lineNum) 行: 列数不足（需 ≥ \(cols.maxIndex + 1) · 实际 \(fields.count)）")
                continue
            }
            guard let time = parseTime(fields[cols.time], format: timeFormat, formatter: dateFormatter) else {
                errors.append("第 \(lineNum) 行: 时间无法解析 '\(fields[cols.time])'（期待 \(timeFormat)）")
                continue
            }
            guard let open  = Decimal(string: fields[cols.open]),
                  let high  = Decimal(string: fields[cols.high]),
                  let low   = Decimal(string: fields[cols.low]),
                  let close = Decimal(string: fields[cols.close]) else {
                errors.append("第 \(lineNum) 行: OHLC 数值无效")
                continue
            }
            let volume: Int = cols.volume.flatMap { idx in
                idx < fields.count ? Int(fields[idx]) ?? 0 : 0
            } ?? 0
            bars.append(KLine(
                instrumentID: instrumentID,
                period: period,
                openTime: time,
                open: open, high: high, low: low, close: close,
                volume: volume,
                openInterest: 0,
                turnover: 0
            ))
        }
        return KLineCSVImportResult(bars: bars, errors: errors, detectedFormat: timeFormat)
    }

    // MARK: - 表头嗅探

    /// 列映射 · 时间 / OHLC 必须存在 · volume 可选
    public struct ColumnMap: Sendable {
        public let time: Int
        public let open: Int
        public let high: Int
        public let low: Int
        public let close: Int
        public let volume: Int?

        var maxIndex: Int {
            max(time, open, high, low, close, volume ?? 0)
        }
    }

    /// 第 1 行 token 含字母（且整体不能 parse 为纯数值）→ 当表头 · 否则当数据
    static func detectHeaderAndColumns(firstLine: String) -> (hasHeader: Bool, columns: ColumnMap) {
        let fields = splitFields(firstLine)
        let firstParse = fields.allSatisfy { Decimal(string: $0) != nil || $0.isEmpty }
        if !firstParse {
            // 有表头 · 按关键词匹配
            let lower = fields.map { $0.lowercased() }
            let timeIdx  = lower.firstIndex { $0.contains("time") || $0.contains("date") || $0.contains("时间") || $0.contains("日期") } ?? 0
            let openIdx  = lower.firstIndex { $0.contains("open") || $0.contains("开") } ?? 1
            let highIdx  = lower.firstIndex { $0.contains("high") || $0.contains("高") } ?? 2
            let lowIdx   = lower.firstIndex { $0.contains("low") || $0.contains("低") } ?? 3
            let closeIdx = lower.firstIndex { $0.contains("close") || $0.contains("收") } ?? 4
            let volIdx   = lower.firstIndex { $0.contains("vol") || $0.contains("量") }
            return (true, ColumnMap(time: timeIdx, open: openIdx, high: highIdx, low: lowIdx, close: closeIdx, volume: volIdx))
        }
        // 无表头 · 默认 trader 常见列序：[time, open, high, low, close, volume]
        return (false, ColumnMap(time: 0, open: 1, high: 2, low: 3, close: 4, volume: fields.count > 5 ? 5 : nil))
    }

    // MARK: - 时间格式嗅探

    static func detectTimeFormat(rows: [String], timeCol: Int) -> String? {
        let candidates = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyyMMdd HHmmss",
            "yyyyMMdd"
        ]
        for fmt in candidates {
            let f = makeFormatter(fmt)
            for row in rows {
                let fields = splitFields(row)
                guard timeCol < fields.count else { continue }
                if f.date(from: fields[timeCol]) != nil {
                    return fmt
                }
            }
        }
        // Unix timestamp（10 位秒 / 13 位毫秒）
        for row in rows {
            let fields = splitFields(row)
            guard timeCol < fields.count else { continue }
            if let _ = TimeInterval(fields[timeCol]) {
                return "UNIX"
            }
        }
        return nil
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = format
        return f
    }

    private static func parseTime(_ s: String, format: String, formatter: DateFormatter) -> Date? {
        if format == "UNIX" {
            guard let n = Double(s) else { return nil }
            // 10 位秒 / 13 位毫秒
            return n > 1_000_000_000_000 ? Date(timeIntervalSince1970: n / 1000) : Date(timeIntervalSince1970: n)
        }
        return formatter.date(from: s)
    }

    // MARK: - 字段切分（逗号 · 简化版 · 不支持引号转义嵌入逗号 · trader 行情 CSV 极少这种）

    static func splitFields(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}
