// MainApp · Shell · v17.0 PoC Step 2
// 主 Shell 窗口入口
// Step 2 加 PrimaryTab + WorkspaceTab 切换 ✅
// Step 3 加 PaneContainer + 嵌入 ChartScene
// Step 6 加 ShellSidebar / Step 7 加 BottomTradingBar / Step 8 加快捷键

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AlertCore

public struct ShellWindow: View {

    /// v17.59 · ShellViewModel 提到 App 级 @StateObject · 此处 EnvironmentObject 接收
    /// 让 detached Pane 多屏共享同一 instance（跨窗口 group 联动）
    @EnvironmentObject private var shellVM: ShellViewModel
    /// v17.66 · 启动恢复 detached NSWindow（每个 paneID openWindow 一次）
    @Environment(\.openWindow) private var openWindow

    /// v17.84 · 当前显示的预警 banner（5s 自动消失 · 点击 → 打开预警窗口）
    @State private var alertBanner: NotificationEvent?
    @State private var alertBannerDismissTask: Task<Void, Never>?
    /// v17.141 · 全工程快捷键速查 sheet 显隐（⌘⇧/ 触发 · 主菜单帮助项也调）
    @State private var showShortcutsSheet: Bool = false

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
        // v17.67 · Workspace 预设选择 sheet
        .sheet(isPresented: $shellVM.showPresetPickerSheet) {
            WorkspacePresetPickerSheet(isPresented: $shellVM.showPresetPickerSheet)
                .environmentObject(shellVM)
        }
        // v17.141 · 全工程快捷键速查 sheet · ⌘⇧/ 触发 + 主菜单"帮助" → "全局快捷键速查"
        .sheet(isPresented: $showShortcutsSheet) {
            GlobalShortcutsHelpSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGlobalShortcutsSheet)) { _ in
            showShortcutsSheet = true
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
        // v17.84 · 预警 InApp banner overlay（NotificationEvent 触发 · 5s 自动消失 · 点击切预警窗口）
        .overlay(alignment: .topTrailing) {
            if let banner = alertBanner {
                alertBannerView(banner)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: alertBanner?.alertID)
        .onReceive(NotificationCenter.default.publisher(for: .alertInAppOverlay)) { note in
            guard let event = note.object as? NotificationEvent else { return }
            alertBanner = event
            alertBannerDismissTask?.cancel()
            alertBannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { alertBanner = nil }
            }
        }
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

    // MARK: - v17.84 · 预警 InApp banner（顶部右侧 · 5s 消失 · 点击 → 预警窗口）

    @ViewBuilder
    private func alertBannerView(_ event: NotificationEvent) -> some View {
        Button {
            openWindow(id: "alert")
            NotificationCenter.default.post(name: .alertWindowFilterToInstrument, object: event.instrumentID)
            alertBannerDismissTask?.cancel()
            alertBanner = nil
        } label: {
            HStack(spacing: 10) {
                Text("🔔").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.alertName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(event.instrumentID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(3)
                    }
                    Text(event.message)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                    Text("@ \(NSDecimalNumber(decimal: event.triggerPrice).stringValue) · 点击打开预警窗口")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                Button {
                    alertBannerDismissTask?.cancel()
                    alertBanner = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 320, alignment: .leading)
            .background(LinearGradient(
                colors: [Color.red.opacity(0.92), Color.orange.opacity(0.92)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
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
