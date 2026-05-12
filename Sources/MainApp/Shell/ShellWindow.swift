// MainApp · Shell · v17.0 PoC Step 2
// 主 Shell 窗口入口
// Step 2 加 PrimaryTab + WorkspaceTab 切换 ✅
// Step 3 加 PaneContainer + 嵌入 ChartScene
// Step 6 加 ShellSidebar / Step 7 加 BottomTradingBar / Step 8 加快捷键

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

public struct ShellWindow: View {

    /// v17.59 · ShellViewModel 提到 App 级 @StateObject · 此处 EnvironmentObject 接收
    /// 让 detached Pane 多屏共享同一 instance（跨窗口 group 联动）
    @EnvironmentObject private var shellVM: ShellViewModel
    /// v17.66 · 启动恢复 detached NSWindow（每个 paneID openWindow 一次）
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // 左 Sidebar（Step 6 ✅）
            ShellSidebar()
                .frame(minWidth: ShellMetrics.sidebarWidth,
                       idealWidth: ShellMetrics.sidebarWidth)
        } detail: {
            // v17.61 · 主区 + 右辅助 Inspector（HSplitView · 可折叠 ⌘⌥I）
            HSplitView {
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
                .frame(minWidth: 800, minHeight: 700)
                if shellVM.layout.inspectorVisible {
                    ShellInspector()
                }
            }
            .background(ShellKeyboardShortcuts())
        }
        .navigationTitle("中国期货 Mac 工作台 · v17.0 PoC")
        .sheet(isPresented: $shellVM.showCommandPalette) {
            ShellCommandPalette(isPresented: $shellVM.showCommandPalette)
                .environmentObject(shellVM)
        }
        // v17.57 · F10 合约资料 sheet
        .sheet(isPresented: $shellVM.showInstrumentInfoSheet) {
            ShellInstrumentInfoSheet(isPresented: $shellVM.showInstrumentInfoSheet)
                .environmentObject(shellVM)
        }
        // v17.57 · 空格快捷下单浮层（Stage A 占位）
        .sheet(isPresented: $shellVM.showQuickOrderSheet) {
            ShellQuickOrderSheet(isPresented: $shellVM.showQuickOrderSheet)
                .environmentObject(shellVM)
        }
        // v17.57 · F 键 toast overlay（瞬态 1.5s）
        .overlay(alignment: .top) {
            if let toast = shellVM.fKeyToast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78))
                    .cornerRadius(10)
                    .padding(.top, 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(toast)  // 同内容刷新动画
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shellVM.fKeyToast)
        .followingChartTheme()  // v17.12 A2.1 · Shell 跟随主图主题（dark/light · UserDefaults chartTheme.v1）
        // v17.66 · App 进程启动后第一次 Shell render · 自动 openWindow 恢复重启前 detached 的 Pane
        // 用 hasRestoredDetachedWindows 防多 ShellWindow 实例重复触发
        .onAppear {
            guard !shellVM.hasRestoredDetachedWindows else { return }
            shellVM.hasRestoredDetachedWindows = true
            for id in shellVM.validDetachedPaneIDsForRestore() {
                openWindow(id: "detachedPane", value: id.uuidString)
            }
        }
        // v17.66 · 监听 App 退出 · 设 flag 让 detached window 的 .onDisappear 跳过清空 list（保留下次恢复）
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            shellVM.isApplicationTerminating = true
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
