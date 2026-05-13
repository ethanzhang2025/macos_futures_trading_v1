// MainApp · Shell · v17.0 PoC Step 1
// Pane 协议（v17.0 Step 1 占位 · Step 3 完整实现）
// 所有可嵌入 Shell 的 view 实现 · 用于 group binding / 持久化 / detach
//
// Step 1 不实现协议方法 · 只定义接口 + 环境 key
// Step 3 让 ChartScene / ReviewWindow 等 conform

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// 标记 view 当前是否嵌入 Shell（vs 独立 WindowGroup）
/// 嵌入模式下 view 内部隐藏 toolbar/状态栏（由 Shell 统一显示）
public struct IsHostedInShellKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var isHostedInShell: Bool {
        get { self[IsHostedInShellKey.self] }
        set { self[IsHostedInShellKey.self] = newValue }
    }
}

// MARK: - v17.58 · 跨周期十字光标同步 Environment 注入（v17.0 P1.2）
//
// PaneHost 注入 paneID + crosshairReporter + externalCrosshair
// ChartScene 嵌入时通过 Environment 调用 reporter（不直接依赖 ShellViewModel）

public struct ShellHostedPaneIDKey: EnvironmentKey {
    public static let defaultValue: UUID? = nil
}

public struct ShellCrosshairReporterKey: EnvironmentKey {
    // v17.190 · Mac 6.3 严格 · closure 须 @Sendable 才能作 module static let
    public static let defaultValue: (@Sendable (UUID, Date?) -> Void)? = nil
}

public struct ShellExternalCrosshairKey: EnvironmentKey {
    public static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// 当前 Pane 的 UUID（仅嵌入 Shell 时非 nil）
    public var shellHostedPaneID: UUID? {
        get { self[ShellHostedPaneIDKey.self] }
        set { self[ShellHostedPaneIDKey.self] = newValue }
    }
    /// hover 时 publish 给 Shell 的 closure（paneID + Date · Date=nil 表示 hover 离开）
    /// v17.190 · 类型须与 ShellCrosshairReporterKey.defaultValue 一致 · 加 @Sendable
    public var shellCrosshairReporter: (@Sendable (UUID, Date?) -> Void)? {
        get { self[ShellCrosshairReporterKey.self] }
        set { self[ShellCrosshairReporterKey.self] = newValue }
    }
    /// 同 group 兄弟广播的 crosshair 时间（ChartScene v18+ 据此画十字）
    public var shellExternalCrosshair: Date? {
        get { self[ShellExternalCrosshairKey.self] }
        set { self[ShellExternalCrosshairKey.self] = newValue }
    }
}

#endif
