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

        // 中 · PaneContainer（A3=C · v17.227 · 嵌套 NSStackView 支持 1/2/4/6/9 grid）
        // PaneContainerController 监听 activeWorkspace.paneLayout 变化自动 rebuild
        let centerVC = PaneContainerController(env: env)
        centerVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        // 右 · Monitor 区（A2=C Full v2 · v17.241 · 嵌套 NSSplitViewController 垂直堆叠 3 段）
        // 上：自选合约 / 中：板块联动 / 下：多空持仓 · 各自可折叠
        let monitorStackVC = MonitorStackController(env: env)
        monitorStackVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let monitorItem = NSSplitViewItem(viewController: monitorStackVC)
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

#endif
