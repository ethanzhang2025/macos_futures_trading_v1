// iPadApp · WP-61 iPad 基础版主入口（v15.25 batch001）
//
// 设计依据：
//   - D2 §M7-M9：iPad 基础同步看盘版 · 不做完整专业工作流
//   - A12 §10：不照搬 Mac UI · NavigationSplitView 替代多窗口 · sheet 替代菜单 · gesture 替代快捷键
//   - WP-60 SyncCore 已铺好 → iPad 与 Mac 共用 CloudKit container
//
// 平台门控：
//   - iOS：完整 SwiftUI App
//   - macOS / Linux：fallback @main 仅打印提示（避免 swift build 失败）
//
// 后续 batch 接入：
//   - batch002 IPadRootView NavigationSplitView
//   - batch003 WatchlistView_iOS
//   - batch004 ChartView_iOS
//   - batch005 多周期 toolbar
//   - batch006 SyncCoordinator + CloudKit
//   - batch007 Settings sheet + 主题 + 同步状态
//   - batch008 行情 detail panel
//   - batch009 文档 + Mac 验收 readme

#if canImport(SwiftUI) && os(iOS)

import SwiftUI

@main
struct FuturesTerminaliPadApp: App {

    init() {
        // batch006+ 在这里接入：
        //   - SyncCoordinator(container: CKContainer(identifier: "iCloud.com.<yourorg>.FuturesTerminal"))
        //   - 加载本地 SQLite store（自选 / 工作区 / settings）
        //   - 后台 sync 任务订阅
    }

    var body: some Scene {
        WindowGroup {
            iPadPlaceholderView()
        }
    }
}

/// batch001 占位视图 · batch002 替换为 IPadRootView NavigationSplitView
private struct iPadPlaceholderView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("期货终端 · iPad 基础版")
                .font(.title)
                .fontWeight(.semibold)

            Text("v15.25 batch001 骨架\n后续 batch 填入自选 / 图表 / 多周期 / CloudKit 同步")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#else

// macOS / Linux fallback · 不应作为可执行入口运行（仅满足 SwiftPM 编译要求）
@main
struct FuturesTerminaliPadApp {
    static func main() {
        print("⚠️ FuturesTerminal iPadApp · 仅 iOS（依赖 SwiftUI iOS）· 当前平台跳过")
        print("   Mac 端用 MainApp（macOS）· iPad 端用 iPadApp（iOS）")
    }
}

#endif
