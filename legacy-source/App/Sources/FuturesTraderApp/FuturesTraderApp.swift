import SwiftUI
import AppKit
import Combine

/// SPM 可执行目标没有 .app bundle，手动创建 NSApplication + 单个 NSWindow。
/// 多窗口在 Alpha 阶段回退 —— 手搓 NSHostingView 多实例的生命周期在 macOS 26 SDK + SwiftUI runtime
/// 反复撞 pool pop over-release / teardown hang，投入产出不划算。Beta 阶段迁到
/// SwiftUI App + WindowGroup 原生多窗口时重做（详见 Docs/Alpha 进度日志.md 对应 decision）。
@main
enum FuturesTraderApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let viewModel = AppViewModel()
    private var titleCancellable: AnyCancellable?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor private func setupWindow() {
        let contentView = ContentView().environmentObject(viewModel)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 850),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.contentView = NSHostingView(rootView: contentView)
        w.contentMinSize = NSSize(width: 1200, height: 700)
        w.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.makeKeyAndOrderFront(nil)

        // 窗口标题随 合约/周期 变化：「螺纹钢 · 日线」
        titleCancellable = viewModel.$selectedSymbol
            .combineLatest(viewModel.$selectedPeriod)
            .sink { [weak w] symbol, period in
                guard let w else { return }
                let name = WatchItem.allContracts.first(where: { $0.symbol == symbol })?.name ?? symbol
                w.title = "\(name) · \(period)"
            }

        window = w
    }

    @MainActor private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App 菜单
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于期货交易终端", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 窗口菜单
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
