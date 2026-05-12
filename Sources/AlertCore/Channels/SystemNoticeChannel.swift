// AlertCore · v17.82 · SystemNoticeChannel
// macOS 通知中心通道（UserNotifications · 10.14+）
//
// 设计：
// - actor 隔离（与 FileChannel / WebhookChannel 同模式）
// - 启动时 requestAuthorization · 失败 silent（仅 console log）· 不阻塞 evaluator
// - 用户拒绝通知权限 → send 静默 no-op
// - notification 标题：alert.name · 副标题：instrumentID @ triggerPrice · 正文：message
// - identifier 用 alertID · 同一 alert 重复触发覆盖前一个（避免通知中心堆积）
//
// Linux / iOS Simulator 不可用 · 编译期 #if 隔离

import Foundation
#if canImport(UserNotifications) && os(macOS)
import UserNotifications

public actor SystemNoticeChannel: NotificationChannel {

    public nonisolated let kind: NotificationChannelKind = .systemNotice

    /// authorization 状态（首次 send 前 request · 失败缓存）
    private var authorizationGranted: Bool?
    private let logger: @Sendable (String) -> Void

    public init(logger: @escaping @Sendable (String) -> Void = { _ in }) {
        self.logger = logger
    }

    public func send(_ event: NotificationEvent) async {
        if authorizationGranted == nil {
            await requestAuthorizationIfNeeded()
        }
        guard authorizationGranted == true else {
            logger("[SystemNotice] 未授权 · 跳过 \(event.alertName)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = event.alertName
        content.subtitle = "\(event.instrumentID) @ \(NSDecimalNumber(decimal: event.triggerPrice).stringValue)"
        content.body = event.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.alertID.uuidString,
            content: content,
            trigger: nil  // 立即触发
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger("[SystemNotice] add error: \(error.localizedDescription)")
        }
    }

    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationGranted = granted
            logger("[SystemNotice] 权限 \(granted ? "已授权" : "被拒绝")")
        } catch {
            authorizationGranted = false
            logger("[SystemNotice] 请求权限失败: \(error.localizedDescription)")
        }
    }
}

#endif
