// v15.23 batch198 · Alert 配置 CSV 导出（trader 备份/分享预警配置 · 与 AlertHistoryCSVExporter 配对）
//
// 设计取舍（与 AlertHistoryCSVExporter 同模式 · BOM + CRLF · RFC 4180 转义）：
// - 字段：合约 / 预警名 / 状态 / 条件 / 通知渠道 / 冷却(秒) / 创建时间 / 最近触发
// - condition 用与 history 同样的 conditionLabel · 一致性
// - channels Set 排序后 + 分隔（CSV 单元格内多值用分号 ;）
// - status 中文化（活跃 / 已触发 / 已暂停 / 已取消）
// - 时间 Asia/Shanghai · yyyy-MM-dd HH:mm:ss · lastTriggeredAt nil → 空串

import Foundation

public enum AlertConfigCSVExporter {

    public static let header = [
        "合约", "预警名", "状态", "条件", "通知渠道", "冷却(秒)", "创建时间", "最近触发",
    ]

    public static func export(_ alerts: [Alert], timeZone: TimeZone? = nil) -> String {
        let tz = timeZone ?? TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append(header.map(escape).joined(separator: ","))
        for a in alerts {
            let row: [String] = [
                a.instrumentID,
                a.name,
                statusLabel(a.status),
                conditionLabel(a.condition),
                channelsLabel(a.channels),
                String(Int(a.cooldownSeconds)),
                formatter.string(from: a.createdAt),
                a.lastTriggeredAt.map(formatter.string(from:)) ?? "",
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func exportData(_ alerts: [Alert], timeZone: TimeZone? = nil) -> Data {
        export(alerts, timeZone: timeZone).data(using: .utf8) ?? Data()
    }

    // MARK: - 字段格式化

    static func statusLabel(_ s: AlertStatus) -> String {
        switch s {
        case .active:    return "活跃"
        case .triggered: return "已触发"
        case .paused:    return "已暂停"
        case .cancelled: return "已取消"
        }
    }

    static func channelsLabel(_ c: Set<NotificationChannelKind>) -> String {
        let sorted = c.sorted { $0.rawValue < $1.rawValue }
        return sorted.map(channelLabel).joined(separator: ";")
    }

    static func channelLabel(_ k: NotificationChannelKind) -> String {
        switch k {
        case .inApp:        return "App内"
        case .systemNotice: return "系统通知"
        case .sound:        return "声音"
        case .console:      return "调试输出"
        case .file:         return "文件日志"
        }
    }

    /// 与 AlertHistoryCSVExporter 同口径
    static func conditionLabel(_ c: AlertCondition) -> String {
        switch c {
        case .priceAbove(let p):                return "价格 ≥ \(p)"
        case .priceBelow(let p):                return "价格 ≤ \(p)"
        case .priceCrossAbove(let p):           return "上穿 \(p)"
        case .priceCrossBelow(let p):           return "下穿 \(p)"
        case .priceBreakoutHigh(let p, let n):  return "突破 \(p.rawValue) 前 \(n) 根高"
        case .priceBreakoutLow(let p, let n):   return "跌破 \(p.rawValue) 前 \(n) 根低"
        case .horizontalLineTouched(_, let p):  return "触线 \(p)"
        case .trendLineCrossed(_, _, let p0, _, let p1):
                                                return "穿越趋势线 \(p0)→\(p1)"
        case .volumeSpike(let m, let n):        return "成交量 ≥ \(m)× / \(n)期"
        case .openInterestSpike(let m, let n):  return "持仓量 ≥ \(m)× / \(n)期"
        case .priceMoveSpike(let p, let s):     return "急动 ≥ \(p)% / \(s)秒"
        case .indicator:                        return "指标条件"
        case .spreadDeviation(let id, let cal, let z):
            return "价差偏离 \(cal ? "跨期" : "跨品种") \(id) |z|≥\(z)"
        }
    }

    static func escape(_ field: String) -> String {
        let needsQuote = field.contains(",") || field.contains("\"")
                      || field.contains("\n") || field.contains("\r")
        if !needsQuote { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
