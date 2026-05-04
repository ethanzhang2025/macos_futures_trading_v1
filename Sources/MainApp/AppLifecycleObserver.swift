// WP-133a · session_start / session_end 埋点 wire（v15.18）
//
// 设计取舍：
// - StageA-补遗 G2：session_start = "进入前台，距上次 session_end > 3 分钟"
//   严谨语义：跨次冷启动也按 3 分钟规则判定 · 防同日多次开计为多次（与 D1 §4 WAPU 严格定义一致）
// - 持有 NSApplication 通知 · 生命周期 = App 全程 · 不需 deinit 清理（避 Swift 6 @MainActor deinit 限制）
// - lastSessionEndMs 持久化到 UserDefaults · 跨启动有效（用户关 App 再开 5 分钟内仍按"同 session"概念不重发）
// - record / setSession 用 fire-and-forget Task · 失败静默（埋点不阻塞 UI）
//
// 与 v15.17 InAppOverlayChannel / SystemNoticeChannel 同套 macOS guard 模式

#if canImport(SwiftUI) && os(macOS)

import Foundation
import AppKit
import Shared

@MainActor
final class AppLifecycleObserver {

    // MARK: - 依赖

    private let analytics: AnalyticsService
    private let userID: String

    // MARK: - 状态

    private var currentSessionID: String?
    private var currentSessionStartMs: Int64?

    // MARK: - 常量

    /// UserDefaults key（跨启动持久 lastSessionEndMs · 与其它 v1 key 风格一致）
    /// 3 分钟阈值 / 决策逻辑见 Shared.SessionGapPolicy（纯函数 · 可单测）
    private static let lastSessionEndKey = "com.futures-terminal.analytics.lastSessionEndMs"

    // MARK: - 初始化（启动即开始监听 · 生命周期与 App 同步 · 无 deinit）

    init(analytics: AnalyticsService, userID: String) {
        self.analytics = analytics
        self.userID = userID

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
    }

    // MARK: - 通知回调

    /// 进入前台 · 距上次 end > 3 分钟则发 session_start（新 UUID）· 否则复用旧 session（不发新事件）
    @objc private func handleBecomeActive() {
        // 已有活跃 session 不重启（避免短切焦点造成误发）
        if currentSessionID != nil { return }

        let nowMs = AnalyticsEvent.nowMs()
        let lastEndMs = Int64(UserDefaults.standard.double(forKey: Self.lastSessionEndKey))

        // 3 分钟规则集中在 SessionGapPolicy（Shared 纯函数 · 单测覆盖）
        guard SessionGapPolicy.shouldStartNewSession(nowMs: nowMs, lastEndMs: lastEndMs) else { return }

        let newID = UUID().uuidString
        currentSessionID = newID
        currentSessionStartMs = nowMs

        let analytics = self.analytics
        let userID = self.userID
        Task {
            await analytics.setSession(newID)
            _ = try? await analytics.record(
                .sessionStart,
                userID: userID,
                properties: ["session_id": newID]
            )
        }
    }

    /// 进入后台 · 发 session_end（含 duration_sec）+ 持久 lastSessionEndMs · 清当前 session
    @objc private func handleResignActive() {
        guard let sessionID = currentSessionID, let startMs = currentSessionStartMs else { return }

        let nowMs = AnalyticsEvent.nowMs()
        let durationSec = max(0, (nowMs - startMs) / 1000)

        currentSessionID = nil
        currentSessionStartMs = nil
        UserDefaults.standard.set(Double(nowMs), forKey: Self.lastSessionEndKey)

        let analytics = self.analytics
        let userID = self.userID
        Task {
            _ = try? await analytics.record(
                .sessionEnd,
                userID: userID,
                properties: [
                    "session_id": sessionID,
                    "duration_sec": "\(durationSec)"
                ]
            )
            await analytics.setSession(nil)
        }
    }
}

#endif
