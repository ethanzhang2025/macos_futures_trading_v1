// WP-133a · session_start 3 分钟规则纯函数（v15.18）
//
// 设计取舍：
// - StageA-补遗 G2 / D1 §4 北极星 WAPU 严谨定义：session_start = "进入前台，距上次 session_end > 3 分钟"
// - 抽出为纯函数 · MainApp 的 AppLifecycleObserver 调用 · Shared 模块可单测（macOS only NSApp 通知不易测）
// - lastEndMs == 0 视为首启（无历史 session）· 必发新 session_start
// - nowMs - lastEndMs >= sessionGapMs 才发新 session（=即未达 3 分钟阈值仍属同 session 复用）

import Foundation

public enum SessionGapPolicy {

    /// 跨 session 间隔阈值（3 分钟 · 毫秒）· StageA-补遗 G2 严谨定义
    public static let sessionGapMs: Int64 = 3 * 60 * 1000

    /// 是否应触发新 session_start
    /// - Parameters:
    ///   - nowMs: 当前 didBecomeActive 时刻（毫秒）
    ///   - lastEndMs: 上次 session_end 时刻（毫秒 · 0 表示无历史 session 即首启）
    /// - Returns: true 表示发 session_start（新 UUID）· false 表示复用上次 session 不重发
    public static func shouldStartNewSession(nowMs: Int64, lastEndMs: Int64) -> Bool {
        if lastEndMs <= 0 { return true }                 // 首启 / lastEndMs 损坏 · 必发
        return (nowMs - lastEndMs) >= sessionGapMs        // ≥ 3 分钟才发
    }
}
