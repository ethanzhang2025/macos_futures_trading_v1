// ChartCore · WP-40 · iOS UIViewRepresentable 版 KLineMetalView（与 Mac 版本对称）
//
// 用途：WP-61 iPad 真业务接入（K 线 + 自选 + 套利只读 + 期权 T 型 都用此 view）
//
// 设计要点（与 Mac 版本完全镜像）：
// - UIViewRepresentable 包 MTKView · 让 SwiftUI 上层用 KLineMetalView_iOS(renderer:input:) 即可挂图表
// - Coordinator @MainActor 持有最新 input · MTKViewDelegate.draw 同步调 renderer.renderToDrawable
// - MetalKLineRenderer 同 Mac · 共享同一 Sources/ChartCore/Metal/MetalKLineRenderer.swift
//   * iOS / iPadOS 全部走 GPU 同一管线 · 单 vertex layout 与 shader 共用
// - PoC 交互（zoom/pan）由调用方 SwiftUI @State 驱动 · KLineMetalView_iOS 不持有 viewport 状态
//
// 跨平台约束：
// - canImport(Metal) + canImport(MetalKit) + canImport(SwiftUI) + canImport(UIKit)
// - Mac 端跳过整文件（Mac 走 KLineMetalView · NSViewRepresentable + AppKit）
// - 显式排除 macCatalyst（避免与 Mac 版冲突 · macCatalyst 也算 UIKit）
//
// iPad 性能预期：
// - M1/M2 iPad Pro：10w K 60fps（与 M2 Pro Mac 同水平 · 共享 GPU 架构）
// - 普通 iPad（A14+）：1w K 60fps · 10w K 30-60fps（Pro 订阅卖点 · 与 Mac 一致）

#if canImport(Metal) && canImport(MetalKit) && canImport(SwiftUI) && canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(macOS)

import Metal
import MetalKit
import SwiftUI
import UIKit

public struct KLineMetalView_iOS: UIViewRepresentable {

    /// 深色背景色（与 Mac 版 defaultClearColor 数值完全一致 · iPad 暗黑主题统一）
    public static let defaultClearColor = MTLClearColorMake(0.07, 0.08, 0.10, 1.0)
    /// 浅色背景色（与 Mac lightClearColor 对齐 · iPad 主题切换同步）
    public static let lightClearColor = MTLClearColorMake(0.96, 0.965, 0.972, 1.0)

    public let renderer: MetalKLineRenderer
    public let input: KLineRenderInput
    public let clearColor: MTLClearColor

    public init(
        renderer: MetalKLineRenderer,
        input: KLineRenderInput,
        clearColor: MTLClearColor = defaultClearColor
    ) {
        self.renderer = renderer
        self.input = input
        self.clearColor = clearColor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, input: input)
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.renderer.metalDevice
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 120  // iPad Pro ProMotion 120Hz · 普通 iPad 60Hz
        view.clearColor = clearColor
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]  // UIKit 等价 Mac autoresizingMask
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.currentInput = input
        uiView.clearColor = clearColor  // 主题切换同步
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
            // 与 Mac 版本行为完全一致
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

#endif
