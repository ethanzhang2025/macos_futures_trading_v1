// MainApp · AppKitShell · v17.241 · V1 重构 A2=C Full v2
//
// 主窗右侧 monitor 区 3 段垂直堆叠 · 嵌套 NSSplitViewController
// doc 章节 162-163「MonitorSplitItems (Watchlist / Sector / Position · NSHostingController)」
//
// 设计要点：
// - splitView.isVertical = false · 横向 divider · 3 段上下堆叠
// - 各 NSSplitViewItem.canCollapse = true · trader 可折叠不需要的段
// - 3 个组件已加 isHostedInShell 嵌入模式（v17.241 · minWidth/minHeight = 0 防撑大）
// - 用 AppKitShellHC.wrapAsMonitor 注入 environment（isHostedInShell = true）
//
// v17.222 教训：子组件 minWidth 撑大 NSHostingController.view 覆盖 NSSplitView divider hit test
//   → SectorWindow / PositionWindow 加 isHostedInShell 条件化 minWidth/minHeight=0 后规避

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗监盘区控制器 · 垂直堆叠 3 段（自选 / 板块 / 持仓）
final class MonitorStackController: NSSplitViewController {
    private let env: AppKitShellEnvironment

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported · MonitorStackController 仅程序化构造")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = false   // 横向 divider · 3 段上下堆叠

        // 上 · 自选合约
        let watchlistVC = AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        let watchlistItem = NSSplitViewItem(viewController: watchlistVC)
        watchlistItem.canCollapse = true
        watchlistItem.minimumThickness = 80
        addSplitViewItem(watchlistItem)

        // 中 · 板块联动
        let sectorVC = AppKitShellHC.wrapAsMonitor(SectorWindow(), env: env)
        let sectorItem = NSSplitViewItem(viewController: sectorVC)
        sectorItem.canCollapse = true
        sectorItem.minimumThickness = 80
        addSplitViewItem(sectorItem)

        // 下 · 多空持仓
        let positionVC = AppKitShellHC.wrapAsMonitor(PositionWindow(), env: env)
        let positionItem = NSSplitViewItem(viewController: positionVC)
        positionItem.canCollapse = true
        positionItem.minimumThickness = 80
        addSplitViewItem(positionItem)
    }
}

#endif
