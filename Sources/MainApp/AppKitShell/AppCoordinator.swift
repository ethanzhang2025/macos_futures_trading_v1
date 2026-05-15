// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
//
// 顶层协调器 · 持有 AppState + WindowManager 唯一实例
// 通过 FuturesTerminalApp @StateObject 持有 · 注入到所有 V1 主窗 WindowGroup
//
// 参考 doc: window-architecture-refactor.md 章节 138-147（AppCoordinator 概念）
//
// Step 1 · 仅最小骨架 · AppState 暂占位（Step 3a 才正式从 ShellViewModel 抽 9 字段）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 重构顶层协调器 · 唯一持有 AppState / WindowManager
@MainActor
final class AppCoordinator: ObservableObject {
    let appState: AppState
    let windowManager: WindowManager

    init() {
        let state = AppState()
        self.appState = state
        self.windowManager = WindowManager(appState: state)
    }
}

/// V1 重构业务状态容器 · Step 3a 拆分目标
///
/// 当前仅占位 · Step 3a 从 ShellViewModel 717 行抽以下 9 字段：
///   primaryTab / workspaces / activeWorkspaceID / maximizedPaneID
///   groupBindings / userPresets / recentPaletteCommands / chartTheme / selectedSymbol
/// 拆分映射详见 doc A4 章节
@MainActor
final class AppState: ObservableObject {
    /// Step 1 占位字段 · Step 3a 整体替换
    @Published var placeholder: Int = 0
}

#endif
