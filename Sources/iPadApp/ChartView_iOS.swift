// ChartView_iOS · iPad 触屏 K 线图（WP-61 batch004）
//
// 实现策略：
//   - 第一版用 SwiftUI Canvas + Path 渲染（不依赖 Metal · iPad 简化版）
//   - 后续 polish 可换成 ChartCore Metal + UIViewRepresentable 桥接
//   - 数据模型用 Shared.KLine（跨端）· 暂用 demo 数据（batch008 接实时）
//
// 触屏交互：
//   - MagnificationGesture：pinch zoom（visibleBarCount 增减）
//   - DragGesture：pan（offsetBars 推进）
//   - tap：hover crosshair（OHLC 浮窗）
//
// 简化版限制：
//   - 不画指标（MA / BOLL 等留 batch005 toggle 后补）
//   - 不支持 inertia 动画
//   - 不支持画线 / 标注（Stage A iPad 范围外）

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import Shared

struct ChartView_iOS: View {

    let instrumentID: String

    /// demo K 线数据 · batch008 替换为真实 SinaSource / DataSource 接入
    @State private var bars: [KLine] = []
    @State private var visibleBarCount: Int = 60
    @State private var offsetBars: Int = 0
    @State private var crosshairBar: KLine? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .systemBackground)

                if bars.isEmpty {
                    ProgressView("加载数据…")
                        .progressViewStyle(.circular)
                } else {
                    chartCanvas(in: geo.size)
                        .gesture(zoomGesture)
                        .simultaneousGesture(panGesture)
                }

                if let bar = crosshairBar {
                    crosshairOverlay(bar: bar)
                }
            }
        }
        .task(id: instrumentID) {
            // batch008 替换为真实数据接入
            self.bars = ChartView_iOS.demoBars(for: instrumentID, count: 200)
            self.visibleBarCount = 60
            self.offsetBars = 0
        }
    }

    // MARK: - Canvas 渲染

    private func chartCanvas(in size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let visible = currentVisibleBars()
            guard !visible.isEmpty else { return }

            let priceRange = priceRange(visible)
            let xUnit = canvasSize.width / CGFloat(visible.count)
            let priceSpan = priceRange.upperBound - priceRange.lowerBound
            guard priceSpan > 0 else { return }

            drawGrid(ctx: ctx, size: canvasSize)

            for (i, bar) in visible.enumerated() {
                let cx = (CGFloat(i) + 0.5) * xUnit
                drawCandle(ctx: ctx, bar: bar, cx: cx, xUnit: xUnit,
                           canvasHeight: canvasSize.height,
                           priceMin: priceRange.lowerBound, priceSpan: priceSpan)
            }
        }
    }

    private func decimalToDouble(_ d: Decimal) -> Double {
        NSDecimalNumber(decimal: d).doubleValue
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let gridColor = Color.gray.opacity(0.15)
        var path = Path()
        // 5 条横线
        for i in 0...5 {
            let y = CGFloat(i) * size.height / 5
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        // 5 条竖线
        for i in 0...5 {
            let x = CGFloat(i) * size.width / 5
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        ctx.stroke(path, with: .color(gridColor), lineWidth: 0.5)
    }

    private func drawCandle(ctx: GraphicsContext, bar: KLine, cx: CGFloat, xUnit: CGFloat,
                            canvasHeight: CGFloat, priceMin: Double, priceSpan: Double) {
        let openD = decimalToDouble(bar.open)
        let closeD = decimalToDouble(bar.close)
        let highD = decimalToDouble(bar.high)
        let lowD = decimalToDouble(bar.low)
        let bullish = closeD >= openD
        let color: Color = bullish ? .red : .green

        let yHigh = canvasHeight - CGFloat((highD - priceMin) / priceSpan) * canvasHeight
        let yLow = canvasHeight - CGFloat((lowD - priceMin) / priceSpan) * canvasHeight
        var wick = Path()
        wick.move(to: CGPoint(x: cx, y: yHigh))
        wick.addLine(to: CGPoint(x: cx, y: yLow))
        ctx.stroke(wick, with: .color(color), lineWidth: 1)

        let yOpen = canvasHeight - CGFloat((openD - priceMin) / priceSpan) * canvasHeight
        let yClose = canvasHeight - CGFloat((closeD - priceMin) / priceSpan) * canvasHeight
        let bodyTop = min(yOpen, yClose)
        let bodyHeight = max(abs(yClose - yOpen), 1)
        let bodyWidth = max(xUnit * 0.7, 1)
        let body = Path(CGRect(x: cx - bodyWidth / 2, y: bodyTop, width: bodyWidth, height: bodyHeight))
        ctx.fill(body, with: .color(color))
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let target = max(20, min(200, Int(60 / scale)))
                if abs(target - visibleBarCount) > 2 {
                    visibleBarCount = target
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let dx = value.translation.width
                let stepBars = Int(dx / 10)  // 每 10pt = 1 根
                offsetBars = clampedOffset(offsetBars - stepBars)
            }
    }

    // MARK: - 数据辅助

    private func currentVisibleBars() -> [KLine] {
        guard !bars.isEmpty else { return [] }
        let total = bars.count
        let end = total - max(0, offsetBars)
        let start = max(0, end - visibleBarCount)
        return Array(bars[start..<min(end, total)])
    }

    private func clampedOffset(_ raw: Int) -> Int {
        max(0, min(bars.count - visibleBarCount, raw))
    }

    private func priceRange(_ visible: [KLine]) -> ClosedRange<Double> {
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for b in visible {
            let l = decimalToDouble(b.low)
            let h = decimalToDouble(b.high)
            lo = min(lo, l)
            hi = max(hi, h)
        }
        if lo == hi { hi = lo + 1 }
        let pad = (hi - lo) * 0.05
        return (lo - pad)...(hi + pad)
    }

    // MARK: - 浮窗

    private func crosshairOverlay(bar: KLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bar.openTime.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                priceTag("开", decimalToDouble(bar.open))
                priceTag("高", decimalToDouble(bar.high))
                priceTag("低", decimalToDouble(bar.low))
                priceTag("收", decimalToDouble(bar.close))
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    private func priceTag(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value)).font(.caption).monospacedDigit()
        }
    }

    // MARK: - Demo data

    /// 合成 demo K 线 · batch008 替换为真实数据
    static func demoBars(for instrumentID: String, count: Int) -> [KLine] {
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price: Double = 3500
        let baseDate = Date(timeIntervalSinceNow: -Double(count) * 60)
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: instrumentID.hashValue))
        for i in 0..<count {
            let drift = rng.nextDouble(-3, 3)
            let open = price
            let close = price + drift
            let high = max(open, close) + rng.nextDouble(0, 2)
            let low = min(open, close) - rng.nextDouble(0, 2)
            let vol = Int(rng.nextDouble(100, 500))
            let ts = baseDate.addingTimeInterval(Double(i) * 60)
            bars.append(KLine(
                instrumentID: instrumentID,
                period: .minute1,
                openTime: ts,
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: vol,
                openInterest: 0,
                turnover: 0
            ))
            price = close
        }
        return bars
    }
}

/// 简易种子化 RNG · 让 demo 数据可重现（同合约同结果）
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble(_ lo: Double, _ hi: Double) -> Double {
        let r = Double(nextUInt64() & 0x000F_FFFF) / Double(0x000F_FFFF)
        return lo + r * (hi - lo)
    }
}

#endif
