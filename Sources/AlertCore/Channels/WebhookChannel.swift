// AlertCore v17.32 B3 · WebhookChannel
// 通用 HTTP POST JSON 通道（trader 可接 Discord/Telegram via IFTTT/Zapier/n8n · 或自架 endpoint）
//
// 设计：
// - actor 隔离（与 FileChannel 同模式）
// - POST application/json · JSON schema 通用稳定
// - 注入 HTTPClient 协议（生产 URLSession · 测试可 mock）
// - 失败静默：网络错误 / 非 2xx 都不抛 · 不阻塞 evaluator（与 FileChannel 同语义）
// - timeout 5s 防慢端点拖累 evaluator

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP 客户端抽象 · 生产用 URLSession · 测试可注入 mock 拦截 request
public protocol WebhookHTTPClient: Sendable {
    /// 发送请求 · 不抛错（实现内部捕获异常返回 nil）· 仅用于通知"是否成功"
    /// 返回 (statusCode, body) · nil 表示传输层失败
    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async -> (statusCode: Int, body: Data)?
}

/// 默认 URLSession 实现 · 5s timeout · 失败返回 nil
public struct URLSessionWebhookClient: WebhookHTTPClient {
    public init() {}

    public func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async -> (statusCode: Int, body: Data)? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            return (http.statusCode, data)
        } catch {
            return nil
        }
    }
}

public actor WebhookChannel: NotificationChannel {

    public nonisolated let kind: NotificationChannelKind = .webhook

    private let url: URL
    private let headers: [String: String]
    private let client: WebhookHTTPClient
    private let timeout: TimeInterval
    private let timestampFormatter: @Sendable (Date) -> String

    /// 最近一次 send 结果（测试 / 内省用）· nil 未尝试 / true 成功(2xx) / false 失败
    private(set) public var lastDeliverySuccess: Bool?

    /// - Parameters:
    ///   - url: webhook endpoint
    ///   - headers: 额外 HTTP headers（如 Authorization · Discord 不需要）
    ///   - client: 注入便于测试 · 默认 URLSession
    ///   - timeout: 请求超时（秒 · 默认 5）
    ///   - timestampFormatter: 注入便于测试 · 默认 ISO8601
    public init(
        url: URL,
        headers: [String: String] = [:],
        client: WebhookHTTPClient = URLSessionWebhookClient(),
        timeout: TimeInterval = 5.0,
        timestampFormatter: @escaping @Sendable (Date) -> String = WebhookChannel.defaultTimestamp
    ) {
        self.url = url
        self.headers = headers
        self.client = client
        self.timeout = timeout
        self.timestampFormatter = timestampFormatter
    }

    public func send(_ event: NotificationEvent) async {
        let payload: [String: Any] = [
            "alert_id": event.alertID.uuidString,
            "alert_name": event.alertName,
            "instrument_id": event.instrumentID,
            "trigger_price": NSDecimalNumber(decimal: event.triggerPrice).stringValue,
            "triggered_at": timestampFormatter(event.triggeredAt),
            "message": event.message
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            lastDeliverySuccess = false
            return
        }
        let result = await client.post(url: url, headers: headers, body: body, timeout: timeout)
        lastDeliverySuccess = result.map { (200..<300).contains($0.statusCode) } ?? false
    }

    public nonisolated var endpoint: URL { url }

    /// ISO8601 默认时间格式（webhook receiver 容易解析）
    public static func defaultTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
