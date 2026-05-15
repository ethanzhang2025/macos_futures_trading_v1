// MainApp · AppKitShell · v17.209 · V1 重构 Step 2a
//
// 主窗 NSSplitViewController · 3 列横向 split（Sidebar / PaneContainer / Monitor）
// doc 章节 153-163 + C3 数值约束（Sidebar min 200/max 360/pref 240）
//
// Step 1 · 3 个 split item placeholder NSHostingController（已通过桥接验证）
// Step 2a · 替换为真 SwiftUI 子树（ShellSidebar / ChartScene / WatchlistWindow）
//   - 中央 PaneContainer 暂用单 ChartScene 起步 · Step 3+ 接入真 PaneContainer 1-N 切分
//   - 右 Monitor 暂用 WatchlistWindow · Step 4 Monitor detach NSPanel 时再接 Sector/Position 切换

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
        // v17.218 · 用默认 paneSplitter（3pt 宽 · 用户拖动 affordance 更好）· .thin 1pt 用户找不准 hover target
        // splitView.dividerStyle = .thin  // 删除 · 用 NSSplitView 默认 .paneSplitter

        // 左 · Sidebar（C3 · min 200 / max 360 / pref 240）
        // Step 1 canCollapse=false · Step 2 toolbar/菜单/⌘⌃[ 完整方案后再 enable
        let sidebarItem = NSSplitViewItem(
            viewController: AppKitShellHC.wrap(ShellSidebar(), env: env)
        )
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.preferredThicknessFraction = 240.0 / 1600.0
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
        // v17.217 · min 60 让 trader 能拖窄到几乎只剩窄列（不进 collapse 死胡同 · 仍可拖回）
        // ChartScene toolbar 需要 ~1240pt · 主窗 1440 - 240 sidebar - 60 watchlist = 1140pt（13" 边界够）
        // 主窗 1600 - 240 - 60 = 1300pt · 主窗 1800 - 240 - 60 = 1500pt
        // preferred 220/1800 ≈ 12.2% · default chart 区 = 1340pt 完整 toolbar ✅
        let monitorItem = NSSplitViewItem(
            viewController: AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        )
        monitorItem.minimumThickness = 60
        monitorItem.maximumThickness = 480
        monitorItem.preferredThicknessFraction = 220.0 / 1800.0
        monitorItem.canCollapse = false
        addSplitViewItem(monitorItem)
    }
}

#endif
