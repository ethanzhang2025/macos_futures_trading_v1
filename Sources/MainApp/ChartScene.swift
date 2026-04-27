// MainApp · K 线图表 Scene（WindowGroup 内容）
//
// 职责：
// - 每个 WindowGroup 实例独立初始化 renderer / bars / indicators（Cmd+N 多窗口隔离）
// - 复用 demo 的 ContentView 5 indicator + 双轴 + 拖拽 + 缩放 + 惯性体验
// - 留口：bars 来源后续接 WP-44c MarketDataProvider；现在用 MockData 占位

#if canImport(SwiftUI) && os(macOS)

import Foundation
import SwiftUI
import Metal
import Shared
import ChartCore
import IndicatorCore

// MARK: - Scene 容器（每窗口独立 state · @State 持有 renderer/bars/indicators）

struct ChartScene: View {

    @State private var renderer: MetalKLineRenderer?
    @State private var bars: [KLine] = []
    @State private var indicators: [IndicatorSeries] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let renderer, !bars.isEmpty {
                ChartContentView(
                    renderer: renderer,
                    bars: bars,
                    indicators: indicators,
                    initialViewport: RenderViewport(
                        startIndex: max(0, bars.count - 200),
                        visibleCount: 200
                    )
                )
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView("加载行情数据…")
            }
        }
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task {
            // 重活全部搬到 Task.detached · 不阻塞 MainActor / NSWindow 创建
            // 否则 ⌘N 新建窗口要等 generateBars+computeIndicators ~1-3s 才弹出
            do {
                // 5000 根足够展示视觉密度（Decimal 算术约束 10w 根需 ~1.9s · 5k 仅 ~100ms）
                // 真 App 接行情后从 SQLite 加载历史 K · 不再走这条 mock 路径
                let result = try await Task.detached(priority: .userInitiated) {
                    let r = try MetalKLineRenderer()
                    let b = MockKLineData.generateBars(5_000)
                    let i = MockKLineData.computeIndicators(bars: b)
                    return (r, b, i)
                }.value
                renderer = result.0
                bars = result.1
                indicators = result.2
            } catch {
                loadError = "\(error)"
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("❌ 渲染器初始化失败").font(.headline)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 图表内容视图（复用 demo · 5 indicator 折线 + 时间轴 + 价格刻度 + 惯性滚动）

struct ChartContentView: View {

    /// 默认窗口宽度（用于计算 dynamic pixelsPerBar · 让 pan 灵敏度跟随 zoom 自动调整）
    static let assumedViewWidth: CGFloat = 1280
    /// visibleCount 范围（防止 zoom 越界）
    static let minVisible = 20
    static let maxVisible = 5000

    /// 惯性衰减率（每帧）· 0.97 ≈ 2 秒衰减
    static let inertiaDecayPerFrame: Float = 0.97
    /// 最小速度阈值（K 数 / 帧 · 低于停止）
    static let inertiaStopThreshold: Float = 0.02
    /// 初始速度分摊帧数
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
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let stats = await renderer.lastStats
                lastFrameMs = stats.lastFrameDuration * 1000
            }
        }
    }

    /// 主图区（K 线 + indicators + HUD · gesture 挂这里）
    var chartMainArea: some View {
        ZStack(alignment: .topLeading) {
            KLineMetalView(
                renderer: renderer,
                input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hud
        }
        .simultaneousGesture(panGesture)
        .simultaneousGesture(zoomGesture)
    }

    /// 拖拽平移 + 松手惯性滑行
    private var panGesture: some Gesture {
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
    }

    /// 双指捏合缩放（visibleCount 反向缩放）
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                inertiaTask?.cancel()
                let base = zoomStartViewport ?? viewport
                zoomStartViewport = base
                let factor = 1.0 / Double(scale)
                viewport = clamp(base.zoomed(by: factor))
            }
            .onEnded { _ in zoomStartViewport = nil }
    }

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
            ForEach(Array(indicators.enumerated()), id: \.offset) { _, series in
                Text("📈 \(series.name): \(latestText(series))")
            }
            Text("🎮 触控板：双指缩放 · 拖拽平移 · ⌘N 新窗口")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .padding(12)
    }

    /// 取 visible window 末位的 indicator 值（与画面对齐 · 不取全段末位）
    private func latestText(_ series: IndicatorSeries) -> String {
        let end = min(series.values.count, viewport.startIndex + viewport.visibleCount)
        let prefix = series.values.prefix(end)
        guard let value = prefix.compactMap({ $0 }).last else { return "—" }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    /// 惯性滚动（onEnded 调 · 速度逐帧衰减直到低于阈值或触底）
    private func startInertia(velocity initialVelocity: Float) {
        inertiaTask?.cancel()
        inertiaTask = Task { @MainActor in
            var v = initialVelocity
            while !Task.isCancelled && abs(v) > Self.inertiaStopThreshold {
                try? await Task.sleep(nanoseconds: 16_666_666)
                if Task.isCancelled { break }
                let prev = viewport
                viewport = clamp(viewport.pannedSmooth(byBars: v))
                if viewport.startIndex == prev.startIndex && viewport.startOffset == prev.startOffset {
                    break
                }
                v *= Self.inertiaDecayPerFrame
            }
        }
    }

    func clamp(_ v: RenderViewport) -> RenderViewport {
        let visible = min(max(Self.minVisible, v.visibleCount), Self.maxVisible)
        let maxStart = max(0, bars.count - visible)
        let start = min(maxStart, max(0, v.startIndex))
        let offset = (start >= maxStart || start <= 0) ? 0 : v.startOffset
        return RenderViewport(startIndex: start, visibleCount: visible, priceRange: v.priceRange, startOffset: offset)
    }
}

// MARK: - Mock 数据（spike 阶段占位 · 后续 WP 接 MarketDataProvider）

enum MockKLineData {

    static func generateBars(_ count: Int, basePrice: Double = 3000) -> [KLine] {
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

    /// 5 条不重合：MA(5) + MA(20) + MA(60) + BOLL UPPER + BOLL LOWER（过滤 BOLL-MID = MA(20)）
    static func computeIndicators(bars: [KLine]) -> [IndicatorSeries] {
        let series = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        let ma5 = (try? MA.calculate(kline: series, params: [5])) ?? []
        let ma20 = (try? MA.calculate(kline: series, params: [20])) ?? []
        let ma60 = (try? MA.calculate(kline: series, params: [60])) ?? []
        let boll = (try? BOLL.calculate(kline: series, params: [20, 2])) ?? []
        let bollBands = boll.filter { $0.name != "BOLL-MID" }
        return ma5 + ma20 + ma60 + bollBands
    }
}

#endif
