// ChartCore · WP-20 SwiftUI ↔ Metal 桥接
//
// 设计要点：
// - NSViewRepresentable 包 MTKView · 让 SwiftUI 上层用 KLineMetalView(renderer:input:) 即可挂图表
// - Coordinator @MainActor 持有最新 input · MTKViewDelegate.draw 拿到 drawable 后**同步**调 renderer.renderToDrawable
//   * MetalKLineRenderer 是 final class @unchecked Sendable + NSLock · 同步调用即可 · 不开 Task / 不跨 actor
//   * draw 阻塞主线程 ~3-5ms（10w K · M2 Pro · 在 16.67ms 帧预算内）· PoC 阶段简化模型
// - PoC 交互（zoom/pan）由调用方 SwiftUI @State 驱动（见 MetalKLineWindowDemo）· KLineMetalView 不持有 viewport 状态
//
// 跨平台约束：
// - canImport(Metal) + canImport(MetalKit) + canImport(SwiftUI) + canImport(AppKit)
// - Linux 端 / iOS 端跳过整文件（M3-M4 iOS 适配时另写 UIViewRepresentable 版本）

#if canImport(Metal) && canImport(MetalKit) && canImport(SwiftUI) && canImport(AppKit)

import Metal
import MetalKit
import SwiftUI
import AppKit

public struct KLineMetalView: NSViewRepresentable {

    /// 深色背景色（Mac 原生终端审美 · #12141A 接近 Xcode dark theme）
    public static let defaultClearColor = MTLClearColorMake(0.07, 0.08, 0.10, 1.0)

    public let renderer: MetalKLineRenderer
    public let input: KLineRenderInput

    public init(renderer: MetalKLineRenderer, input: KLineRenderInput) {
        self.renderer = renderer
        self.input = input
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, input: input)
    }

    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.clearColor = Self.defaultClearColor
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.currentInput = input
    }

    @MainActor
    public final class Coordinator: NSObject, MTKViewDelegate {

        public let renderer: MetalKLineRenderer
        public var currentInput: KLineRenderInput

        init(renderer: MetalKLineRenderer, input: KLineRenderInput) {
            self.renderer = renderer
            self.currentInput = input
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // PoC 不特殊处理 · ortho matrix 自动按 viewport.priceRange/visibleCount 适应
        }

        public func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor else { return }
            renderer.renderToDrawable(
                input: currentInput,
                passDescriptor: passDescriptor,
                drawable: drawable
            )
        }
    }
}

#endif  // canImport(Metal) && canImport(MetalKit) && canImport(SwiftUI) && canImport(AppKit)
