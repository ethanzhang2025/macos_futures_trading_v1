// WP-52 模块 3 · 通知统一层
// ChatGPT A08 禁做项："不要把通知发送逻辑散落在多个模块"
//   → 所有通知发送统一走 NotificationChannel 协议
//
// v1 数据模型层只提供：
// - 协议定义
// - LoggingNotificationChannel 默认实现（仅打印 log，便于测试）
// - NotificationDispatcher actor（多 channel 广播）
//
// 真实通知实现留给 UI 层：
// - InAppOverlayChannel（SwiftUI overlay，留 UI WP）
// - SystemNoticeChannel（UserNotifications，留 Mac 切机）
// - SoundChannel（NSSound，留 Mac 切机）

import Foundation

/// 通知发送事件 · 解耦 Alert 与通知通道
public struct NotificationEvent: Sendable, Equatable, Hashable {
    public let alertID: UUID
    public let alertName: String
    public let instrumentID: String
    public let triggerPrice: Decimal
    public let triggeredAt: Date
    public let message: String

    public init(
        alertID: UUID,
        alertName: String,
        instrumentID: String,
        triggerPrice: Decimal,
        triggeredAt: Date,
        message: String
    ) {
        self.alertID = alertID
        self.alertName = alertName
        self.instrumentID = instrumentID
        self.triggerPrice = triggerPrice
        self.triggeredAt = triggeredAt
        self.message = message
    }
}

/// 通知通道协议 · 单个通道（如 App 内浮窗 / 系统通知 / 声音）
/// 实现方需是 Sendable + 内部并发安全
public protocol NotificationChannel: Sendable {
    /// 通道标识（与 NotificationChannelKind 对齐）
    var kind: NotificationChannelKind { get }

    /// 发送通知（应快速返回，长耗时操作应异步执行）
    func send(_ event: NotificationEvent) async
}

/// 默认实现 · 仅向 stdout 打印 log
/// 用途：测试 / 早期开发 / Linux 上无真实通知能力
public struct LoggingNotificationChannel: NotificationChannel {
    public let kind: NotificationChannelKind

    /// 注入便于测试拦截；生产路径请显式注入真实 logger，不要依赖默认 print
    private let logger: @Sendable (String) -> Void

    public init(
        kind: NotificationChannelKind = .inApp,
        logger: @escaping @Sendable (String) -> Void = { print("[Alert][\($0.prefix(80))]") }
    ) {
        self.kind = kind
        self.logger = logger
    }

    public func send(_ event: NotificationEvent) async {
        logger("\(kind.rawValue) | \(event.alertName) | \(event.instrumentID) @ \(event.triggerPrice) | \(event.message)")
    }
}

/// 通知调度器 actor · 注册多个 channel + 按 Alert.channels 选择性广播
/// 这是"通知统一层"的核心：所有 emit 走这里，不散落
public actor NotificationDispatcher {

    private var channels: [NotificationChannelKind: NotificationChannel] = [:]

    public init(channels: [NotificationChannel] = []) {
        for channel in channels {
            self.channels[channel.kind] = channel
        }
    }

    /// 注册通道（同 kind 已存在则覆盖）
    public func register(_ channel: NotificationChannel) {
        channels[channel.kind] = channel
    }

    /// 移除通道
    public func unregister(_ kind: NotificationChannelKind) {
        channels.removeValue(forKey: kind)
    }

    /// 当前已注册的 kinds
    public func registeredKinds() -> Set<NotificationChannelKind> {
        Set(channels.keys)
    }

    /// 广播事件到指定 kinds（与 Alert.channels 对齐）
    /// 已注册但不在 kinds 集合内的 channel 不会被调用
    public func dispatch(_ event: NotificationEvent, to kinds: Set<NotificationChannelKind>) async {
        for kind in kinds {
            guard let channel = channels[kind] else { continue }
            await channel.send(event)
        }
    }
}
