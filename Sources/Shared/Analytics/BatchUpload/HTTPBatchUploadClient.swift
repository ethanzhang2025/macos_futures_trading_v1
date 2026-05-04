// WP-133b · HTTP 上报客户端真实现（v15.18 · 后端就绪后切此实现）
//
// 设计取舍：
// - URLSession + JSON POST · 协议级实现 · 不依赖第三方 HTTP 库
// - endpoint 注入 · 后端就绪后传真实 URL · stub 期暂用 about:blank（不会真发请求 · 保留兼容性）
// - 失败映射：URLError → networkFailed / 4xx-5xx → serverRejected / 编码失败 → payloadInvalid
// - timeout 30s · WP-133b spec "每 5 分钟批量"短周期不挂连接太久
// - 不重试：driver 层负责（失败 = 不 markUploaded · 下轮 queryPending 自然重试）

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP 上报请求体（与后端 PostgreSQL events 表 schema 对齐）
public struct BatchUploadPayload: Sendable, Codable, Equatable {
    public let userID: String
    public let deviceID: String
    public let appVersion: String
    public let events: [Item]

    public struct Item: Sendable, Codable, Equatable {
        public let sessionID: String?
        public let eventName: String
        public let eventTimestampMs: Int64
        public let properties: [String: String]
    }

    public init(events: [AnalyticsEvent]) {
        // 取首条 user/device/version 作为公共字段（驱动调用前已确保单批同源）
        let first = events.first
        self.userID = first?.userID ?? ""
        self.deviceID = first?.deviceID ?? ""
        self.appVersion = first?.appVersion ?? ""
        self.events = events.map {
            Item(
                sessionID: $0.sessionID,
                eventName: $0.eventName.rawValue,
                eventTimestampMs: $0.eventTimestampMs,
                properties: $0.properties
            )
        }
    }
}

public actor HTTPBatchUploadClient: BatchUploadClient {

    private let endpoint: URL
    private let timeoutSec: TimeInterval
    private let session: URLSession

    public init(endpoint: URL, timeoutSec: TimeInterval = 30, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.timeoutSec = timeoutSec
        self.session = session
    }

    public func upload(_ events: [AnalyticsEvent]) async throws {
        guard !events.isEmpty else { return }

        let payload = BatchUploadPayload(events: events)
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw BatchUploadError.payloadInvalid("JSON 编码失败: \(error)")
        }

        var req = URLRequest(url: endpoint, timeoutInterval: timeoutSec)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw BatchUploadError.networkFailed("非 HTTP 响应")
            }
            if (200..<300).contains(http.statusCode) { return }
            let msg = String(data: data, encoding: .utf8) ?? "(无消息体)"
            throw BatchUploadError.serverRejected(statusCode: http.statusCode, message: msg)
        } catch let err as BatchUploadError {
            throw err
        } catch let url as URLError {
            throw BatchUploadError.networkFailed("URLError code=\(url.code.rawValue): \(url.localizedDescription)")
        } catch {
            throw BatchUploadError.networkFailed("\(error)")
        }
    }
}
