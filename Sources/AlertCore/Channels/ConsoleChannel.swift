// AlertCore Linux 通道 v1 · ConsoleChannel
// 比 LoggingNotificationChannel 更"production"的 stdout 通道：
// - 带时间戳（注入便于测试 100% 确定）
// - 带前缀（区分多 alert app）
// - writer 闭包注入（默认 print；测试可拦截）
//
// 用途：开发期 + Linux production（Linux 无系统通知中心，console 是默认输出通道）

import Foundation

public struct ConsoleChannel: NotificationChannel {

    public let kind: NotificationChannelKind = .console

    private let prefix: String
    private let timestampFormatter: @Sendable (Date) -> String
    private let writer: @Sendable (String) -> Void

    /// - Parameters:
    ///   - prefix: 行首前缀（如 "[Alert]" / "[Bot01]"），便于多源日志区分
    ///   - timestampFormatter: 时间格式化（默认 yyyy-MM-dd HH:mm:ss · Asia/Shanghai · 注入便于测试）
    ///   - writer: 输出器（默认 print → stdout · 测试可注入闭包拦截）
    public init(
        prefix: String = "[Alert]",
        timestampFormatter: @escaping @Sendable (Date) -> String = ConsoleChannel.defaultTimestamp,
        writer: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.prefix = prefix
        self.timestampFormatter = timestampFormatter
        self.writer = writer
    }

    public func send(_ event: NotificationEvent) async {
        let ts = timestampFormatter(event.triggeredAt)
        writer("\(prefix) [\(ts)] 🔔 \(event.alertName) · \(event.instrumentID) @ \(event.triggerPrice) · \(event.message)")
    }

    /// 默认时间格式化器（yyyy-MM-dd HH:mm:ss · Asia/Shanghai · en_US_POSIX）
    /// static let 复用同一 DateFormatter，避免每次 send 重新分配
    public static func defaultTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
