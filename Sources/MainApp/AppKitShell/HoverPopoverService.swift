// MainApp · AppKitShell · v17.234 · 改 shared 单例 + 独立 chartTooltip 入口
//
// v17.226 原版 → 让全局 .tooltip 走 HoverPopoverModifier · 322 处替换性能崩盘
// v17.233 紧急回退 · InstantTooltip.tooltip() 恢复 .help()
// v17.234 重定位 · 仅 K 线图工具条用 NSPopover 0 延迟提示 · 通过独立 .chartTooltip 调用
//
// 设计要点：
// - shared 单例 NSPopover 复用 · behavior=.transient + animates=false
// - 不依赖 SwiftUI environment 注入 · 进程级共享（与 InstantTooltip 风格一致）
// - HoverPopoverAnchor NSViewRepresentable 单次 makeNSView · 不重建（防 SwiftUI 重渲染累积开销）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// NSPopover 0 延迟悬停提示气泡服务 · shared 单例
@MainActor
final class HoverPopoverService {
    static let shared = HoverPopoverService()

    private let popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
        return p
    }()

    private init() {}

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

/// SwiftUI chart 工具条专用 hover popover modifier · 走 shared service
struct ChartTooltipModifier: ViewModifier {
    let text: String
    @State private var anchor: NSView?

    func body(content: Content) -> some View {
        content
            .background(
                HoverPopoverAnchor { v in anchor = v }
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                if hovering, let a = anchor {
                    HoverPopoverService.shared.show(anchor: a, text: text)
                } else {
                    HoverPopoverService.shared.hide()
                }
            }
    }
}

extension View {
    /// K 线图工具条专用 0 延迟提示气泡 · 仅 ChartScene 工具条调用 · 全 app 其他地方仍用 .tooltip / .help
    /// v17.234 · 替代 v17.226 全局替换（322 处性能崩盘）· 仅 31 处局部应用
    func chartTooltip(_ text: String) -> some View {
        modifier(ChartTooltipModifier(text: text))
    }
}

#endif
