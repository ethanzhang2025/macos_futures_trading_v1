// AlertCore Linux 通道 v1 · FileChannel
// 文件追加日志通道（持久化预警记录 · 与 SQLite AlertHistory 互补）
//
// 设计：
// - actor 隔离：FileHandle 操作并发安全
// - 显式 close()：Swift 6 严格并发禁止 nonisolated deinit 访问 actor 状态
// - 失败不抛错：write 失败静默跳过（不影响其他通道 · 不阻塞 evaluator）
// - 不做 rotate / 大小限制（v1 简单追加；v2 按需加 rotate 策略）

import Foundation

public actor FileChannel: NotificationChannel {

    /// 通道标识（actor 字段须 nonisolated 才能满足协议 var 要求）
    public nonisolated let kind: NotificationChannelKind = .file

    private let path: String
    private var fileHandle: FileHandle?
    private let timestampFormatter: @Sendable (Date) -> String

    /// - Parameters:
    ///   - path: 日志文件绝对路径（不存在则自动创建；存在则 append）
    ///   - timestampFormatter: 时间格式化（默认 yyyy-MM-dd HH:mm:ss · Asia/Shanghai · 注入便于测试）
    public init(
        path: String,
        timestampFormatter: @escaping @Sendable (Date) -> String = FileChannel.defaultTimestamp
    ) throws {
        self.path = path
        self.timestampFormatter = timestampFormatter

        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        self.fileHandle = handle
    }

    public func send(_ event: NotificationEvent) async {
        guard let handle = fileHandle else { return }
        let ts = timestampFormatter(event.triggeredAt)
        let line = "[\(ts)] \(event.alertName) | \(event.instrumentID) | @ \(event.triggerPrice) | \(event.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    /// 显式关闭（Swift 6 严格并发要求）· close 后 send 静默 noop
    public func close() async {
        try? fileHandle?.close()
        fileHandle = nil
    }

    /// 当前底层文件路径（测试 / 内省用）
    public nonisolated var filePath: String { path }

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
