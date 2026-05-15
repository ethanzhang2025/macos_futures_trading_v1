// MainApp · AppKitShell · v17.227 · V1 重构 A3=C Mini v1
//
// V1 主窗中央 chart 区 · 根据 activeWorkspace.paneLayout 动态创建 1/2/4/6/9 个 ChartScene
// doc 章节 200-218 + A3=C 决策 + 验收第 9 条
//
// Mini v1 设计要点：
// - NSStackView fillEqually 均分 grid（简单 · 不抢外层 NSSplitView divider hit test）
// - 每个 Pane 一个独立 ChartScene NSHostingController · @State 独立 symbol/period
// - 多实例间 group binding 联动通过 shellVM.groupBindings 跨实例同步（沿用 v17.1）
// - Combine 监听 shellVM.objectWillChange · paneLayout / activeWorkspaceID 切换时 rebuild
// - signature 防抖：仅 paneLayout/activeWorkspaceID/paneCount 变化才 rebuild · 普通 symbol 变化不抖动
//
// Full v2（后续）：ChartScene 接 paneID environment · 根据 PaneConfig.symbol/period 显示

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Combine

@MainActor
final class PaneContainerController: NSViewController {
    private let env: AppKitShellEnvironment
    private var lastSignature: String = ""
    private var cancellables = Set<AnyCancellable>()

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported · PaneContainerController 仅程序化构造")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildLayout()
        env.shellVM.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.checkAndRebuild() }
            .store(in: &cancellables)
    }

    /// signature: workspaceID:paneLayout:paneCount · 仅这些变化时 rebuild
    private func currentSignature() -> String {
        guard let ws = env.shellVM.activeWorkspace else { return "empty" }
        return "\(ws.id.uuidString):\(ws.paneLayout.rawValue):\(ws.panes.count)"
    }

    private func checkAndRebuild() {
        let sig = currentSignature()
        guard sig != lastSignature else { return }
        rebuildLayout()
    }

    private func rebuildLayout() {
        lastSignature = currentSignature()
        // 清理旧子组件
        for child in children { child.removeFromParent() }
        for sub in view.subviews { sub.removeFromSuperview() }

        guard let ws = env.shellVM.activeWorkspace else {
            installPlaceholder(text: "暂无 workspace · 请新建一个")
            return
        }
        let layout = ws.paneLayout
        let count = layout.paneCount
        guard count > 0 else {
            installPlaceholder(text: "自定义布局尚未实装")
            return
        }

        // 创建 N 个 ChartScene NSHostingController
        let chartVCs: [NSViewController] = (0..<count).map { _ in
            AppKitShellHC.wrap(ChartScene(), env: env)
        }
        for vc in chartVCs { addChild(vc) }

        let grid = buildGrid(layout: layout, chartViews: chartVCs.map { $0.view })
        view.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func installPlaceholder(text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// 根据 paneLayout 用 NSStackView 嵌套构造 grid · fillEqually 均分
    private func buildGrid(layout: PaneLayout, chartViews: [NSView]) -> NSView {
        switch layout {
        case .single:
            return chartViews[0]
        case .twoHorizontal:
            return makeStack(views: chartViews, orientation: .horizontal)
        case .twoVertical:
            return makeStack(views: chartViews, orientation: .vertical)
        case .four:
            let top = makeStack(views: [chartViews[0], chartViews[1]], orientation: .horizontal)
            let bot = makeStack(views: [chartViews[2], chartViews[3]], orientation: .horizontal)
            return makeStack(views: [top, bot], orientation: .vertical)
        case .sixGrid:
            let top = makeStack(views: Array(chartViews[0..<3]), orientation: .horizontal)
            let bot = makeStack(views: Array(chartViews[3..<6]), orientation: .horizontal)
            return makeStack(views: [top, bot], orientation: .vertical)
        case .nineGrid:
            let r1 = makeStack(views: Array(chartViews[0..<3]), orientation: .horizontal)
            let r2 = makeStack(views: Array(chartViews[3..<6]), orientation: .horizontal)
            let r3 = makeStack(views: Array(chartViews[6..<9]), orientation: .horizontal)
            return makeStack(views: [r1, r2, r3], orientation: .vertical)
        case .custom:
            return chartViews[0]
        }
    }

    private func makeStack(views: [NSView], orientation: NSUserInterfaceLayoutOrientation) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.distribution = .fillEqually
        stack.spacing = 2
        return stack
    }
}

#endif
