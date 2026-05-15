// MainApp · AppKitShell · v17.220 · V1 重构 Step 2a · 方案 G 调研 fix
//
// 主窗 NSSplitViewController · 3 列横向 split（Sidebar / PaneContainer / Monitor）
// doc 章节 153-163
//
// v17.220 · 方案 G 调研发现：HashNuke GitHub working sample (NSSplitViewController +
// NSViewControllerRepresentable + SwiftUI) 用 Auto Layout widthAnchor 约束设最小宽度 ·
// 不用 NSSplitViewItem.minimumThickness API · divider 拖动正常。
//
// 强烈怀疑根因：NSSplitViewItem.minimumThickness 在 SwiftUI WindowGroup 嵌入环境下
// 锁定 split position 但吞掉 user drag event。
//
// 修法：删 NSSplitViewItem.minimumThickness · 改用每个子视图的 view.widthAnchor 约束

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
        // 用 NSSplitView 默认 dividerStyle (paneSplitter · 3pt 宽 · 标准 Xcode/Finder 风格)

        // 左 · Sidebar · widthAnchor ≥ 200 enforce 最小宽度（替代 NSSplitViewItem.minimumThickness）
        let sidebarVC = AppKitShellHC.wrap(ShellSidebar(), env: env)
        sidebarVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.canCollapse = true   // v17.221 真修 · canCollapse=false 在 SwiftUI 嵌入下锁死整个 NSSplitView 拖动 · 改回 true 恢复拖动
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer（A3=C · 看盘 tab 下 chart Pane 1-N 切分）
        // Step 2 暂用单 ChartScene · Step 3+ 接入真 PaneContainer（嵌套 NSSplitView 1/2/4/6/9 grid）
        let centerVC = AppKitShellHC.wrap(ChartScene(), env: env)
        centerVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.canCollapse = true
        addSplitViewItem(centerItem)

        // 右 · Monitor 区（A2=C · Watchlist / Sector / Position · 可 detach 为 NSPanel）
        // Step 2 暂用 WatchlistWindow · Step 4 Monitor detach 接入时加 Sector/Position 切换
        let monitorVC = AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        monitorVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let monitorItem = NSSplitViewItem(viewController: monitorVC)
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

#endif
