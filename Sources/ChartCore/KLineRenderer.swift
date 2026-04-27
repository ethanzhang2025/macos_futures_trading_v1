// ChartCore · KLineRenderer 协议 + 数据契约
// WP-20 Mac 切机包预埋（v5.0+ · 2026-04-26）：
// - 接口层 Metal-agnostic · Linux 可编译（保持 ChartCore target 跨平台 build 能力）
// - Metal 实现 `MetalKLineRenderer: KLineRenderer` 留 Mac 端写（import Metal/MetalKit）
// - 数据契约 KLineRenderInput / RenderViewport / RenderQuality / RenderStats 跨端共用
//
// 设计取舍：
// - 渲染线程不算指标（靠 IndicatorCore 预算好 IndicatorSeries 通过 input 传入）
// - 不混写 Shader 与 UI 状态：renderer 只负责像素，UI 状态走 SwiftUI @State
// - 视口归一化（0..1 logical · NDC 由 renderer 自己映射）· 与 LayoutFrame 同模式

import Foundation
import Shared
import DataCore
import IndicatorCore

/// 视口（归一化逻辑坐标 · 0..1 范围 · 与平台 NDC 解耦）
public struct RenderViewport: Sendable, Equatable, Hashable, Codable {
    /// 起始 K 线索引（0 = 最早；input.bars 数组下标）
    public var startIndex: Int
    /// 可见 K 线数量（>0 · 决定缩放程度）
    public var visibleCount: Int
    /// Y 轴价格范围（min/max · 让出一定 padding 由 renderer 决定）
    public var priceRange: ClosedRange<Decimal>?
    /// 子 bar 偏移（0..<1 · pixel-precise pan 关键）
    /// pan 时累加浮点 K 数 · 满 1 进位 startIndex · 渲染端 viewMatrix 用 startIndex+startOffset
    /// 让 trackpad 拖拽不依赖 startIndex Int 跳跃 · 视觉连续丝滑
    public var startOffset: Float

    public init(startIndex: Int, visibleCount: Int, priceRange: ClosedRange<Decimal>? = nil, startOffset: Float = 0) {
        self.startIndex = max(0, startIndex)
        self.visibleCount = max(1, visibleCount)
        self.priceRange = priceRange
        self.startOffset = max(0, min(0.999, startOffset))
    }

    /// 平移视口 · 整数 K 数（旧 API · 兼容已有调用）
    public func panned(by delta: Int) -> RenderViewport {
        RenderViewport(startIndex: startIndex + delta, visibleCount: visibleCount, priceRange: priceRange, startOffset: startOffset)
    }

    /// 平移视口 · 浮点 K 数（pixel-precise · sub-bar 偏移自动累加 + 满 1 进位）
    public func pannedSmooth(byBars deltaBars: Float) -> RenderViewport {
        let total = Float(startIndex) + startOffset + deltaBars
        let clamped = max(0, total)
        let newIndex = Int(clamped.rounded(.down))
        let newOffset = clamped - Float(newIndex)
        return RenderViewport(
            startIndex: newIndex,
            visibleCount: visibleCount,
            priceRange: priceRange,
            startOffset: newOffset
        )
    }

    /// 缩放视口（visibleCount × factor · startIndex 围绕中心调整 · startOffset 重置 0）
    public func zoomed(by factor: Double) -> RenderViewport {
        let newCount = max(1, Int(Double(visibleCount) * factor))
        let center = startIndex + visibleCount / 2
        let newStart = max(0, center - newCount / 2)
        return RenderViewport(startIndex: newStart, visibleCount: newCount, priceRange: priceRange)
    }
}

/// 渲染质量档（M6 Pro 订阅可解锁 .ultra · 普通用户 .high · 老 Mac fallback .balanced）
public enum RenderQuality: String, Sendable, Codable, CaseIterable {
    case balanced  // 性价比 · 老 Intel Mac · 抗锯齿 2x
    case high      // 默认 · M1+ · 抗锯齿 4x
    case ultra     // Pro 订阅解锁 · M2 Pro+ · 抗锯齿 8x + 子像素优化
}

/// 渲染输入 · IndicatorCore 预算好的 IndicatorSeries 通过此结构传入（渲染线程不再计算）
public struct KLineRenderInput: Sendable, Equatable {
    public var bars: [KLine]
    /// 叠加指标（已预算 · IndicatorSeries.values 与 bars 等长 · index 对齐）
    public var indicators: [IndicatorSeries]
    public var viewport: RenderViewport
    public var quality: RenderQuality

    public init(bars: [KLine], indicators: [IndicatorSeries] = [], viewport: RenderViewport, quality: RenderQuality = .high) {
        self.bars = bars
        self.indicators = indicators
        self.viewport = viewport
        self.quality = quality
    }
}

/// 渲染统计 · 用于 fps 监控 / Instruments 截图配套数据
public struct RenderStats: Sendable, Equatable, Hashable, Codable {
    /// 单帧 60fps 预算（16.67ms · 1.0 / 60.0）
    public static let frameBudget60fps: TimeInterval = 1.0 / 60.0
    /// 60fps 健康容忍（1ms · 抵消 timer 抖动）
    public static let healthyFrameTolerance: TimeInterval = 0.001

    public var lastFrameDuration: TimeInterval
    public var drawCallCount: Int
    public var visibleBarCount: Int
    public var droppedFrameCount: Int

    public init(lastFrameDuration: TimeInterval = 0, drawCallCount: Int = 0, visibleBarCount: Int = 0, droppedFrameCount: Int = 0) {
        self.lastFrameDuration = lastFrameDuration
        self.drawCallCount = drawCallCount
        self.visibleBarCount = visibleBarCount
        self.droppedFrameCount = droppedFrameCount
    }

    /// 60fps 健康判断（lastFrameDuration <= 16.67ms · 容忍 droppedFrame ≤ 1）
    public var isHealthy60fps: Bool {
        lastFrameDuration <= Self.frameBudget60fps + Self.healthyFrameTolerance && droppedFrameCount <= 1
    }
}

/// K 线渲染器协议 · Metal-agnostic 接口
///
/// 实现方：
/// - **Mac**：`MetalKLineRenderer`（WP-40 · `import Metal` + `import MetalKit` · 切 Mac 后写）
/// - **测试 / Linux 占位**：`NoOpKLineRenderer`（仅记录最近一次 input · 不渲染）
/// - **未来跨平台**：`SoftwareKLineRenderer`（CPU 渲染 · iOS / iPad 备选）
///
/// 线程契约：所有方法 actor-isolated 或 nonisolated（caller 决定）；render(_:) 实际执行在 Metal command queue
public protocol KLineRenderer: Sendable {
    /// 当前渲染质量档
    var quality: RenderQuality { get async }

    /// 设置渲染质量（用户切档 / Pro 订阅状态变化触发）
    func setQuality(_ quality: RenderQuality) async

    /// 提交一帧渲染输入 · 实际绘制在下一个 vsync
    /// - Returns: 本帧渲染统计（fps / drawCall / visibleBars）
    @discardableResult
    func render(_ input: KLineRenderInput) async -> RenderStats

    /// 当前最近一帧统计（fps 监控 / Instruments 配套数据）
    var lastStats: RenderStats { get async }
}

/// 测试 / Linux 占位实现：不渲染像素，仅记录最近一次 input + 模拟统计
public actor NoOpKLineRenderer: KLineRenderer {

    private var _quality: RenderQuality
    private var _lastStats: RenderStats = RenderStats()
    private(set) var lastInput: KLineRenderInput?
    private(set) var renderCount: Int = 0

    public init(quality: RenderQuality = .high) {
        self._quality = quality
    }

    public var quality: RenderQuality { _quality }
    public var lastStats: RenderStats { _lastStats }

    public func setQuality(_ quality: RenderQuality) {
        _quality = quality
    }

    @discardableResult
    public func render(_ input: KLineRenderInput) -> RenderStats {
        lastInput = input
        renderCount += 1
        // 模拟统计：60fps 假数据 · drawCall = visibleBars（每根 K 一个 draw call · 待 Metal 实现合批优化）
        let visible = min(input.viewport.visibleCount, max(0, input.bars.count - input.viewport.startIndex))
        let stats = RenderStats(
            lastFrameDuration: RenderStats.frameBudget60fps,
            drawCallCount: visible,
            visibleBarCount: visible,
            droppedFrameCount: 0
        )
        _lastStats = stats
        return stats
    }
}
