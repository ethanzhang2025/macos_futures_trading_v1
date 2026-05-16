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
/// v17.247 修 · NSSplitViewController 子类 → NSViewController + addChild NSSplitViewController
/// 之前 view 直接是 NSSplitView · 外层 MainSplitView 的 vertical divider hit test 被内层 NSSplitView 抢占
/// 改成 wrap NSView · 隔离 outer/inner NSSplitView · 外层 divider 可拖
final class MonitorStackController: NSViewController {
    private let env: AppKitShellEnvironment

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported · MonitorStackController 仅程序化构造")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let inner = NSSplitViewController()
        inner.splitView.isVertical = false   // 横向 divider · 3 段上下堆叠

        // v17.245 · 每段加 SwiftUI section header 显示标题 · trader 一眼看清哪段是什么
        let watchlistVC = AppKitShellHC.wrapAsMonitor(
            MonitorSectionWrapper(title: "⭐️ 自选合约") { WatchlistWindow() }, env: env
        )
        let watchlistItem = NSSplitViewItem(viewController: watchlistVC)
        watchlistItem.canCollapse = true
        watchlistItem.minimumThickness = 80
        inner.addSplitViewItem(watchlistItem)

        let sectorVC = AppKitShellHC.wrapAsMonitor(
            MonitorSectionWrapper(title: "🗂 板块联动") { SectorWindow() }, env: env
        )
        let sectorItem = NSSplitViewItem(viewController: sectorVC)
        sectorItem.canCollapse = true
        sectorItem.minimumThickness = 80
        inner.addSplitViewItem(sectorItem)

        let positionVC = AppKitShellHC.wrapAsMonitor(
            MonitorSectionWrapper(title: "💼 多空持仓") { PositionWindow() }, env: env
        )
        let positionItem = NSSplitViewItem(viewController: positionVC)
        positionItem.canCollapse = true
        positionItem.minimumThickness = 80
        inner.addSplitViewItem(positionItem)

        addChild(inner)
        view.addSubview(inner.view)
        // v17.249 修 · 同 PaneContainerController · Auto Layout .required 与 NSSplitView 冲突 · 改 autoresizingMask
        inner.view.translatesAutoresizingMaskIntoConstraints = true
        inner.view.frame = view.bounds
        inner.view.autoresizingMask = [.width, .height]
    }
}

/// v17.245 · 监盘段标题包装 · 顶部 28pt 标题栏 + 内嵌内容
/// v17.260 · 样式增强 · 测试发现 emoji 渲染了但太淡看不到（size 11 .secondary）
///   - size 11 → 14 / weight .semibold → .bold
///   - .secondary 浅灰 → .primary 主色 (深色背景 = 白)
///   - 加 accent 边框让段 header 视觉分明
///   - 高度 22 → 28 增加点击靶心
private struct MonitorSectionWrapper<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(height: 28)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.accentColor.opacity(0.4)),
                alignment: .bottom
            )
            content
        }
    }
}

#endif
