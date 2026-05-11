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
            // 左 Sidebar（Step 6 实装 · Step 1 占位）
            sidebarPlaceholder
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
                bottomTradingBarPlaceholder
            }
            .frame(minWidth: 1000, minHeight: 700)
        }
        .navigationTitle("中国期货 Mac 工作台 · v17.0 PoC")
        .environmentObject(shellVM)
    }

    // MARK: - Sidebar 占位（Step 6 实装）

    private var sidebarPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📂 Sidebar")
                .font(.title3.bold())
            Divider()
            Text("Step 6 实装：")
                .font(.caption).foregroundColor(.secondary)
            Text("· 自选 mini list\n· 板块树\n· 持仓速览\n· 异动 chip\n· 训练 streak 🔥")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Divider()
            Text("v17.0 PoC Step 2 · Tab 切换就绪")
                .font(.caption2).foregroundColor(.secondary)
            Text("workspaces: \(shellVM.workspaces.count)")
                .font(.caption2.monospaced()).foregroundColor(.accentColor)
            if let ws = shellVM.activeWorkspace {
                Text("active: \(ws.name)")
                    .font(.caption2.monospaced()).foregroundColor(.accentColor)
            }
        }
        .padding(12)
    }

    // MARK: - Pane 占位（Step 3 实装）

    private var paneContainerPlaceholder: some View {
        VStack(spacing: 16) {
            if let ws = shellVM.activeWorkspace {
                Text("🚧 Step 3 实装：PaneContainer 嵌入 28 view")
                    .font(.title3).foregroundColor(.secondary)
                Divider().frame(width: 240)
                VStack(spacing: 6) {
                    Text("当前 Workspace：\(ws.name)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Text("布局：\(ws.paneLayout.emoji) \(ws.paneLayout.displayName)")
                        .font(.system(size: 12, design: .monospaced))
                    Text("Panes：")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    ForEach(ws.panes) { pane in
                        HStack(spacing: 6) {
                            Text(pane.kind.emoji)
                            Text(pane.kind.displayName)
                                .font(.system(size: 11))
                            if let sym = pane.symbol {
                                Text("· \(sym)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if let period = pane.periodRaw {
                                Text("· \(period)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if let color = pane.groupColor {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            } else {
                Text("无 active workspace · 点 + 新建").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部交易区占位（Step 7 实装）

    private var bottomTradingBarPlaceholder: some View {
        HStack(spacing: 16) {
            Text("📊 持仓 0  ·  📋 委托 0  ·  ✓ 成交 0  ·  💰 资金 ¥100,000  ·  🎯 训练规则 0/0")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text("Step 7 实装")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .frame(height: ShellMetrics.bottomBarHeight)
    }
}

#endif
