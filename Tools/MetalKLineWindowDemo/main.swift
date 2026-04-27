// WP-20 Metal K 线 PoC · SwiftUI 真窗口 + zoom/pan 交互 demo
//
// 运行：swift run MetalKLineWindowDemo
//
// 验收 DoD（WP-20 完整 DoD：10w K 60fps + 滚动缩放流畅）：
// - 真窗口 vsync · MTKView 60fps preferredFramesPerSecond
// - trackpad pinch（MagnificationGesture）→ zoom in/out · viewport.visibleCount 实时调整
// - trackpad 单指 / 鼠标拖拽（DragGesture）→ pan · viewport.startIndex 实时调整
// - 10w K 模拟数据 · 默认看末尾 200 根
// - 顶部 HUD 显示当前 visibleCount + startIndex + lastFrameDuration
//
// 跨平台：
// - canImport(Metal) + canImport(AppKit) + canImport(SwiftUI) 包裹
// - Linux 端打印 "Window demo macOS only" 退出 0

#if canImport(Metal) && canImport(AppKit) && canImport(SwiftUI)

import Foundation
import AppKit
import SwiftUI
import Metal
import Shared
import ChartCore

@main
struct MetalKLineWindowDemoApp {

    static func main() {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("⚠️ Metal 不可用 · 退出")
            return
        }
        let renderer: MetalKLineRenderer
        do {
            renderer = try MetalKLineRenderer()
        } catch {
            print("❌ MetalKLineRenderer init 失败：\(error)")
            return
        }
        let bars = generateMockBars(100_000)
        let initialViewport = RenderViewport(
            startIndex: max(0, bars.count - 200),
            visibleCount: 200
        )

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WP-20 · Metal K 线 PoC（pinch zoom · drag pan · 10w K · 60fps）"
        window.center()

        let rootView = ContentView(
            renderer: renderer,
            bars: bars,
            initialViewport: initialViewport
        )
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        app.run()
    }

    // MARK: - 模拟 10w 根 K 数据（random walk · 起价 3000 · ±2 步长）

    static func generateMockBars(_ count: Int, basePrice: Double = 3000) -> [KLine] {
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price = basePrice
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count {
            let drift = Double.random(in: -2...2, using: &rng)
            let open = price
            let close = max(100, price + drift)
            let high = max(open, close) + Double.random(in: 0...3, using: &rng)
            let low = min(open, close) - Double.random(in: 0...3, using: &rng)
            bars.append(KLine(
                instrumentID: "RB",
                period: .minute1,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: 100,
                openInterest: 0,
                turnover: 0
            ))
            price = close
        }
        return bars
    }
}

// MARK: - SwiftUI ContentView · 视口 @State + gesture

struct ContentView: View {

    /// 拖拽灵敏度：每根 K 占屏幕 5 px（约 1280/256）
    static let pixelsPerBar: CGFloat = 5
    /// visibleCount 范围（防止 zoom 越界）
    static let minVisible = 20
    static let maxVisible = 5000

    let renderer: MetalKLineRenderer
    let bars: [KLine]
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?

    init(renderer: MetalKLineRenderer, bars: [KLine], initialViewport: RenderViewport) {
        self.renderer = renderer
        self.bars = bars
        self._viewport = State(initialValue: initialViewport)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 必须 .frame 拉满 · 否则 NSViewRepresentable 默认 zero size → MTKView drawableSize=0 → currentDrawable 永远 nil → 不渲染
            KLineMetalView(
                renderer: renderer,
                input: KLineRenderInput(bars: bars, viewport: viewport)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hud
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let base = dragStartViewport ?? viewport
                    dragStartViewport = base
                    let delta = Int(-value.translation.width / Self.pixelsPerBar)
                    viewport = clamp(base.panned(by: delta))
                }
                .onEnded { _ in dragStartViewport = nil }
        )
        .gesture(
            MagnificationGesture()
                .onChanged { scale in
                    let base = zoomStartViewport ?? viewport
                    zoomStartViewport = base
                    let factor = 1.0 / Double(scale)
                    viewport = clamp(base.zoomed(by: factor))
                }
                .onEnded { _ in zoomStartViewport = nil }
        )
        .task(id: viewport) {
            let stats = await renderer.lastStats
            lastFrameMs = stats.lastFrameDuration * 1000
        }
    }

    var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📊 visible: \(viewport.visibleCount) · start: \(viewport.startIndex) / \(bars.count)")
            Text("⏱️  last frame: \(String(format: "%.2f", lastFrameMs)) ms · budget 16.67 ms")
            Text("🎮 trackpad pinch=zoom · drag=pan")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .padding(12)
    }

    func clamp(_ v: RenderViewport) -> RenderViewport {
        let visible = min(max(Self.minVisible, v.visibleCount), Self.maxVisible)
        let maxStart = max(0, bars.count - visible)
        let start = min(maxStart, max(0, v.startIndex))
        return RenderViewport(startIndex: start, visibleCount: visible)
    }
}

#else

@main
struct MetalKLineWindowDemoApp {
    static func main() {
        print("⚠️  WindowDemo 仅在 macOS 可用（依赖 Metal + AppKit + SwiftUI）· 当前平台跳过")
    }
}

#endif
