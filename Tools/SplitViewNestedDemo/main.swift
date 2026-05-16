// SplitViewNestedDemo · 5.1 节四宫格诊断 demo · 2026-05-16
//
// 镜像 MainSplitViewController + PaneContainerController + MonitorStackController 3 层嵌套结构
// 用 4 个彩色 NSView placeholder 替代 ChartScene NSHostingController
// 不引入任何业务依赖（无 Shared / DataCore / SwiftUI / NSHostingController）
//
// 验证假设：
//   H1 · NSSplitViewController 3 层嵌套自身就是 root cause
//   H2 · ChartScene SwiftUI minWidth 残留
//   H3 · NSHostingController.intrinsicContentSize 覆盖 hit test
//
// 区分方法：
//   - 全 6 处 divider 都能拖 → H1 排除 · root cause = H2 或 H3（ChartScene 内部）
//   - 全都不能拖 → H1 确认（NSSplitViewController 嵌套自身）
//   - 部分能拖 → 记录哪条 · 缩小排查范围
//
// 运行：swift run SplitViewNestedDemo
// 平台：macOS only · Linux 端打印退出 0

#if canImport(AppKit)

import AppKit

// MARK: - ColoredView · 带文字的彩色占位视图

final class ColoredView: NSView {
    private let label: NSTextField

    init(color: NSColor, title: String) {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        lbl.textColor = .white
        lbl.alignment = .center
        lbl.backgroundColor = .clear
        lbl.drawsBackground = false
        lbl.translatesAutoresizingMaskIntoConstraints = false
        self.label = lbl
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

func makeColoredVC(color: NSColor, title: String) -> NSViewController {
    let vc = NSViewController()
    vc.view = ColoredView(color: color, title: title)
    return vc
}

// MARK: - PaneContainerVC · 镜像 PaneContainerController.swift（四宫格 = 3 层嵌套）

final class PaneContainerVC: NSViewController {
    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let red    = makeColoredVC(color: .systemRed,    title: "Chart 1 · 红")
        let green  = makeColoredVC(color: .systemGreen,  title: "Chart 2 · 绿")
        let blue   = makeColoredVC(color: .systemBlue,   title: "Chart 3 · 蓝")
        let yellow = makeColoredVC(color: .systemYellow, title: "Chart 4 · 黄")

        let topRow = makeSplit(controllers: [red, green],    isVertical: true,  fraction: 0.5)
        let botRow = makeSplit(controllers: [blue, yellow],  isVertical: true,  fraction: 0.5)
        let outer  = makeSplit(controllers: [topRow, botRow], isVertical: false, fraction: 0.5)

        addChild(outer)
        view.addSubview(outer.view)
        // 镜像 v17.249 autoresizingMask
        outer.view.translatesAutoresizingMaskIntoConstraints = true
        outer.view.frame = view.bounds
        outer.view.autoresizingMask = [.width, .height]
    }

    private func makeSplit(controllers: [NSViewController], isVertical: Bool, fraction: CGFloat) -> NSSplitViewController {
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

// MARK: - MonitorStackVC · 镜像 MonitorStackController.swift v17.247

final class MonitorStackVC: NSViewController {
    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let watchlist = makeColoredVC(color: .systemOrange, title: "Monitor 1 · 橙 · Watchlist")
        let sector    = makeColoredVC(color: .systemPurple, title: "Monitor 2 · 紫 · Sector")
        let position  = makeColoredVC(color: .systemTeal,   title: "Monitor 3 · 青 · Position")

        let inner = NSSplitViewController()
        inner.splitView.isVertical = false
        for vc in [watchlist, sector, position] {
            let item = NSSplitViewItem(viewController: vc)
            item.canCollapse = true
            item.minimumThickness = 80
            inner.addSplitViewItem(item)
        }
        addChild(inner)
        view.addSubview(inner.view)
        inner.view.translatesAutoresizingMaskIntoConstraints = true
        inner.view.frame = view.bounds
        inner.view.autoresizingMask = [.width, .height]
    }
}

// MARK: - MainSplitVC · 镜像 MainSplitViewController.swift（3 列横向）

final class MainSplitVC: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true

        let sidebar = makeColoredVC(color: .darkGray, title: "Sidebar · 灰")
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        let center = PaneContainerVC()
        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = 400
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        let monitor = MonitorStackVC()
        let monitorItem = NSSplitViewItem(viewController: monitor)
        monitorItem.minimumThickness = 200
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainVC = MainSplitVC()
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SplitView 嵌套诊断 · 试拖 7 条 divider"
        window.contentViewController = mainVC
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        printGuide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func printGuide() {
        let lines = [
            "===== SplitView 嵌套诊断 demo =====",
            "",
            "窗口已开 · 请尝试以下 7 处拖动 · 记录每条能否拖动:",
            "",
            "外层 MainSplit (3 列):",
            "  1. 灰 sidebar 与中央 chart 之间 (vertical divider)",
            "  2. 中央 chart 与右侧 monitor 之间 (vertical divider)",
            "",
            "中央 PaneContainer (四宫格 · 3 层嵌套):",
            "  3. 红 / 绿 之间 (vertical divider · 顶行)",
            "  4. 蓝 / 黄 之间 (vertical divider · 底行)",
            "  5. 顶行 (红绿) 与 底行 (蓝黄) 之间 (horizontal divider)",
            "",
            "右侧 MonitorStack (3 段):",
            "  6. 橙 / 紫 之间 (horizontal divider)",
            "  7. 紫 / 青 之间 (horizontal divider)",
            "",
            "结果对照:",
            "  - 全 7 条都能拖 → H1 排除 · root cause = ChartScene SwiftUI 内部 (H2/H3)",
            "  - 1-2 能拖, 3-7 不能 → 嵌套层数是问题",
            "  - 全都不能拖 → H1 确认 · NSSplitViewController 嵌套自身",
            "  - 其他模式 → 记录具体哪条 · 给 AI 看",
            "",
            "退出 demo: ⌘Q 或 关窗口"
        ]
        for line in lines { print(line) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

#else

import Foundation
print("SplitViewNestedDemo · macOS only · Linux 端跳过")
exit(0)

#endif
