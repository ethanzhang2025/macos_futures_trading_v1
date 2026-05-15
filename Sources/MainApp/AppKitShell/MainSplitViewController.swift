// MainApp · AppKitShell · v17.223 · V1 重构 Step 2a
//
// 主窗 NSSplitViewController · 3 列横向 split（Sidebar / PaneContainer / Monitor）
// doc 章节 153-163
//
// v17.222 诊断证实：placeholder 能拖 · 真子组件不能拖 = ChartScene 的 minWidth/minHeight
// 撑大 NSHostingController.view 覆盖 NSSplitView divider hit test
//
// v17.223 修法：
//   - 加 isInV1MainWindow environment（injectAppKitShellEnv 默认注入 true）
//   - ChartScene + ChartContentView 内 minWidth/minHeight 受 isInV1MainWindow 控制（true 时 = 0）
//   - 恢复 3 个真子组件（ShellSidebar / ChartScene / WatchlistWindow）
//   - canCollapse=true 保持（v17.221 已翻 · macOS NSSplitView 标准 collapse 行为）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗 NSSplitViewController · 3 列布局
final class MainSplitViewController: NSSplitViewController {
    private let env: AppKitShellEnvironment

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported · V1 NSSplitViewController 仅程序化构造")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true

        // 左 · Sidebar · widthAnchor ≥ 200
        let sidebarVC = AppKitShellHC.wrap(ShellSidebar(), env: env)
        sidebarVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer（A3=C · 看盘 tab 下 chart Pane 1-N 切分 · Step 2 暂用单 ChartScene）
        let centerVC = AppKitShellHC.wrap(ChartScene(), env: env)
        centerVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        // 右 · Monitor 区（A2=C · Watchlist / Sector / Position · 可 detach 为 NSPanel）
        let monitorVC = AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        monitorVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let monitorItem = NSSplitViewItem(viewController: monitorVC)
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

#endif
