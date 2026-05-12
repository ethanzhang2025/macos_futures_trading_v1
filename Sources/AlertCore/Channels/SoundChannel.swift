// AlertCore · v17.82 · SoundChannel
// macOS 系统音效通道（NSSound）
//
// 设计：
// - actor 隔离（与 FileChannel / WebhookChannel 同模式）
// - 默认 "Funk"（macOS 内置 short attention sound）· trader 可改任意 NSSound 名
// - sound 找不到 → silent no-op（不抛错 · logger 提示）
// - 多次触发不抢占播放（NSSound.play 自动 mix）
//
// Linux 不可用 · 编译期 #if 隔离

import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit

public actor SoundChannel: NotificationChannel {

    public nonisolated let kind: NotificationChannelKind = .sound

    /// v17.86 · macOS 内置 14 sound（trader 可在 AlertSoundPickerSheet 选）
    public static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    /// v17.86 · UserDefaults 持久化 key（trader 设置后跨 App 重启保留）
    public static let userDefaultsKey: String = "alertCenter.v1.soundName"

    private let soundName: String
    private let logger: @Sendable (String) -> Void

    /// - Parameters:
    ///   - soundName: macOS 内置 sound 名（默认 nil = 读 UserDefaults · 兜底 Funk）
    public init(
        soundName: String? = nil,
        logger: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        let resolved = soundName
            ?? UserDefaults.standard.string(forKey: SoundChannel.userDefaultsKey)
            ?? "Funk"
        self.soundName = resolved
        self.logger = logger
    }

    public func send(_ event: NotificationEvent) async {
        guard let sound = NSSound(named: soundName) else {
            logger("[Sound] 未找到 '\(soundName)' · 跳过 \(event.alertName)")
            return
        }
        // NSSound.play 在 MainActor 之外 OK · 但 AppKit 推荐主线程调用
        await MainActor.run {
            sound.play()
        }
    }
}

#endif
