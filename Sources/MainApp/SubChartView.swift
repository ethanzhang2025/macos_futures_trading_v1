// MainApp · 副图区（指数平滑异同移动平均线 MACD · 默认 12/26/9）
//
// 视觉布局：
//   - 零轴：水平虚线居中
//   - MACD 直方：> 0 红柱 / < 0 绿柱（中国期货约定 · 与主图涨跌色一致）
//   - DIF 双线之一：黄色折线（与主图 MA(5) 同色调 · 短期）
//   - DEA 双线之二：紫色折线（与主图 MA(20) 同色调 · 中期）
//   - 迷你信息浮层（HUD）左上：visible 末位的 DIF / DEA / MACD-柱
//
// 性能取舍（Karpathy 1 避免过度复杂）：
//   - 用 SwiftUI Canvas（不上 Metal）· 200 根 × 双线 + 直方 ≈ 600 path op / 帧 · M4 Pro 余量充足
//   - 后续 WP 若要 10w 根级副图再升 Metal pipeline
//
// viewport 共享：副图只读父视图传入的 viewport · 父变即自动重渲染（SwiftUI 标准）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import ChartCore
import IndicatorCore

struct SubChartView: View {

    // 视觉配色（与主图协调 · 涨红跌绿与中国期货约定一致）
    static let bgColor = Color(red: 0.07, green: 0.08, blue: 0.10)        // #11141A 同 K 线 clearColor
    static let zeroLineColor = Color.white.opacity(0.25)
    static let difColor = Color(red: 1.00, green: 0.78, blue: 0.18)       // #FFC72E 黄
    static let deaColor = Color(red: 0.63, green: 0.42, blue: 0.83)       // #A06CD5 紫
    static let bullColor = Color(red: 0.96, green: 0.27, blue: 0.27)      // #F54545 涨红
    static let bearColor = Color(red: 0.18, green: 0.74, blue: 0.42)      // #2DBC6B 跌绿

    let bars: [KLine]
    let viewport: RenderViewport

    @State private var dif: [Decimal?] = []
    @State private var dea: [Decimal?] = []
    @State private var hist: [Decimal?] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.bgColor
            Canvas { context, size in
                drawChart(context: context, size: size)
            }
            hud
        }
        .task(id: bars.count) {
            await computeMACD()
        }
    }

    // MARK: - 迷你信息浮层（HUD）

    private var hud: some View {
        let visibleEnd = min(viewport.startIndex + viewport.visibleCount, bars.count) - 1
        let difLast = lastValue(dif, at: visibleEnd)
        let deaLast = lastValue(dea, at: visibleEnd)
        let histLast = lastValue(hist, at: visibleEnd)
        let histColor = histLast.map { $0 >= 0 ? Self.bullColor : Self.bearColor } ?? .secondary

        return HStack(spacing: 10) {
            Text("MACD 12/26/9").foregroundColor(.secondary)
            Text("DIF \(fmt(difLast))").foregroundColor(Self.difColor)
            Text("DEA \(fmt(deaLast))").foregroundColor(Self.deaColor)
            Text("柱 \(fmt(histLast))").foregroundColor(histColor)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .padding(8)
    }

    // MARK: - MACD 计算（异步 · bars 变化触发）

    @MainActor
    private func computeMACD() async {
        let snap = bars
        let result = await Task.detached(priority: .userInitiated) {
            let series = KLineSeries(
                opens: snap.map(\.open),
                highs: snap.map(\.high),
                lows: snap.map(\.low),
                closes: snap.map(\.close),
                volumes: snap.map(\.volume),
                openInterests: snap.map { _ in 0 }
            )
            return (try? MACD.calculate(kline: series, params: [12, 26, 9])) ?? []
        }.value
        dif = result.first { $0.name == "DIF" }?.values ?? []
        dea = result.first { $0.name == "DEA" }?.values ?? []
        hist = result.first { $0.name == "MACD" }?.values ?? []
    }

    // MARK: - Canvas 绘制

    private func drawChart(context: GraphicsContext, size: CGSize) {
        let visibleStart = viewport.startIndex
        let visibleCount = viewport.visibleCount
        let visibleEnd = min(visibleStart + visibleCount, bars.count)
        guard visibleEnd > visibleStart else { return }

        // y 范围：visible 内 |DIF / DEA / 柱| 最大值 · 上下对称（零轴居中）· 留 10% 边距
        var maxAbs: Double = 0.01
        for i in visibleStart..<visibleEnd {
            for arr in [dif, dea, hist] {
                if i < arr.count, let v = arr[i] {
                    let d = abs(NSDecimalNumber(decimal: v).doubleValue)
                    if d > maxAbs { maxAbs = d }
                }
            }
        }
        let yScale = (size.height / 2) * 0.9 / CGFloat(maxAbs)
        let yCenter = size.height / 2
        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)

        drawZeroLine(context: context, size: size, yCenter: yCenter)
        drawHistogram(context: context, visibleStart: visibleStart, visibleEnd: visibleEnd,
                      barWidth: barWidth, xOffset: xOffset, yCenter: yCenter, yScale: yScale)
        drawLine(values: dif, color: Self.difColor, context: context,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset, yCenter: yCenter, yScale: yScale)
        drawLine(values: dea, color: Self.deaColor, context: context,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset, yCenter: yCenter, yScale: yScale)
    }

    private func drawZeroLine(context: GraphicsContext, size: CGSize, yCenter: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: yCenter))
        path.addLine(to: CGPoint(x: size.width, y: yCenter))
        context.stroke(path, with: .color(Self.zeroLineColor),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func drawHistogram(
        context: GraphicsContext, visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat, yCenter: CGFloat, yScale: CGFloat
    ) {
        for i in visibleStart..<visibleEnd {
            guard i < hist.count, let v = hist[i] else { continue }
            let value = CGFloat(NSDecimalNumber(decimal: v).doubleValue)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let yTop = yCenter - value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: min(yTop, yCenter),
                width: barWidth * 0.6,
                height: abs(yTop - yCenter)
            )
            context.fill(Path(rect), with: .color(value >= 0 ? Self.bullColor : Self.bearColor))
        }
    }

    private func drawLine(
        values: [Decimal?], color: Color, context: GraphicsContext,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat, yCenter: CGFloat, yScale: CGFloat
    ) {
        var path = Path()
        var moved = false
        for i in visibleStart..<visibleEnd {
            guard i < values.count, let v = values[i] else { continue }
            let value = CGFloat(NSDecimalNumber(decimal: v).doubleValue)
            let x = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let y = yCenter - value * yScale
            if !moved {
                path.move(to: CGPoint(x: x, y: y))
                moved = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - 工具

    private func lastValue(_ values: [Decimal?], at end: Int) -> Decimal? {
        guard end >= 0, !values.isEmpty else { return nil }
        let safeEnd = min(end, values.count - 1)
        return values.prefix(safeEnd + 1).reversed().compactMap { $0 }.first
    }

    private func fmt(_ v: Decimal?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f", NSDecimalNumber(decimal: v).doubleValue)
    }
}

#endif
