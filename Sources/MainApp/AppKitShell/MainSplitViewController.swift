// MainApp · AppKitShell · v17.219 · V1 重构 Step 2a
//
// 主窗 NSSplitViewController · 3 列横向 split（Sidebar / PaneContainer / Monitor）
// doc 章节 153-163
//
// v17.219 · 配置极简对齐 spike v17.208（spike 已验证可拖）·
//   - 删 maximumThickness · 删 preferredThicknessFraction · 删 dividerStyle.thin
//   - 仅保留 minimumThickness + canCollapse=false · 让 NSSplitView 默认行为完整启用 user drag
// 之前 v17.213-218 多约束疑似锁定 NSSplitView 拖动（macOS 26 行为）· 回退到极简配置

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
        // 用 NSSplitView 默认 dividerStyle (paneSplitter · 3pt 宽 · 用户拖动 affordance 标准 Xcode/Finder 风格)

        // 左 · Sidebar
        let sidebarItem = NSSplitViewItem(
            viewController: AppKitShellHC.wrap(ShellSidebar(), env: env)
        )
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        // 中 · PaneContainer（A3=C · 看盘 tab 下 chart Pane 1-N 切分）
        // Step 2 暂用单 ChartScene · Step 3+ 接入真 PaneContainer（嵌套 NSSplitView 1/2/4/6/9 grid）
        let centerItem = NSSplitViewItem(
            viewController: AppKitShellHC.wrap(ChartScene(), env: env)
        )
        centerItem.minimumThickness = 400
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        // 右 · Monitor 区（A2=C · Watchlist / Sector / Position · 可 detach 为 NSPanel）
        // Step 2 暂用 WatchlistWindow · Step 4 Monitor detach 接入时加 Sector/Position 切换
        let monitorItem = NSSplitViewItem(
            viewController: AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        )
        monitorItem.minimumThickness = 200
        monitorItem.canCollapse = false
        addSplitViewItem(monitorItem)
    }
}

#endif
