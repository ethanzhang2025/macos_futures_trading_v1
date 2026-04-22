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
    /// 按窗口分组的 Combine 订阅；窗口关闭时精确清理，避免 publisher 在 teardown 过程中继续触发
    private var windowCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    /// 按窗口分组的 vm 引用；关窗时先显式 stopPolling，再 release
    private var windowViewModels: [ObjectIdentifier: AppViewModel] = [:]

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        newWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    // 关最后一个窗口不退出 app —— 规避 SwiftUI + NSHostingView 在 terminate flow 中
    // pool pop 时 over-release NSConcretePointerArray 的已知 crash。
    // 用户走 ⌘Q 退出；Dock 重开触发 applicationShouldHandleReopen 新建窗口。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow() }
        return true
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
        // 订阅按窗口分组存；关窗时连带清理，避免闭包在窗口 teardown 过程中继续运行
        let titleCancellable = viewModel.$selectedSymbol
            .combineLatest(viewModel.$selectedPeriod)
            .sink { [weak window] symbol, period in
                guard let window else { return }
                let name = WatchItem.allContracts.first(where: { $0.symbol == symbol })?.name ?? symbol
                window.title = "\(name) · \(period)"
            }
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
        let key = ObjectIdentifier(window)
        windows.append(window)
        windowCancellables[key] = titleCancellable
        windowViewModels[key] = viewModel

        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
    }

    @MainActor @objc private func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        let key = ObjectIdentifier(w)
        // willClose 在当前 runloop tick 的 CA transaction commit 前触发，NSHostingView/SwiftUI
        // 内部 pointer array 里仍挂着捕获 vm 的 block。若此刻同步释放 vm，pool pop 时
        // 会 over-release 野指针（表现：objc_release → _Block_release → NSConcretePointerArray dealloc）。
        // 只做两件可安全同步完成的事：
        //   ① 停轮询（仅 cancel Task，不释放对象）
        //   ② 移除自己作为 NC observer（避免重复触发）
        windowViewModels[key]?.stopPolling()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: w)
        // 其余强引用清理推到下一个 runloop tick：此时 CA transaction 已 commit 完当前帧，
        // NSHostingView 已完整释放其内部 observer，vm 再走默认释放链就安全了。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowCancellables.removeValue(forKey: key)
            self.windowViewModels.removeValue(forKey: key)
            self.windows.removeAll { $0 === w }
        }
    }

    @MainActor private func setupMenuBar() {
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
