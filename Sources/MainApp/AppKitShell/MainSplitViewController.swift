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

        // v17.248 修 · widthAnchor.required 与 NSSplitView 自身 layout 系统冲突 · 导致 divider 拖不动
        // 改用 NSSplitViewItem.minimumThickness（NSSplitView 标准 API · 不走 Auto Layout）

        // 左 · Sidebar · 最小 200pt · 可折叠
        let sidebarVC = AppKitShellHC.wrap(ShellSidebar(), env: env)
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer · 最小 400pt · 不可折叠（PaneContainerController 监听 paneLayout 变化）
        let centerVC = PaneContainerController(env: env)
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 400
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        // 右 · Monitor · 最小 200pt · 可折叠（内嵌 MonitorStackController 3 段堆叠）
        let monitorStackVC = MonitorStackController(env: env)
        let monitorItem = NSSplitViewItem(viewController: monitorStackVC)
        monitorItem.minimumThickness = 200
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

#endif
