// ChartCore · WP-40 · 时间轴 + 价格刻度（SwiftUI overlay 简化版）
//
// 设计：
// - 纯 SwiftUI · 与 KLineMetalView 通过同一 viewport + bars + priceRange 同步
// - 不走 Metal text 渲染（PoC 阶段过度复杂 · 留 WP-40+ 完整图表引擎）
// - 5 等距标签 · 半透明背景 · 等宽字体 · 视觉风格与 K 线主区协调
//
// 跨平台：canImport(SwiftUI) 包裹 · Linux 端不参编

#if canImport(SwiftUI)

import SwiftUI
import Foundation
import Shared

public struct KLineAxisView: View {

    public enum Orientation: Sendable {
        case time   // 横向 · 底部 · 时间标签
        case price  // 纵向 · 右侧 · 价格标签
    }

    /// 标签数量（视觉密度 · 5 是文华/国信主流）
    public static let labelCount = 5
    /// 时间格式（mock 数据从 1970 起 · 真行情会用 "MM-dd HH:mm" 同款）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let priceRange: ClosedRange<Decimal>
    public let orientation: Orientation

    public init(bars: [KLine], viewport: RenderViewport, priceRange: ClosedRange<Decimal>, orientation: Orientation) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.orientation = orientation
    }

    public var body: some View {
        GeometryReader { geom in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                ForEach(0..<Self.labelCount, id: \.self) { i in
                    Text(label(at: i))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.78))
                        .position(position(at: i, in: geom.size))
                }
            }
        }
    }

    private func label(at i: Int) -> String {
        switch orientation {
        case .time:
            let visible = max(1, viewport.visibleCount)
            let step = visible / max(1, Self.labelCount - 1)
            let idx = min(bars.count - 1, max(0, viewport.startIndex + step * i))
            guard idx >= 0, idx < bars.count else { return "" }
            return Self.timeFormatter.string(from: bars[idx].openTime)
        case .price:
            // 顶 = upperBound · 底 = lowerBound · 5 等分（i=0 最上 · i=4 最下）
            let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
            let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
            let t = Double(Self.labelCount - 1 - i) / Double(max(1, Self.labelCount - 1))
            let value = lo + (hi - lo) * t
            return String(format: "%.1f", value)
        }
    }

    private func position(at i: Int, in size: CGSize) -> CGPoint {
        let t = CGFloat(i) / CGFloat(max(1, Self.labelCount - 1))
        switch orientation {
        case .time:
            return CGPoint(x: t * size.width, y: size.height / 2)
        case .price:
            return CGPoint(x: size.width / 2, y: t * size.height)
        }
    }
}

#endif
