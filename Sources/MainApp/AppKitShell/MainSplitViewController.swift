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

        // v17.265 · holdingPriority 修法 · 解决"拖左侧 divider 右边 monitor 变 · center 不变"bug
        // NSSplitView 默认 priority 250 都相同 · 拖 divider 时把 delta 推给最远的 item
        // 修: center 设 248 (低) · sidebar/monitor 设 252 (高) · 拖任一 divider 都让 center 优先变化

        // 左 · Sidebar · 最小 200pt · 可折叠 · 高 priority (拖时保持)
        let sidebarVC = AppKitShellHC.wrap(ShellSidebar(), env: env)
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(252)
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer · 最小 200pt · 不可折叠 · 低 priority (拖时优先变)
        // v17.266 · ui_tree 验证 center 当前 = 400pt (= 旧 minThickness · 卡 min 不能 shrink)
        //   → NSSplitView 把 delta 推给 monitor · center 不变
        // 改 400 → 200 · 让 center 真正能 shrink/grow 接收 delta
        // inner 4 chart pane 各自 minWidth=0 (isInV1MainWindow · v17.223) · 不阻止 center 压缩
        let centerVC = PaneContainerController(env: env)
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 200
        centerItem.canCollapse = false
        centerItem.holdingPriority = NSLayoutConstraint.Priority(248)
        addSplitViewItem(centerItem)

        // 右 · Monitor · 最小 200pt · 可折叠 · 高 priority (拖时保持)
        let monitorStackVC = MonitorStackController(env: env)
        let monitorItem = NSSplitViewItem(viewController: monitorStackVC)
        monitorItem.minimumThickness = 200
        monitorItem.canCollapse = true
        monitorItem.holdingPriority = NSLayoutConstraint.Priority(252)
        addSplitViewItem(monitorItem)
    }
}

#endif
