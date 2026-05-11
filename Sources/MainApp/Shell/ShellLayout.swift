// MainApp · Shell · v17.0 PoC Step 1
// Shell 布局状态（sidebar/inspector/bottom 折叠 + 尺寸常量）
// v16.155 守护：仅 macOS 编译（依赖 CGFloat from CoreGraphics）

#if canImport(SwiftUI) && os(macOS)
import Foundation
import CoreGraphics

public struct ShellLayout: Codable, Sendable, Equatable {
    public var sidebarCollapsed: Bool   // 左 sidebar 折叠到 60pt 图标条
    public var inspectorVisible: Bool   // 右辅助可见
    public var bottomBarCollapsed: Bool // 底部交易区折叠到 24pt tab bar

    public init(sidebarCollapsed: Bool = false,
                inspectorVisible: Bool = true,
                bottomBarCollapsed: Bool = false) {
        self.sidebarCollapsed = sidebarCollapsed
        self.inspectorVisible = inspectorVisible
        self.bottomBarCollapsed = bottomBarCollapsed
    }
}

/// Shell 视觉尺寸常量（设计文档 § 15 拍板项 A-F）
public enum ShellMetrics {
    public static let sidebarWidth: CGFloat = 240        // A · 推荐 240pt
    public static let sidebarCollapsedWidth: CGFloat = 60
    public static let inspectorWidth: CGFloat = 280
    public static let topBarHeight: CGFloat = 32
    public static let workspaceTabBarHeight: CGFloat = 28
    public static let bottomBarHeight: CGFloat = 120     // D · 推荐 120pt
    public static let bottomBarCollapsedHeight: CGFloat = 24
}

#endif
