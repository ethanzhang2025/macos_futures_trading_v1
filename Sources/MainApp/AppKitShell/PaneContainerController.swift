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

        // v17.246 · 创建 N 个 ChartScene NSHostingController + 走 NSSplitViewController 嵌套强制均分
        let chartVCs: [NSViewController] = (0..<count).map { _ in
            AppKitShellHC.wrap(ChartScene(), env: env)
        }
        let rootVC = buildGridController(layout: layout, charts: chartVCs)
        addChild(rootVC)
        view.addSubview(rootVC.view)
        rootVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            rootVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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

    /// 根据 paneLayout 用 NSSplitViewController 嵌套构造 grid · 强制按 preferredThicknessFraction 均分
    /// v17.245 用 raw NSSplitView 默认 sizing 不均分（第一个 view 占大部分 · 其他被挤到 0 宽）
    /// v17.246 改 NSSplitViewController + NSSplitViewItem.preferredThicknessFraction = 1/N · 严格按比例
    private func buildGridController(layout: PaneLayout, charts: [NSViewController]) -> NSViewController {
        switch layout {
        case .single:
            return charts[0]
        case .twoHorizontal:
            return makeSplitController(controllers: charts, isVertical: true, fraction: 1.0 / 2)
        case .twoVertical:
            return makeSplitController(controllers: charts, isVertical: false, fraction: 1.0 / 2)
        case .four:
            let topRow = makeSplitController(controllers: [charts[0], charts[1]], isVertical: true, fraction: 1.0 / 2)
            let botRow = makeSplitController(controllers: [charts[2], charts[3]], isVertical: true, fraction: 1.0 / 2)
            return makeSplitController(controllers: [topRow, botRow], isVertical: false, fraction: 1.0 / 2)
        case .sixGrid:
            let topRow = makeSplitController(controllers: Array(charts[0..<3]), isVertical: true, fraction: 1.0 / 3)
            let botRow = makeSplitController(controllers: Array(charts[3..<6]), isVertical: true, fraction: 1.0 / 3)
            return makeSplitController(controllers: [topRow, botRow], isVertical: false, fraction: 1.0 / 2)
        case .nineGrid:
            let r1 = makeSplitController(controllers: Array(charts[0..<3]), isVertical: true, fraction: 1.0 / 3)
            let r2 = makeSplitController(controllers: Array(charts[3..<6]), isVertical: true, fraction: 1.0 / 3)
            let r3 = makeSplitController(controllers: Array(charts[6..<9]), isVertical: true, fraction: 1.0 / 3)
            return makeSplitController(controllers: [r1, r2, r3], isVertical: false, fraction: 1.0 / 3)
        case .custom:
            return charts[0]
        }
    }

    /// NSSplitViewController + preferredThicknessFraction 强制按比例均分
    /// isVertical=true 是 vertical divider（左右排列）· false 是 horizontal divider（上下排列）
    private func makeSplitController(controllers: [NSViewController], isVertical: Bool, fraction: CGFloat) -> NSSplitViewController {
        let split = NSSplitViewController()
        split.splitView.isVertical = isVertical
        split.splitView.dividerStyle = .thin
        for ctrl in controllers {
            let item = NSSplitViewItem(viewController: ctrl)
            item.canCollapse = false
            item.minimumThickness = 100
            item.preferredThicknessFraction = fraction
            split.addSplitViewItem(item)
        }
        return split
    }
}

#endif
