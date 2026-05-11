// MainApp · Shell · v17.0 PoC Step 2
// 主 Shell 窗口入口
// Step 2 加 PrimaryTab + WorkspaceTab 切换 ✅
// Step 3 加 PaneContainer + 嵌入 ChartScene
// Step 6 加 ShellSidebar / Step 7 加 BottomTradingBar / Step 8 加快捷键

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

public struct ShellWindow: View {

    @StateObject private var shellVM = ShellViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // 左 Sidebar（Step 6 ✅）
            ShellSidebar()
                .frame(minWidth: ShellMetrics.sidebarWidth,
                       idealWidth: ShellMetrics.sidebarWidth)
        } detail: {
            // 主区
            VStack(spacing: 0) {
                PrimaryTabBar()
                WorkspaceTabBar()
                Divider()
                paneContainerPlaceholder
                Divider()
                BottomTradingBar()
                Divider()
                ShellStatusBar()
            }
            .frame(minWidth: 1000, minHeight: 700)
            .background(ShellKeyboardShortcuts())
        }
        .navigationTitle("中国期货 Mac 工作台 · v17.0 PoC")
        .environmentObject(shellVM)
        .sheet(isPresented: $shellVM.showCommandPalette) {
            ShellCommandPalette(isPresented: $shellVM.showCommandPalette)
                .environmentObject(shellVM)
        }
    }

    // MARK: - Pane 容器（Step 3 ✅ · ChartScene 真实嵌入 · Step 5 全 18 view 接入）

    @ViewBuilder
    private var paneContainerPlaceholder: some View {
        if let ws = shellVM.activeWorkspace {
            PaneContainer(workspace: ws)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Text("无 active workspace · 点 + 新建").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

#endif
