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

#endif
