// MainApp · Shell · v17.0 PoC Step 1
// 主 Shell 窗口入口（v17.0 Step 1 占位 · 验证框架编译通过）
// Step 2 加 PrimaryTab + WorkspaceTab 切换
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
            // 主区（Step 2/3 实装 · Step 1 占位）
            mainPlaceholder
        }
        .navigationTitle("中国期货 Mac 工作台 · v17.0 PoC")
        .environmentObject(shellVM)
    }

    // MARK: - Step 1 占位

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
            Text("v17.0 PoC Step 1 · Shell 框架")
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

    private var mainPlaceholder: some View {
        VStack(spacing: 16) {
            // 顶部模块切换占位（Step 2 实装 PrimaryTab + WorkspaceTab）
            HStack(spacing: 12) {
                ForEach(PrimaryTab.allCases) { tab in
                    Button {
                        shellVM.primaryTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.emoji)
                            Text(tab.displayName)
                                .font(.system(size: 13, weight: shellVM.primaryTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(shellVM.primaryTab == tab
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12)

            Divider()

            VStack(spacing: 12) {
                Text("🚧 v17.0 PoC Step 1")
                    .font(.title.bold())
                Text("Shell 框架已就绪")
                    .font(.title3).foregroundColor(.secondary)
                Divider().frame(width: 200)
                Text("当前模块：\(shellVM.primaryTab.emoji) \(shellVM.primaryTab.displayName)")
                    .font(.system(size: 14, design: .monospaced))
                if let ws = shellVM.activeWorkspace {
                    Text("当前 Workspace：\(ws.name)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Text("Pane 配置：\(ws.paneLayout.emoji) \(ws.paneLayout.displayName) · \(ws.panes.count) Pane")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Divider().frame(width: 200)
                Text("下一步 Step 2：PrimaryTab + WorkspaceTab 切换")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部交易区占位（Step 7 实装）
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
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

#endif
