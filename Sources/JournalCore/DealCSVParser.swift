// WP-53 模块 2 · 交割单 CSV 导入与归一化转换层
// A09 禁做项关键："不要把原始交割单数据直接当最终业务模型使用"
//   → RawDeal：CSV 行的 1:1 映射（保留所有字段为 String，不做语义转换）
//   → Trade：标准化业务模型
//   → RawDeal.toTrade(source:) 是显式的转换边界
//
// 支持格式：
// - wenhua: 文华财经导出的交割单格式（中文表头）
// - generic: 通用 CSV 格式（英文表头，可适配多数券商）
//
// 解析容错：
// - 跳过空行
// - 跳过表头行（header）
// - 单行解析失败抛 ParseError，caller 决定是否中止 vs 跳过

import Foundation
import Shared

// MARK: - CSV 格式

public enum DealCSVFormat: String, Sendable, Codable, CaseIterable {
    case wenhua    // 文华财经
    case generic   // 通用
}

// MARK: - 解析错误

public enum DealCSVError: Error, Equatable, CustomStringConvertible {
    case invalidEncoding
    case missingColumn(name: String, line: Int)
    case invalidValue(field: String, value: String, line: Int)
    case unsupportedFormat(DealCSVFormat)

    public var description: String {
        switch self {
        case .invalidEncoding:
            return "CSV 编码错误（非 UTF-8）"
        case .missingColumn(let name, let line):
            return "第 \(line) 行缺少字段 \(name)"
        case .invalidValue(let field, let value, let line):
            return "第 \(line) 行字段 \(field) 值非法：\(value)"
        case .unsupportedFormat(let format):
            return "暂不支持格式 \(format.rawValue)"
        }
    }
}

// MARK: - RawDeal · CSV 行 1:1 映射

/// 原始 CSV 一行 · 所有字段保留为 String，不做语义转换
/// 这是禁做项的边界守卫：RawDeal 永远不进业务流，必须先 toTrade() 转换
public struct RawDeal: Sendable, Codable, Equatable, Hashable {
    public let lineNumber: Int      // CSV 第几行（含表头）
    public let format: DealCSVFormat
    /// 原始字段（key 是表头列名，value 是该行该列的字符串）
    public let fields: [String: String]

    public init(lineNumber: Int, format: DealCSVFormat, fields: [String: String]) {
        self.lineNumber = lineNumber
        self.format = format
        self.fields = fields
    }
}

// MARK: - 解析器

public enum DealCSVParser {

    /// 解析 CSV 字符串为 RawDeal 数组
    /// - Parameter csvString: 完整 CSV 内容（含表头）
    /// - Throws: DealCSVError.invalidEncoding（无效编码）/ missingColumn（表头缺关键列）
    public static func parse(_ csvString: String, format: DealCSVFormat) throws -> [RawDeal] {
        // 按 \n / \r 都拆（兼容 LF / CRLF / CR 三种行尾）
        let lines = csvString.split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }

        let headers = splitCSVLine(lines[0])
        try validateHeaders(headers, format: format)

        var deals: [RawDeal] = []
        deals.reserveCapacity(max(lines.count - 1, 0))
        for (index, line) in lines.enumerated() where index > 0 {
            let values = splitCSVLine(line)
            guard values.count == headers.count else {
                throw DealCSVError.missingColumn(name: "<列数不匹配>", line: index + 1)
            }
            var fields: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                fields[header] = values[i]
            }
            deals.append(RawDeal(lineNumber: index + 1, format: format, fields: fields))
        }
        return deals
    }

    /// 极简 CSV 行拆分（v1 不处理引号转义；ChatGPT A09 v1 范围接受）
    /// 文华 / 通用 CSV 实测均不含引号转义
    private static func splitCSVLine(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 校验表头必含关键列
    private static func validateHeaders(_ headers: [String], format: DealCSVFormat) throws {
        let required: [String] = format.requiredColumns
        for column in required where !headers.contains(column) {
            throw DealCSVError.missingColumn(name: column, line: 1)
        }
    }
}

// MARK: - 格式列契约

extension DealCSVFormat {
    /// 该格式必含的表头列名（缺失则解析失败）
    public var requiredColumns: [String] {
        switch self {
        case .wenhua:
            return ["合约", "买卖", "开平", "成交价", "成交量", "手续费", "成交时间", "成交编号"]
        case .generic:
            return ["instrument", "direction", "offset", "price", "volume", "commission", "timestamp", "trade_id"]
        }
    }
}

// MARK: - RawDeal → Trade 标准化转换

extension RawDeal {

    /// 转换为标准 Trade · 显式边界（A09 禁做项落实）
    /// - Throws: DealCSVError.invalidValue（字段值无法解析为目标类型）
    public func toTrade() throws -> Trade {
        switch format {
        case .wenhua:  return try toTradeFromWenhua()
        case .generic: return try toTradeFromGeneric()
        }
    }

    private func toTradeFromWenhua() throws -> Trade {
        let instrumentID = try requireField("合约")
        let direction = try parseDirection(try requireField("买卖"), wenhua: true)
        let offset = try parseOffset(try requireField("开平"), wenhua: true)
        let price = try requireDecimal("成交价")
        let volume = try requireInt("成交量")
        let commission = try requireDecimal("手续费")
        let timestamp = try parseDate(try requireField("成交时间"))
        let reference = try requireField("成交编号")

        return Trade(
            tradeReference: reference,
            instrumentID: instrumentID,
            direction: direction, offsetFlag: offset,
            price: price, volume: volume, commission: commission,
            timestamp: timestamp, source: .wenhua
        )
    }

    private func toTradeFromGeneric() throws -> Trade {
        let instrumentID = try requireField("instrument")
        let direction = try parseDirection(try requireField("direction"), wenhua: false)
        let offset = try parseOffset(try requireField("offset"), wenhua: false)
        let price = try requireDecimal("price")
        let volume = try requireInt("volume")
        let commission = try requireDecimal("commission")
        let timestamp = try parseDate(try requireField("timestamp"))
        let reference = try requireField("trade_id")

        return Trade(
            tradeReference: reference,
            instrumentID: instrumentID,
            direction: direction, offsetFlag: offset,
            price: price, volume: volume, commission: commission,
            timestamp: timestamp, source: .generic
        )
    }

    // MARK: - 字段提取 helpers

    private func requireField(_ name: String) throws -> String {
        guard let value = fields[name], !value.isEmpty else {
            throw DealCSVError.missingColumn(name: name, line: lineNumber)
        }
        return value
    }

    private func requireDecimal(_ name: String) throws -> Decimal {
        let raw = try requireField(name)
        guard let value = Decimal(string: raw) else {
            throw DealCSVError.invalidValue(field: name, value: raw, line: lineNumber)
        }
        return value
    }

    private func requireInt(_ name: String) throws -> Int {
        let raw = try requireField(name)
        guard let value = Int(raw) else {
            throw DealCSVError.invalidValue(field: name, value: raw, line: lineNumber)
        }
        return value
    }

    private func parseDirection(_ raw: String, wenhua: Bool) throws -> Direction {
        if wenhua {
            switch raw {
            case "买", "买入", "0": return .buy
            case "卖", "卖出", "1": return .sell
            default: throw DealCSVError.invalidValue(field: "买卖", value: raw, line: lineNumber)
            }
        } else {
            switch raw.lowercased() {
            case "buy", "long", "0":  return .buy
            case "sell", "short", "1": return .sell
            default: throw DealCSVError.invalidValue(field: "direction", value: raw, line: lineNumber)
            }
        }
    }

    private func parseOffset(_ raw: String, wenhua: Bool) throws -> OffsetFlag {
        if wenhua {
            switch raw {
            case "开仓", "开", "0":     return .open
            case "平仓", "平", "1":     return .close
            case "强平", "2":           return .forceClose
            case "平今", "3":           return .closeToday
            case "平昨", "4":           return .closeYesterday
            default: throw DealCSVError.invalidValue(field: "开平", value: raw, line: lineNumber)
            }
        } else {
            switch raw.lowercased() {
            case "open", "0":          return .open
            case "close", "1":         return .close
            case "force_close", "2":   return .forceClose
            case "close_today", "3":   return .closeToday
            case "close_yesterday", "4": return .closeYesterday
            default: throw DealCSVError.invalidValue(field: "offset", value: raw, line: lineNumber)
            }
        }
    }

    /// 解析时间戳 · 支持 ISO8601 + "yyyy-MM-dd HH:mm:ss" + "yyyyMMdd HHmmss" 三种常见格式
    private func parseDate(_ raw: String) throws -> Date {
        // 1. ISO8601
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        // 2. "yyyy-MM-dd HH:mm:ss"
        if let d = Self.standardFormatter.date(from: raw) { return d }
        // 3. "yyyyMMdd HHmmss"
        if let d = Self.compactFormatter.date(from: raw) { return d }
        throw DealCSVError.invalidValue(field: "timestamp", value: raw, line: lineNumber)
    }

    private static let standardFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let compactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd HHmmss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
