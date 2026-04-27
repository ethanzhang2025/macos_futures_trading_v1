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
import IndicatorCore

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
        // MA20 / MA60 通过 IndicatorCore.MA 公开 API 计算（基于 Legacy FormulaEngine 演化的算法）
        let indicators = computeIndicators(bars: bars)
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
        window.title = "WP-20 · Metal K 线 PoC（双指缩放 · 拖拽平移 · 10w K · 60fps）"
        window.contentMinSize = NSSize(width: 800, height: 480)

        let rootView = ContentView(
            renderer: renderer,
            bars: bars,
            indicators: indicators,
            initialViewport: initialViewport
        )
        // NSHostingController 自动处理 SwiftUI ↔ AppKit layout
        window.contentViewController = NSHostingController(rootView: rootView)
        // 强制覆盖 NSHostingController.intrinsicContentSize · 防止窗口被 SwiftUI ContentView 缩成指甲盖
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        app.run()
    }

    // MARK: - 指标计算（IndicatorCore 公开 API · 基于 Legacy FormulaEngine 演化的 MA 算法）

    static func computeIndicators(bars: [KLine]) -> [IndicatorSeries] {
        let series = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        // 5 条不重合的折线（BOLL-MID = MA(20) 完全相同 · 必须过滤避免像素级覆盖）
        let ma5 = (try? MA.calculate(kline: series, params: [5])) ?? []   // 短期 · 黄
        let ma20 = (try? MA.calculate(kline: series, params: [20])) ?? [] // 中期 · 紫
        let ma60 = (try? MA.calculate(kline: series, params: [60])) ?? [] // 长期 · 蓝
        let boll = (try? BOLL.calculate(kline: series, params: [20, 2])) ?? []
        let bollBands = boll.filter { $0.name != "BOLL-MID" }  // 仅保留 UPPER/LOWER（橙 · 粉）
        return ma5 + ma20 + ma60 + bollBands
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

    /// 默认窗口宽度（用于计算 dynamic pixelsPerBar · 让 pan 灵敏度跟随 zoom 自动调整）
    static let assumedViewWidth: CGFloat = 1280
    /// visibleCount 范围（防止 zoom 越界）
    static let minVisible = 20
    static let maxVisible = 5000

    /// 惯性衰减率（每帧）· 0.97 ≈ 2 秒衰减（更接近老代码"轻甩飞远"体验）
    static let inertiaDecayPerFrame: Float = 0.97
    /// 惯性最小速度阈值（K 数 / 帧 · 低于此值停止动画）· 0.02 让轻甩也能触发
    static let inertiaStopThreshold: Float = 0.02
    /// 初始速度分摊帧数（predictedExtraPx / 该值 = 启动速度）· 越小启动越快·轻甩越敏感
    static let inertiaSpreadFrames: Float = 20

    let renderer: MetalKLineRenderer
    let bars: [KLine]
    let indicators: [IndicatorSeries]
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?
    @State var inertiaTask: Task<Void, Never>?

    init(renderer: MetalKLineRenderer, bars: [KLine], indicators: [IndicatorSeries], initialViewport: RenderViewport) {
        self.renderer = renderer
        self.bars = bars
        self.indicators = indicators
        self._viewport = State(initialValue: initialViewport)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                chartMainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                KLineAxisView(bars: bars, viewport: viewport, priceRange: currentPriceRange, orientation: .price)
                    .frame(width: 60)
            }
            KLineAxisView(bars: bars, viewport: viewport, priceRange: currentPriceRange, orientation: .time)
                .frame(height: 28)
        }
        // 让 NSHostingController 知道 ideal 1280x720（防止窗口启动时缩成指甲盖）
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task {
            // 每 100ms 采样 lastStats（render 在每帧 16.67ms 跑 · viewport 不变也要更新 HUD）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let stats = await renderer.lastStats
                lastFrameMs = stats.lastFrameDuration * 1000
            }
        }
    }

    /// 主图区（K 线 + indicators + HUD）· gesture 挂这里 · 让 axis 区域不抢手势
    var chartMainArea: some View {
        ZStack(alignment: .topLeading) {
            KLineMetalView(
                renderer: renderer,
                input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hud
        }
        // simultaneousGesture 让 drag 与 magnification 并行识别 · 不互相覆盖
        // DragGesture(minimumDistance: 0) 起手即响应 · 消除"延迟感"
        // onEnded 启动惯性衰减动画（轻甩飞远 · 像 iPhone Safari 滚动）
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    inertiaTask?.cancel()
                    let base = dragStartViewport ?? viewport
                    dragStartViewport = base
                    let perBar = Self.assumedViewWidth / CGFloat(max(1, base.visibleCount))
                    let deltaBars = Float(-value.translation.width / perBar)
                    viewport = clamp(base.pannedSmooth(byBars: deltaBars))
                }
                .onEnded { value in
                    dragStartViewport = nil
                    let perBar = Self.assumedViewWidth / CGFloat(max(1, viewport.visibleCount))
                    let predictedExtraPx = value.predictedEndTranslation.width - value.translation.width
                    let initialVelocity = Float(-predictedExtraPx / perBar) / Self.inertiaSpreadFrames
                    if abs(initialVelocity) > Self.inertiaStopThreshold {
                        startInertia(velocity: initialVelocity)
                    }
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    inertiaTask?.cancel()
                    let base = zoomStartViewport ?? viewport
                    zoomStartViewport = base
                    let factor = 1.0 / Double(scale)
                    viewport = clamp(base.zoomed(by: factor))
                }
                .onEnded { _ in zoomStartViewport = nil }
        )
    }

    /// 当前 visible 范围价格区间（与 renderer 内部 derivePriceRange 同 fallback 逻辑 · 确保 axis 与 K 线对齐）
    var currentPriceRange: ClosedRange<Decimal> {
        if let r = viewport.priceRange { return r }
        let visible = min(viewport.visibleCount, max(0, bars.count - viewport.startIndex))
        guard visible > 0 else { return Decimal(0)...Decimal(1) }
        let slice = bars[viewport.startIndex..<(viewport.startIndex + visible)]
        let lo = slice.map(\.low).min() ?? Decimal(0)
        let hi = slice.map(\.high).max() ?? Decimal(1)
        return lo...max(hi, lo + Decimal(1))
    }

    var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📊 可见: \(viewport.visibleCount) · 起点: \(viewport.startIndex) / \(bars.count)")
            Text("⏱️  上一帧: \(String(format: "%.2f", lastFrameMs)) ms · 预算 16.67 ms")
            ForEach(Array(indicators.enumerated()), id: \.offset) { idx, series in
                Text("📈 \(series.name): \(latestText(series))")
            }
            Text("🎮 触控板：双指缩放 · 拖拽平移")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .padding(12)
    }

    /// 取 visible window 末位的 indicator 值（HUD 显示与画面 K 线对齐 · 不是全段末位）
    /// 全段 100,000 根 · 用户拖到 99,730 看 200 根 · indicator 末根（99,999）的 MA20 与画面无关
    private func latestText(_ series: IndicatorSeries) -> String {
        let end = min(series.values.count, viewport.startIndex + viewport.visibleCount)
        let prefix = series.values.prefix(end)
        guard let value = prefix.compactMap({ $0 }).last else { return "—" }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    /// 启动惯性滚动动画（onEnded 调 · 速度逐帧衰减直到低于阈值或触底）
    private func startInertia(velocity initialVelocity: Float) {
        inertiaTask?.cancel()
        inertiaTask = Task { @MainActor in
            var v = initialVelocity
            while !Task.isCancelled && abs(v) > Self.inertiaStopThreshold {
                try? await Task.sleep(nanoseconds: 16_666_666)  // 16.67 ms · 60fps · ProMotion 屏自动叠加
                if Task.isCancelled { break }
                let prev = viewport
                viewport = clamp(viewport.pannedSmooth(byBars: v))
                // 触底（边界 clamp 让 viewport 没动）· 立即停止惯性
                if viewport.startIndex == prev.startIndex && viewport.startOffset == prev.startOffset {
                    break
                }
                v *= Self.inertiaDecayPerFrame  // 速度衰减
            }
        }
    }

    func clamp(_ v: RenderViewport) -> RenderViewport {
        let visible = min(max(Self.minVisible, v.visibleCount), Self.maxVisible)
        let maxStart = max(0, bars.count - visible)
        let start = min(maxStart, max(0, v.startIndex))
        // 触底（最末根）时清零 startOffset 防止超出 · 中段保留 sub-bar 偏移
        let offset = (start >= maxStart || start <= 0) ? 0 : v.startOffset
        return RenderViewport(startIndex: start, visibleCount: visible, priceRange: v.priceRange, startOffset: offset)
    }
}

#else

@main
struct MetalKLineWindowDemoApp {
    static func main() {
        print("⚠️  窗口 Demo 仅在 macOS 可用（依赖 Metal + AppKit + SwiftUI）· 当前平台跳过")
    }
}

#endif
