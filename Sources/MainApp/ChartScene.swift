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
import DataCore
import ChartCore
import IndicatorCore

// MARK: - Scene 容器（每窗口独立 state · @State 持有 renderer/bars/indicators）

struct ChartScene: View {

    @State private var renderer: MetalKLineRenderer?
    @State private var bars: [KLine] = []
    @State private var indicators: [IndicatorSeries] = []
    @State private var loadError: String?
    @State private var instrumentLabel: String = "—"
    @State private var periodLabel: String = "—"
    @State private var dataSourceLabel: String = "加载中…"
    @State private var pipeline: MarketDataPipeline?
    @State private var currentInstrumentID: String = MarketDataPipeline.defaultInstrumentID

    var body: some View {
        VStack(spacing: 0) {
            toolbar  // 切换合约 · 始终可见（切换时主区切到 ProgressView 但 toolbar 不消失）
            mainContent
        }
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        // .task(id:) 在 id 变化时自动取消旧 task + 启动新 task · pipeline 资源由 closure 入口手动 stop
        .task(id: currentInstrumentID) {
            await resetForNewContract()
            await loadAndStream(instrumentID: currentInstrumentID)
        }
        .onDisappear {
            Task { await pipeline?.stop() }
        }
    }

    /// 切换合约前重置：停旧管线 + 清空数据 + 重置 HUD label（renderer 不动 · 跨合约复用）
    private func resetForNewContract() async {
        await pipeline?.stop()
        pipeline = nil
        bars = []
        indicators = []
        dataSourceLabel = "加载中…"
        instrumentLabel = currentInstrumentID
    }

    /// 顶部工具条 · 合约 Picker（切换时驱动 .task(id:) 重启 pipeline）
    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("合约：").foregroundColor(.secondary)
            Picker("", selection: $currentInstrumentID) {
                ForEach(MarketDataPipeline.supportedContracts, id: \.self) { sym in
                    Text(sym).tag(sym)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .labelsHidden()
            Spacer()
            Text("⌘N 新窗口 · ⌘L 自选 · ⌘, 设置")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 32)
        // K 线区域 clear color 是 #11141A（≈ white 0.07）· 工具条用 white 0.22 留出明显对比
        .background(Color(white: 0.22))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let renderer, !bars.isEmpty {
            ChartContentView(
                renderer: renderer,
                bars: bars,
                indicators: indicators,
                instrumentLabel: instrumentLabel,
                periodLabel: periodLabel,
                dataSourceLabel: dataSourceLabel,
                initialViewport: RenderViewport(
                    startIndex: max(0, bars.count - 200),
                    visibleCount: 200
                )
            )
        } else if let loadError {
            errorView(loadError)
        } else {
            ProgressView("加载 \(currentInstrumentID) 真行情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 主流程：renderer init（首次）→ pipeline 启动 → 监听 stream 增量更新
    /// 失败兜底：renderer init 抛错 → loadError；首次 snapshot 拉空 → Mock 兜底
    private func loadAndStream(instrumentID: String) async {
        // 1. renderer 仅首次 init（切换合约时复用 · MetalKLineRenderer 与合约无关）
        if renderer == nil {
            do {
                renderer = try await Task.detached(priority: .userInitiated) {
                    try MetalKLineRenderer()
                }.value
            } catch {
                loadError = "渲染器初始化失败：\(error)"
                return
            }
        }

        // 2. 启新 pipeline 拉指定合约真行情
        let pipe = MarketDataPipeline(instrumentID: instrumentID)
        pipeline = pipe
        instrumentLabel = pipe.instrumentID
        periodLabel = pipe.periodLabel
        let stream = await pipe.start()

        // 3. 监听 snapshot + 实时增量
        var snapshotReceived = false
        for await update in stream {
            switch update {
            case .snapshot(let snapBars):
                if snapBars.isEmpty && !snapshotReceived {
                    // 首次 snapshot 拉空 → Sina 不可达 / 节假日 → 回退 Mock
                    await pipe.stop()
                    pipeline = nil
                    await loadMockFallback()
                    return
                }
                snapshotReceived = true
                bars = snapBars
                indicators = await computeIndicatorsAsync(snapBars)
                dataSourceLabel = "Sina 真行情"
            case .completedBar(let k):
                bars.append(k)
                indicators = await computeIndicatorsAsync(bars)
            }
        }
    }

    /// Sina 不可达兜底：5000 根 random walk Mock · 保留用户选的 instrumentLabel · 仅 dataSourceLabel 标 fallback
    private func loadMockFallback() async {
        let result = await Task.detached(priority: .userInitiated) {
            let b = MockKLineData.generateBars(5_000)
            let i = MockKLineData.computeIndicators(bars: b)
            return (b, i)
        }.value
        bars = result.0
        indicators = result.1
        dataSourceLabel = "Sina 不可达 · 已退回 Mock"
    }

    /// 指标计算搬到后台（200 根 ~10ms / 5k 根 ~50ms · 但保持架构一致）
    private func computeIndicatorsAsync(_ snap: [KLine]) async -> [IndicatorSeries] {
        await Task.detached(priority: .userInitiated) {
            MockKLineData.computeIndicators(bars: snap)
        }.value
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
    let instrumentLabel: String
    let periodLabel: String
    let dataSourceLabel: String
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?
    @State var inertiaTask: Task<Void, Never>?

    init(
        renderer: MetalKLineRenderer,
        bars: [KLine],
        indicators: [IndicatorSeries],
        instrumentLabel: String,
        periodLabel: String,
        dataSourceLabel: String,
        initialViewport: RenderViewport
    ) {
        self.renderer = renderer
        self.bars = bars
        self.indicators = indicators
        self.instrumentLabel = instrumentLabel
        self.periodLabel = periodLabel
        self.dataSourceLabel = dataSourceLabel
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
            Text("📌 合约 \(instrumentLabel) · \(periodLabel) · 🌐 \(dataSourceLabel)")
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
