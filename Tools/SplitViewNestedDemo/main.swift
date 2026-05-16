// SplitViewNestedDemo · 5.1 节四宫格诊断 demo · v17.251 · 2026-05-16
//
// v17.250 第一轮诊断反馈：
//   - inner（PaneContainer 四宫格 / Monitor 3 段）divider 全能拖 ✅
//   - outer MainSplit 的 1, 2 vertical divider 拖不动 ❌
// → 修订假设：不是 inner 嵌套抢 inner hit test · 而是 inner 是否抢 outer hit test？
//
// v17.251 升级 · 3 窗口对比锁定 root cause:
//   Mode 1 simple      · center+monitor 都是简单 ColoredView（无 inner 嵌套）
//   Mode 2 midNested   · center 嵌套 PaneContainer / monitor 简单（隔离 center 嵌套）
//   Mode 3 fullNested  · center+monitor 都嵌套（当前实现 · 已知 1, 2 不能拖）
//
// 锁定逻辑:
//   Mode 1 能拖 1, 2 + Mode 2 不能拖 1 → root cause = inner 嵌套抢 outer hit test
//   Mode 1 也不能拖 → root cause = outer MainSplit 自身配置问题（与 inner 无关）
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
        lbl.font = NSFont.systemFont(ofSize: 16, weight: .bold)
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
        let watchlist = makeColoredVC(color: .systemOrange, title: "Monitor 1 · 橙")
        let sector    = makeColoredVC(color: .systemPurple, title: "Monitor 2 · 紫")
        let position  = makeColoredVC(color: .systemTeal,   title: "Monitor 3 · 青")

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

// MARK: - DemoMode · 3 种对比 mode

enum DemoMode {
    case simple        // center / monitor 都是简单 ColoredView · 无 inner 嵌套
    case midNested     // center 嵌套 PaneContainer · monitor 简单
    case fullNested    // center + monitor 都嵌套（当前实现）

    var title: String {
        switch self {
        case .simple:     return "Mode 1/3 · simple · 无 inner 嵌套"
        case .midNested:  return "Mode 2/3 · midNested · 仅 center 嵌套"
        case .fullNested: return "Mode 3/3 · fullNested · center + monitor 都嵌套"
        }
    }
}

// MARK: - MainSplitVC · 镜像 MainSplitViewController.swift（3 列横向）

final class MainSplitVC: NSSplitViewController {
    private let mode: DemoMode

    init(mode: DemoMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true

        let sidebar = makeColoredVC(color: .darkGray, title: "Sidebar · 灰")
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        let center: NSViewController
        switch mode {
        case .simple:
            center = makeColoredVC(color: .systemBrown, title: "中央 · 简单棕 · 无嵌套")
        case .midNested, .fullNested:
            center = PaneContainerVC()
        }
        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = 400
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        let monitor: NSViewController
        switch mode {
        case .simple, .midNested:
            monitor = makeColoredVC(color: .systemPink, title: "Monitor · 简单粉 · 无嵌套")
        case .fullNested:
            monitor = MonitorStackVC()
        }
        let monitorItem = NSSplitViewItem(viewController: monitor)
        monitorItem.minimumThickness = 200
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

// MARK: - AppDelegate · 3 窗口对比启动

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let modes: [DemoMode] = [.simple, .midNested, .fullNested]
        let winW: CGFloat = 1000
        let winH: CGFloat = 600
        let stepX: CGFloat = 80
        let stepY: CGFloat = 80
        let baseX: CGFloat = 60
        let baseY: CGFloat = 60

        for (i, mode) in modes.enumerated() {
            let mainVC = MainSplitVC(mode: mode)
            let win = NSWindow(
                contentRect: NSRect(
                    x: baseX + CGFloat(i) * stepX,
                    y: baseY + CGFloat(i) * stepY,
                    width: winW,
                    height: winH
                ),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = mode.title
            win.contentViewController = mainVC
            win.makeKeyAndOrderFront(nil)
            windows.append(win)
        }
        NSApp.activate(ignoringOtherApps: true)

        printGuide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func printGuide() {
        let lines = [
            "===== SplitView 嵌套对比 demo · v17.251 =====",
            "",
            "3 窗口已开 · 请分别测每个窗口的 outer 1 / 2 vertical divider 是否能拖:",
            "",
            "Mode 1/3 · simple:",
            "  - center / monitor 都是简单 ColoredView · 无 inner 嵌套",
            "  - 测: 灰 ↔ 棕 (divider 1) / 棕 ↔ 粉 (divider 2)",
            "  - 预期: 都能拖（无 inner 干扰）",
            "",
            "Mode 2/3 · midNested:",
            "  - center 嵌套四宫格 · monitor 简单",
            "  - 测: 灰 ↔ 四宫格 (divider 1) / 四宫格 ↔ 粉 (divider 2)",
            "  - 关键: 哪条能哪条不能",
            "",
            "Mode 3/3 · fullNested:",
            "  - center + monitor 都嵌套（当前主工程实现）",
            "  - 已知 1, 2 都拖不动 · 重新确认即可",
            "",
            "反馈给 AI:",
            "  Mode 1: 1=? / 2=?",
            "  Mode 2: 1=? / 2=?",
            "  Mode 3: 1=? / 2=?",
            "",
            "锁定逻辑:",
            "  Mode 1 都能拖 · Mode 2 divider 1 不能拖 → inner 嵌套抢 outer hit test ✅ root cause",
            "  Mode 1 不能拖              → outer MainSplit 自身配置问题（与 inner 无关）",
            "",
            "退出: ⌘Q 或 关全部窗口"
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
