// ChartCore · 视觉迭代第 2 项 · 主图十字光标 + OHLC 浮窗
//
// 设计：
// - macOS onContinuousHover 跟踪鼠标 · 不影响 pan/zoom gesture（事件不互斥 · 但 hover 视觉跟随）
// - 反向计算 hover x → bar index · y → 价格 · 用 viewport.startIndex/visibleCount + priceRange 投影
// - 浮窗显示 OHLC + 量 + 当前 y 对应价位 · 接边时翻转防越界
// - 半透明虚线十字 · 不抢主图视觉

#if canImport(SwiftUI)

import SwiftUI
import Foundation
import Shared

public struct KLineCrosshairView: View {

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let priceRange: ClosedRange<Decimal>

    @State private var hoverPoint: CGPoint?

    /// 时间格式（与 KLineAxisView.timeFormatter 同款）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    public init(bars: [KLine], viewport: RenderViewport, priceRange: ClosedRange<Decimal>) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
    }

    public var body: some View {
        GeometryReader { geom in
            ZStack {
                // 透明 hover 接收层（不挡 K 线 gesture · 仅接受 hover 事件）
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): hoverPoint = pt
                        case .ended: hoverPoint = nil
                        }
                    }

                if let pt = hoverPoint, let info = computeBarInfo(at: pt, in: geom.size) {
                    crosshairLines(at: pt, in: geom.size)
                    OHLCTooltip(
                        time: Self.timeFormatter.string(from: info.bar.openTime),
                        bar: info.bar,
                        cursorPrice: info.cursorPrice
                    )
                    .position(tooltipPosition(at: pt, in: geom.size))
                }
            }
        }
    }

    // MARK: - 私有

    private struct BarInfo {
        let bar: KLine
        let cursorPrice: Decimal
    }

    private func computeBarInfo(at pt: CGPoint, in size: CGSize) -> BarInfo? {
        let visibleCount = max(1, viewport.visibleCount)
        let xRatio = max(0, min(1, pt.x / size.width))
        let barIndex = viewport.startIndex + Int(xRatio * CGFloat(visibleCount))
        guard barIndex >= 0, barIndex < bars.count else { return nil }
        let bar = bars[barIndex]
        // y → price · 顶 0 = upperBound · 底 1 = lowerBound
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let yRatio = 1.0 - max(0, min(1, Double(pt.y / size.height)))
        let priceDouble = lo + (hi - lo) * yRatio
        return BarInfo(bar: bar, cursorPrice: Decimal(priceDouble))
    }

    private func crosshairLines(at pt: CGPoint, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: pt.x, y: 0))
            p.addLine(to: CGPoint(x: pt.x, y: size.height))
        }
        .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        .allowsHitTesting(false)
    }

    /// 浮窗位置：默认鼠标右下偏移 · 接边翻转
    private func tooltipPosition(at pt: CGPoint, in size: CGSize) -> CGPoint {
        let tooltipWidth: CGFloat = 200
        let tooltipHeight: CGFloat = 130
        let dx: CGFloat = pt.x + 12 + tooltipWidth / 2 < size.width
            ? tooltipWidth / 2 + 12
            : -tooltipWidth / 2 - 12
        let dy: CGFloat = pt.y + 12 + tooltipHeight / 2 < size.height
            ? tooltipHeight / 2 + 12
            : -tooltipHeight / 2 - 12
        return CGPoint(x: pt.x + dx, y: pt.y + dy)
    }
}

// MARK: - OHLC 浮窗

private struct OHLCTooltip: View {
    let time: String
    let bar: KLine
    let cursorPrice: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Divider().background(Color.white.opacity(0.2))
            row(label: "开", value: bar.open, color: .white)
            row(label: "高", value: bar.high, color: .red)
            row(label: "低", value: bar.low, color: .green)
            row(label: "收", value: bar.close, color: bar.close >= bar.open ? .red : .green)
            row(label: "量", value: Decimal(bar.volume), color: .gray)
            Divider().background(Color.white.opacity(0.2))
            row(label: "价位", value: cursorPrice, color: .yellow)
        }
        .padding(8)
        .frame(width: 200, alignment: .leading)
        .background(Color.black.opacity(0.85))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
    }

    private func row(label: String, value: Decimal, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 28, alignment: .leading)
            Text(value.description)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color)
            Spacer()
        }
    }
}

#endif
