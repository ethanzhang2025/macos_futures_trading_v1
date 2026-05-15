// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
//
// 主窗 NSSplitViewController · 3 列横向 split（Sidebar / PaneContainer / Monitor）
// doc 章节 153-163 + C3 数值约束（Sidebar min 200/max 360/pref 240/canCollapse）
//
// Step 1 · 3 个 split item 全部用 placeholder NSHostingController 验证桥接稳定
// Step 2 · 替换为真 SwiftUI 子树（ShellSidebar / PaneContainer / Watchlist+Sector+Position）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗 NSSplitViewController · 3 列布局
final class MainSplitViewController: NSSplitViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // 左 · Sidebar（C3 · min 200 / max 360 / pref 240）
        // Step 1 canCollapse=false · 拖到底是 200pt 不会折叠消失
        // Step 2 同步加 NSToolbar trackingSeparator + 菜单 View → Show Sidebar + ⌘⌃[ 后再 enable canCollapse
        let sidebarItem = NSSplitViewItem(
            viewController: Self.placeholderHC(label: "Sidebar", color: .systemBlue)
        )
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.preferredThicknessFraction = 240.0 / 1600.0
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer（A3=C · 看盘 tab 下 chart Pane 1-N 切分 · PaneKind 限定 .chart）
        let centerItem = NSSplitViewItem(
            viewController: Self.placeholderHC(
                label: "PaneContainer\n（中央 · 看盘 tab chart Pane 1-N 切分）",
                color: .systemGray
            )
        )
        centerItem.minimumThickness = 400
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        // 右 · Monitor 区（A2=C · Watchlist / Sector / Position · 可 detach 为 NSPanel）
        // Step 1 canCollapse=false · Step 4 monitor detach 接入时再 enable + 加 toolbar/菜单恢复入口
        let monitorItem = NSSplitViewItem(
            viewController: Self.placeholderHC(
                label: "Monitor\n（Watchlist / Sector / Position）",
                color: .systemGreen
            )
        )
        monitorItem.minimumThickness = 240
        monitorItem.maximumThickness = 480
        monitorItem.canCollapse = false
        addSplitViewItem(monitorItem)
    }

    /// Step 1 占位 NSHostingController · Step 2 替换为真 SwiftUI 视图
    private static func placeholderHC(label: String, color: NSColor) -> NSViewController {
        NSHostingController(rootView: PlaceholderPaneView(label: label, color: Color(nsColor: color)))
    }
}

/// Step 1 占位视图 · 让 3 个 split item 可视化 · Step 2 移除
private struct PlaceholderPaneView: View {
    let label: String
    let color: Color

    var body: some View {
        ZStack {
            color.opacity(0.15)
            VStack(spacing: 8) {
                Text("🚧 V1 · Step 1 占位")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(color)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
