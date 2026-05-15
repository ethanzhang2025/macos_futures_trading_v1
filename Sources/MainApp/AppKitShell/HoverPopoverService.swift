// MainApp · AppKitShell · v17.226 · V1 重构 Step 5
//
// NSPopover 0 延迟 hover tooltip · 替代 macOS 系统 .help() 1.5s 延迟
// doc 章节 314-332（NSPopover 规则）+ Step 5（替代 .help() 不稳定）
//
// 设计要点：
// - 单例 NSPopover · 重用避免频繁创建（show 时只换 contentViewController）
// - behavior=.transient · 鼠标移出 anchor / 点击外部自动关
// - animates=false · 0 延迟 + 0 淡入动画
// - SwiftUI 入口在 InstantTooltip.tooltip() · 全 app 调用点零修改
// - 失败 fallback 走系统 .help()（无 popoverService environment 时）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗 hover popover 服务 · 单例 NSPopover · 0 延迟自定义 tooltip
@MainActor
final class HoverPopoverService {
    private let popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        return p
    }()

    func show(anchor: NSView, text: String) {
        guard !text.isEmpty, anchor.window != nil else { return }
        let content = HoverPopoverContent(text: text)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func hide() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}

/// EnvironmentKey · HoverPopoverService 注入（V1 主窗内嵌组件用）
private struct HoverPopoverServiceKey: EnvironmentKey {
    static let defaultValue: HoverPopoverService? = nil
}

extension EnvironmentValues {
    var hoverPopoverService: HoverPopoverService? {
        get { self[HoverPopoverServiceKey.self] }
        set { self[HoverPopoverServiceKey.self] = newValue }
    }
}

/// NSPopover 内嵌 SwiftUI tooltip 视图 · 紧凑 padding + 自动尺寸
private struct HoverPopoverContent: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize()
    }
}

/// NSViewRepresentable 透明 anchor · 让 NSPopover.show(relativeTo:of:) 拿到 NSView ref
struct HoverPopoverAnchor: NSViewRepresentable {
    final class Coordinator {
        weak var nsView: NSView?
    }

    let onAnchorReady: (NSView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.nsView = v
        DispatchQueue.main.async {
            onAnchorReady(v)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// SwiftUI hover popover modifier · 内部走 HoverPopoverService（不可用则降级 .help()）
struct HoverPopoverModifier: ViewModifier {
    let text: String
    @Environment(\.hoverPopoverService) private var service
    @State private var anchor: NSView?

    func body(content: Content) -> some View {
        if let service {
            content
                .background(
                    HoverPopoverAnchor { v in anchor = v }
                        .allowsHitTesting(false)
                )
                .onHover { hovering in
                    if hovering, let a = anchor {
                        service.show(anchor: a, text: text)
                    } else {
                        service.hide()
                    }
                }
        } else {
            content.help(text)
        }
    }
}

#endif
