// AlertCore · v17.84 · InAppOverlayChannel
// App 内浮层通道（ShellWindow .overlay banner · 5s 自动消失 · 点击切预警 tab）
//
// 设计：
// - actor 隔离（与 SystemNoticeChannel / SoundChannel / WebhookChannel 同模式）
// - send 时 NotificationCenter.default.post 通知 · UI 层订阅显示
// - 不直接持有 UI · 解耦 AlertCore 与 SwiftUI（AlertCore 是 Linux 可跑模块）
// - object 直接传 NotificationEvent · 订阅者解包显示
//
// 命名空间：Notification.Name.alertInAppOverlay = "AlertCore.inAppOverlay"

import Foundation

public actor InAppOverlayChannel: NotificationChannel {

    public nonisolated let kind: NotificationChannelKind = .inApp

    private let notificationName: Notification.Name
    private let center: NotificationCenter

    /// - Parameters:
    ///   - center: 注入便于测试（默认 default）
    ///   - notificationName: post 用通知名（默认 alertInAppOverlay）
    public init(
        center: NotificationCenter = .default,
        notificationName: Notification.Name = .alertInAppOverlay
    ) {
        self.center = center
        self.notificationName = notificationName
    }

    public func send(_ event: NotificationEvent) async {
        await MainActor.run {
            center.post(name: notificationName, object: event)
        }
    }
}

extension Notification.Name {
    /// AlertCore InAppOverlay 触发通知 · object = NotificationEvent
    public static let alertInAppOverlay = Notification.Name("AlertCore.inAppOverlay")
}
