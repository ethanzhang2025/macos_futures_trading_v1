// MainApp · v15.17 通知通道 macOS 实现
//
// 设计要点：
// - WP-52 · NotificationChannel 协议在 AlertCore（Linux 兼容 · 无 AppKit/UN）
// - macOS 真实通道实现放 MainApp（#if os(macOS) guard）
// - SystemNoticeChannel：UNUserNotificationCenter（macOS 11+ · 系统通知中心）
// - SoundChannel：NSSound 系统声音播放（.glass / .ping / .submarine 等）
// - InAppOverlayChannel：通过 NotificationCenter post · ChartScene overlay 监听显示 toast（v15.17 完成）
//
// 使用：FuturesTerminalApp 启动时 dispatcher.register(SystemNoticeChannel())
// + dispatcher.register(SoundChannel()) · 用户预警触发 → AlertEvaluator dispatch → 发系统通知 + 播声音

#if canImport(AppKit) && os(macOS)

import Foundation
import AppKit
import UserNotifications
import AlertCore

/// macOS 系统通知通道 · 用 UserNotifications 框架（macOS 11+）
/// 首次发送会弹权限请求 · 用户拒绝后通知静默不显（NSAlert 提示设置）
/// v15.17 hotfix：从 NSLock 改 actor · Swift 6 async context NSLock unavailable
public actor SystemNoticeChannel: NotificationChannel {
    public nonisolated let kind: NotificationChannelKind = .systemNotice

    /// 是否已请求过权限（避免每次 send 都请求 · actor 自动序列化）
    private var permissionRequested: Bool = false

    public init() {}

    public func send(_ event: NotificationEvent) async {
        await ensurePermission()
        let content = UNMutableNotificationContent()
        content.title = "预警触发：\(event.alertName)"
        content.subtitle = "\(event.instrumentID) @ \(event.triggerPrice)"
        content.body = event.message
        content.sound = nil  // 声音由 SoundChannel 单独控制 · 避免重复
        let request = UNNotificationRequest(
            identifier: event.alertID.uuidString + "-" + UUID().uuidString,
            content: content,
            trigger: nil  // 立即触发
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // 权限被拒 / 系统级错误 · 静默 fallback（不阻塞预警流程）
            print("⚠️ SystemNoticeChannel.send failed: \(error)")
        }
    }

    private func ensurePermission() async {
        guard !permissionRequested else { return }
        permissionRequested = true
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge])
        } catch {
            print("⚠️ SystemNoticeChannel permission request failed: \(error)")
        }
    }
}

/// macOS App 内浮窗通道 · 通过 NotificationCenter 转发 · ChartScene overlay 接收显示 toast
/// 设计：channel 自身不持有 SwiftUI 状态 · 解耦 actor → @MainActor view
public final class InAppOverlayChannel: NotificationChannel, @unchecked Sendable {
    public let kind: NotificationChannelKind = .inApp

    /// NotificationCenter 名（ChartScene .onReceive 监听）
    public static let alertNotification = Notification.Name("FuturesTerminal.alertTriggeredInApp")

    public init() {}

    public func send(_ event: NotificationEvent) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Self.alertNotification,
                object: nil,
                userInfo: [
                    "alertID": event.alertID,
                    "alertName": event.alertName,
                    "instrumentID": event.instrumentID,
                    "triggerPrice": event.triggerPrice,
                    "message": event.message
                ]
            )
        }
    }
}

/// macOS 系统声音通道 · NSSound 播放系统内置声音
/// 默认 "Glass"（清脆 · 不易混淆）· 用户后续可在设置中改
public final class SoundChannel: NotificationChannel, @unchecked Sendable {
    public let kind: NotificationChannelKind = .sound

    /// 系统声音名（参考 /System/Library/Sounds/）
    /// macOS 内置：Basso / Blow / Bottle / Frog / Funk / Glass / Hero / Morse / Ping / Pop / Purr / Sosumi / Submarine / Tink
    private let soundName: String

    public init(soundName: String = "Glass") {
        self.soundName = soundName
    }

    public func send(_ event: NotificationEvent) async {
        // NSSound 在 MainActor 上播放更稳 · 防潜在 thread issue
        let name = soundName
        await MainActor.run {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.play()
            } else {
                print("⚠️ SoundChannel: 系统声音 '\(name)' 不存在")
            }
        }
    }
}

#endif
