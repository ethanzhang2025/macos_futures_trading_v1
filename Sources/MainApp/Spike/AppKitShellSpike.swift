// MainApp · Spike · v17.208 · 方案 3 AppKit 桥接可行性验证
//
// 背景：v17.6-v17.207 累积 6+ 个 Shell 兼容性补丁（isHostedInShell / @State→@Binding /
// tooltip 1.5s 妥协 / menu Button anti-pattern / frame minHeight 撑大）· 反映 SwiftUI 单一
// view tree 不适合多面板嵌入大型独立窗口的结构性问题。
//
// 方案 3：AppKit NSSplitViewController 主容器 + NSHostingController 包裹每个 SwiftUI 子窗口。
// 关键不同：NSHostingController 把每个子 SwiftUI tree 隔离 · 父 AppKit 主导 layout · 不互约束。
//
// 本 spike 验证 5 个核心点（spike 通过 = 方案 3 可行 · 投入 3-5d 重写主容器）：
//   1. NSViewControllerRepresentable + NSSplitViewController 能在 SwiftUI 内桥接渲染
//   2. NSHostingController 包 ChartScene / OptionWindow 等大型 SwiftUI 子树正常显示
//   3. OptionWindow `.frame(minHeight: 720)` 在 NSHostingController 内 不撑大顶部 header
//      （这是 Shell 方案的核心痛点 · v17.207 用 isHostedInShell 治标）
//   4. Environment 跨 NSHostingController 边界手动注入正常（chartTheme / shellVM / store）
//   5. tooltip 0 延迟（每个 NSHostingController 独立 view tree · v17.201 的 1.5s 妥协可回退）
//
// 不动现有 Shell · 独立 WindowGroup id "appkitSpike" · 用户可以并排比较两个窗口效果
// 入口：菜单工具 → "🧪 AppKit Spike（⌘⌥⇧K）"

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import StoreCore
import TradingCore
import AlertCore

// MARK: - SwiftUI 入口 · 顶部 header 显式测试上下文 + AppKit 主容器嵌入

struct AppKitShellSpikeWindow: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics
    @Environment(\.alertEvaluator) private var alertEvaluator
    @Environment(\.simulatedTradingEngine) private var simulatedTradingEngine
    @Environment(\.bannerService) private var bannerService

    var body: some View {
        VStack(spacing: 0) {
            spikeHeader
            Divider()
            // AppKit 主容器（高度由父决定 · 不被子 view minHeight 撑大 · 这是 spike 验证关键）
            AppKitSplitView(
                shellVM: shellVM,
                storeManager: storeManager,
                analytics: analytics,
                alertEvaluator: alertEvaluator,
                simulatedTradingEngine: simulatedTradingEngine,
                bannerService: bannerService
            )
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
            Divider()
            spikeFooter
        }
    }

    /// 顶部说明条 · 让用户知道在测什么
    private var spikeHeader: some View {
        HStack(spacing: 12) {
            Text("🧪 AppKit Spike · v17.208")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)
            Text("验证：OptionWindow .frame(minHeight: 720) 在 NSHostingController 内不撑大本 header")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text("通过判定：本 header 始终可见 + 底部 footer 始终可见")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.orange.opacity(0.08))
    }

    /// 底部说明条 · 与 Shell ShellStatusBar 视觉对齐
    private var spikeFooter: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("底部 footer · 如果 OptionWindow 撑大父容器 · 这一行会被推出可见区")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }
}

// MARK: - AppKit NSSplitViewController 桥接

/// NSViewControllerRepresentable 把 NSSplitViewController 包成 SwiftUI View
/// 关键：每个 split item 是 NSHostingController(rootView: 子 SwiftUI) · 独立 view tree
struct AppKitSplitView: NSViewControllerRepresentable {
    let shellVM: ShellViewModel
    let storeManager: StoreManager?
    let analytics: AnalyticsService?
    let alertEvaluator: AlertEvaluator?
    let simulatedTradingEngine: SimulatedTradingEngine?
    let bannerService: BannerService?

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin

        // 左 pane · ChartScene（大型 SwiftUI 子树 · 测试 Environment 注入完整性）
        let leftVC = NSHostingController(
            rootView: injectEnv(ChartScene())
        )
        let leftItem = NSSplitViewItem(viewController: leftVC)
        leftItem.minimumThickness = 400
        leftItem.canCollapse = false
        split.addSplitViewItem(leftItem)

        // 右 pane · OptionWindow（关键测试：minHeight 720 不撑大父）
        let rightVC = NSHostingController(
            rootView: injectEnv(OptionWindow())
        )
        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.minimumThickness = 300
        rightItem.canCollapse = false
        split.addSplitViewItem(rightItem)

        return split
    }

    func updateNSViewController(_ nsViewController: NSSplitViewController, context: Context) {}

    /// 跨 NSHostingController 边界手动注入 Environment
    ///
    /// 注意（spike 验证点）：NSHostingController 默认**不继承**父 SwiftUI 的 Environment。
    /// 必须显式把 shellVM / storeManager / analytics 等逐个注入到 rootView 上。
    /// 这是方案 3 的"成本" · 需要约 6 行 boilerplate / 每个 NSHostingController · 但一次性。
    @ViewBuilder
    private func injectEnv<V: View>(_ view: V) -> some View {
        view
            .environmentObject(shellVM)
            .environment(\.storeManager, storeManager)
            .environment(\.analytics, analytics)
            .environment(\.alertEvaluator, alertEvaluator)
            .environment(\.simulatedTradingEngine, simulatedTradingEngine)
            .environment(\.bannerService, bannerService)
    }
}

#endif
