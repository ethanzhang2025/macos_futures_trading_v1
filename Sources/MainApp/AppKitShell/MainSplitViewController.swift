// MainApp · AppKitShell · v17.222 · 诊断 · 占位 placeholder 验证拖动
//
// 主窗 NSSplitViewController · 3 列横向 split（占位 placeholder 临时测试）
//
// v17.222 诊断 hypothesis：v17.209 初版 placeholder 能拖（截图 d110a764 证明）·
// Step 2 后真子组件（ShellSidebar/ChartScene/WatchlistWindow）拖不动 ·
// 怀疑真子组件 SwiftUI 内部 gesture 拦截 NSSplitView divider hit test。
//
// 用 placeholder 替换 3 个 split item · 如果能拖 = 子组件干扰 · 需要进一步定位 + 修
// 如果还不能拖 = 与子组件无关 · 是 V1 主窗其他结构问题（VStack 顶/底 / WindowGroup 等）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗 NSSplitViewController · 3 列布局
final class MainSplitViewController: NSSplitViewController {
    private let env: AppKitShellEnvironment

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported · V1 NSSplitViewController 仅程序化构造")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true

        // v17.222 诊断 · 3 个 split item 全 placeholder · 验证拖动是否恢复
        // 通过 = 真子组件干扰 hit test · 继续定位
        // 不通过 = 与子组件无关 · 排查 V1 主窗其他结构

        let sidebarVC = NSHostingController(rootView: DiagPlaceholderView(label: "Sidebar 占位", color: .blue))
        sidebarVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        let centerVC = NSHostingController(rootView: DiagPlaceholderView(label: "Center 占位", color: .gray))
        centerVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.canCollapse = false
        addSplitViewItem(centerItem)

        let monitorVC = NSHostingController(rootView: DiagPlaceholderView(label: "Monitor 占位", color: .green))
        monitorVC.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let monitorItem = NSSplitViewItem(viewController: monitorVC)
        monitorItem.canCollapse = true
        addSplitViewItem(monitorItem)
    }
}

/// v17.222 诊断占位 · 与 v17.209 Step 1 PlaceholderPaneView 等价
private struct DiagPlaceholderView: View {
    let label: String
    let color: Color
    var body: some View {
        ZStack {
            color.opacity(0.15)
            VStack(spacing: 8) {
                Text("🩺 v17.222 诊断占位")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
