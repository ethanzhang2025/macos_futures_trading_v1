import SwiftUI
import AppKit
import Combine

/// SPM可执行目标没有.app bundle，需要手动创建NSApplication和窗口
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var cancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        newWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 新开窗口：每个窗口独立 AppViewModel（合约/周期/指标参数各自独立），watchList 通过 UserDefaults 共享
    @MainActor @objc func newWindow() {
        let viewModel = AppViewModel()
        let contentView = ContentView()
            .environmentObject(viewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 850),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 标题随 selectedSymbol / selectedPeriod 变化：「螺纹钢 · 日线」
        viewModel.$selectedSymbol
            .combineLatest(viewModel.$selectedPeriod)
            .sink { [weak window] symbol, period in
                guard let window else { return }
                let name = WatchItem.allContracts.first(where: { $0.symbol == symbol })?.name ?? symbol
                window.title = "\(name) · \(period)"
            }
            .store(in: &cancellables)
        // 级联排列：避免新窗口完全盖住旧窗口
        if let last = windows.last {
            let f = last.frame
            window.setFrame(NSRect(x: f.origin.x + 30, y: f.origin.y - 30, width: f.width, height: f.height), display: false)
        } else {
            window.center()
        }
        window.contentView = NSHostingView(rootView: contentView)
        window.contentMinSize = NSSize(width: 1200, height: 700)
        window.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        windows.append(window)

        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
    }

    @MainActor @objc private func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App菜单
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "关于期货交易终端", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 文件菜单：新窗口 ⌘N（macOS 系统惯例，非产品自定义快捷键）
        let fileMenu = NSMenu(title: "文件")
        let newWinItem = NSMenuItem(title: "新窗口", action: #selector(newWindow), keyEquivalent: "n")
        newWinItem.target = self
        fileMenu.addItem(newWinItem)
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

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
