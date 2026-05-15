// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
// v17.225 · Step 3a · AppState 9 字段 facade 化
//
// 顶层协调器 · 持有 AppState + WindowManager 唯一实例
// 通过 FuturesTerminalApp @StateObject 持有 · 注入到所有 V1 主窗 WindowGroup
//
// 参考 doc: window-architecture-refactor.md 章节 138-147（AppCoordinator 概念）+ A4 / E1
//
// E1 渐进迁移：AppState 不重复存储 · 包同一个 ShellViewModel ref 做 facade
// → 老调用继续 environmentObject(shellVM) · 新 V1 组件用 AppState · 二者读写同一数据源
// → Step 4-6 调用点逐步从 shellVM 迁到 appState · 最后删 ShellViewModel

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Combine

/// V1 重构顶层协调器 · 唯一持有 AppState / WindowManager
@MainActor
final class AppCoordinator: ObservableObject {
    let shellVM: ShellViewModel
    let appState: AppState
    let windowManager: WindowManager

    init(shellVM: ShellViewModel) {
        self.shellVM = shellVM
        let state = AppState(shellVM: shellVM)
        self.appState = state
        self.windowManager = WindowManager(appState: state)
    }
}

/// V1 重构业务状态容器 · Step 3a facade 模式
///
/// 9 字段映射（doc A4 章节）：
/// - 7 个 facade 字段（primaryTab / workspaces / activeWorkspaceID / maximizedPaneID /
///   groupBindings / userPresets / recentPaletteCommands）· 直接转发到 shellVM
/// - 2 个新字段（chartTheme / selectedSymbol）· AppState 独立存储 · 调用点 Step 3c/4 渐进迁
///
/// objectWillChange 通过 Combine 从 shellVM 转发 · V1 组件订阅 AppState 即可拿到全部数据变化
@MainActor
final class AppState: ObservableObject {
    private let shellVM: ShellViewModel
    private var cancellables = Set<AnyCancellable>()

    init(shellVM: ShellViewModel) {
        self.shellVM = shellVM
        shellVM.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Facade · 7 个现有 ShellViewModel 字段

    var primaryTab: PrimaryTab {
        get { shellVM.primaryTab }
        set { shellVM.primaryTab = newValue }
    }

    var workspaces: [Workspace] {
        get { shellVM.workspaces }
        set { shellVM.workspaces = newValue }
    }

    var activeWorkspaceID: UUID? {
        get { shellVM.activeWorkspaceID }
        set { shellVM.activeWorkspaceID = newValue }
    }

    var maximizedPaneID: UUID? {
        get { shellVM.maximizedPaneID }
        set { shellVM.maximizedPaneID = newValue }
    }

    var groupBindings: [GroupColor: SymbolBinding] {
        get { shellVM.groupBindings }
        set { shellVM.groupBindings = newValue }
    }

    var userPresets: [UserWorkspacePreset] {
        get { shellVM.userPresets }
        set { shellVM.userPresets = newValue }
    }

    var recentPaletteCommands: [String] {
        get { shellVM.recentPaletteCommands }
        set { shellVM.recentPaletteCommands = newValue }
    }

    var activeWorkspace: Workspace? { shellVM.activeWorkspace }

    // MARK: - 新字段 · Step 3a 占位 · Step 3c/4 迁调用点

    /// 全局图表主题 · 当前事实源仍在 ChartScene line 249 @State
    /// Step 3c 把 ChartScene chartTheme @State 提升到此处 · 多 chart 窗联动
    @Published var chartTheme: ChartTheme = .dark

    /// 当前选中合约 · 替代 watchlistInstrumentSelected Notification
    /// 当前 8+ onReceive 调用点未迁（HeatmapWindow / SpreadWindow / SectorWindow / 等）
    /// Step 4 渐进改 onChange · 双轨过渡期 Notification 同时存在
    @Published var selectedSymbol: String? = nil
}

#endif
