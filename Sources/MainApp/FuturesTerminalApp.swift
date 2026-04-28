// MainApp · 期货终端真 App 入口
//
// 取代 MetalKLineWindowDemo 命令式 NSApplication.run 的 PoC 路径，
// 用 SwiftUI App 协议提供：
//   - WindowGroup × 2（K 线图表 / 自选合约）· Cmd+N / Cmd+L 多窗口隔离
//   - Settings Scene · Cmd+, 自动绑定偏好设置窗口
//   - 主菜单 .commands（File / View / Window 骨架）
//
// 后续 WP 接入路径：
//   - WP-43 自选 UI → 替换 WatchlistContentView 真实数据源
//   - WP-44 多周期 + 多窗口 UI → CommandMenu 加周期切换 Cmd+1~9
//   - WP-90 上线决策 → Settings 真实订阅 / 账号 / 偏好
//   - M5 集成（StoreCore）→ App.init() 一次 init 6 store + 注入到 Scene

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

@main
struct FuturesTerminalApp: App {

    init() {
        // swift run 是 non-bundle 可执行 · macOS 默认不把它当前台 App ·
        // 菜单栏不切换 · ⌘N / ⌘L / ⌘, 全部落到 Terminal 上。
        // 显式声明 .regular 让主菜单栏 + 全局快捷键 + Dock 图标正常工作。
        // M6 打包 .app bundle 后此调用变成 no-op（Bundle Info.plist 已声明）。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // 主图表窗口（默认启动 + Cmd+N 新建多个 · 每窗口独立 renderer / viewport）
        WindowGroup("K 线图表", id: "chart") {
            ChartScene()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewChartButton()
                Divider()
                OpenWatchlistButton()
                OpenReviewButton()
                OpenAlertButton()
                OpenJournalButton()
            }
            CommandMenu("视图") {
                Text("（多周期切换已支持工具条 Picker · 键盘 ⌘1~9 待 Mac 切机集中接）")
                    .foregroundColor(.secondary)
            }
        }

        // 自选合约窗口（菜单触发打开 · 单实例 · WP-43 UI commit 1/4 起接 WatchlistWindow）
        WindowGroup("自选合约", id: "watchlist") {
            WatchlistWindow()
        }

        // 复盘工作台（⌘R · 8 图独立窗口 · 与 K 线主图区分离）
        WindowGroup("复盘", id: "review") {
            ReviewWindow()
        }

        // 预警面板（⌘B · Bell · 独立窗口）
        WindowGroup("预警", id: "alert") {
            AlertWindow()
        }

        // 交易日志（⌘J · Journal · 独立窗口 · WP-53 UI commit 1/4 起）
        WindowGroup("交易日志", id: "journal") {
            JournalWindow()
        }

        // 偏好设置（Cmd+, 自动绑定 · macOS 标准）
        Settings {
            SettingsContentView()
        }
    }
}

// MARK: - 菜单按钮（@Environment(\.openWindow) 必须在 View 内调用 · 抽出来给 .commands 用）

private struct NewChartButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("新建图表") { openWindow(id: "chart") }
            .keyboardShortcut("n", modifiers: [.command])
    }
}

private struct OpenWatchlistButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("自选合约") { openWindow(id: "watchlist") }
            .keyboardShortcut("l", modifiers: [.command])
    }
}

private struct OpenReviewButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("复盘工作台") { openWindow(id: "review") }
            .keyboardShortcut("r", modifiers: [.command])
    }
}

private struct OpenAlertButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("预警面板") { openWindow(id: "alert") }
            .keyboardShortcut("b", modifiers: [.command])
    }
}

private struct OpenJournalButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("交易日志") { openWindow(id: "journal") }
            .keyboardShortcut("j", modifiers: [.command])
    }
}

#else

@main
struct FuturesTerminalApp {
    static func main() {
        print("⚠️ FuturesTerminal · 仅 macOS（依赖 SwiftUI/AppKit/Metal）· 当前平台跳过")
    }
}

#endif
