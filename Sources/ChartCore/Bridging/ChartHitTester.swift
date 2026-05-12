// ChartCore · 屏幕像素 ↔ 数据坐标转换 helper（v15.39）
//
// 散落场景统一：
//   1. KLineCrosshairView.computeBarInfo（viewport 模式 · 主图十字光标）
//   2. MultiChartCellCanvas.onContinuousHover（全 bars 均匀模式 · 多图 cell）
//   3. KLineSessionDividerView.xPosition（反向 · bar index → 像素 x）
//   4. SpreadWindow / SpreadBacktestSheet / OptionBacktestSheet 之 Canvas 绘图（反向）
//
// 设计：
//   - 纯函数 · 无状态 · 无副作用 · 无 SwiftUI 依赖（Foundation + CoreGraphics 即可 · 跨平台编译）
//   - 两种坐标模型：
//     * viewport 模式：[startIndex, startIndex+visibleCount) 子区间映射到 [0, width]
//     * full bars 模式：[0, barCount) 均匀映射到 [0, width]
//   - barIndex 反向：返回 bar 中心点（barIndex + 0.5 偏移 · 与渲染对齐）
//   - 价格反向：y=0 顶 = upperBound · y=height 底 = lowerBound（屏幕坐标系 · 与 SwiftUI 默认对齐）
//
// 跨平台：Foundation + CoreGraphics（Linux 端 SwiftPM 自动 stub CGFloat/CGPoint · 可参编）

import Foundation
import Shared
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum ChartHitTester {

    // MARK: - 像素 → bar index（正向 hit-test）

    /// viewport 模式 · 主图带 viewport 的图表用（KLineCrosshairView）
    /// - Parameters:
    ///   - x: 像素横坐标（0 ≤ x ≤ width · 越界自动 clamp）
    ///   - width: 视图宽度
    ///   - viewport: 视口（startIndex / visibleCount · priceRange 不参与）
    ///   - barCount: bars 数组总长度（用于 clamp · 防越界）
    /// - Returns: bar 索引 ∈ [startIndex, min(startIndex+visibleCount, barCount)-1] · barCount=0 返 nil
    public static func barIndex(
        atX x: CGFloat, width: CGFloat,
        viewport: RenderViewport, barCount: Int
    ) -> Int? {
        guard barCount > 0, width > 0 else { return nil }
        let visibleCount = max(1, viewport.visibleCount)
        let xRatio = max(0, min(1, x / width))
        let raw = viewport.startIndex + Int(xRatio * CGFloat(visibleCount))
        let upperLimit = min(viewport.startIndex + visibleCount, barCount) - 1
        let lower = max(0, viewport.startIndex)
        guard upperLimit >= lower else { return nil }
        return min(upperLimit, max(lower, raw))
    }

    /// 全 bars 均匀模式 · MultiChartCellCanvas / SpreadWindow / 期权 PnL 等无 viewport 的图表用
    /// - Returns: bar 索引 ∈ [0, barCount-1] · barCount=0 返 nil
    public static func barIndex(
        atX x: CGFloat, width: CGFloat, barCount: Int
    ) -> Int? {
        guard barCount > 0, width > 0 else { return nil }
        let xRatio = max(0, min(1, x / width))
        return min(barCount - 1, Int(xRatio * CGFloat(barCount)))
    }

    // MARK: - bar index → 像素 x（反向 · 渲染叠加层用）

    /// viewport 模式 · 反向：barIndex → 像素 x（返回 bar 中心点）
    /// - Returns: x ∈ [0, width] · barIndex 不在可视范围返 nil
    public static func xPosition(
        forBarIndex barIndex: Int, width: CGFloat,
        viewport: RenderViewport
    ) -> CGFloat? {
        let visible = max(1, viewport.visibleCount)
        let lo = viewport.startIndex
        guard barIndex >= lo, barIndex < lo + visible else { return nil }
        let xRatio = (CGFloat(barIndex - lo) + 0.5) / CGFloat(visible)
        return xRatio * width
    }

    /// 全 bars 均匀模式 · 反向 · 返回 bar 中心点
    /// - Returns: x ∈ [0, width] · barIndex 越界返 nil
    public static func xPosition(
        forBarIndex barIndex: Int, width: CGFloat, barCount: Int
    ) -> CGFloat? {
        guard barCount > 0, barIndex >= 0, barIndex < barCount else { return nil }
        let xRatio = (CGFloat(barIndex) + 0.5) / CGFloat(barCount)
        return xRatio * width
    }

    /// v17.76 · 时间 → 像素 x（跨周期共振光标定位 · 主图 KLineCrosshairView + 副图 SubChartView 共用）
    /// 找最后一根 openTime ≤ time 的 bar · 走 viewport.xPosition 转 x（不在 viewport 可见区返 nil）
    public static func xPosition(
        forTime time: Date, in bars: [KLine],
        width: CGFloat, viewport: RenderViewport
    ) -> CGFloat? {
        guard !bars.isEmpty,
              let idx = bars.lastIndex(where: { $0.openTime <= time }) else { return nil }
        return xPosition(forBarIndex: idx, width: width, viewport: viewport)
    }

    // MARK: - 像素 y → 价格（屏幕坐标系 · y=0 顶）

    /// y → 价格（Decimal）· 用于 KLineCrosshairView 价位 + 价格轴 hit-test
    /// - Parameters:
    ///   - y: 像素纵坐标（0 ≤ y ≤ height）
    ///   - height: 视图高度
    ///   - priceRange: 价格范围（lowerBound 底 · upperBound 顶 · 屏幕坐标系映射）
    /// - Returns: 价格 · y 越界自动 clamp 到 [lowerBound, upperBound]
    public static func price(
        atY y: CGFloat, height: CGFloat,
        priceRange: ClosedRange<Decimal>
    ) -> Decimal {
        guard height > 0 else { return priceRange.lowerBound }
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let yRatio = 1.0 - max(0, min(1, Double(y / height)))
        return Decimal(lo + (hi - lo) * yRatio)
    }

    /// price → y（反向 · 价格轴标签 / 水平参考线渲染用）
    /// - Returns: y ∈ [0, height] · price 越界 clamp 到 [0, height]
    public static func yPosition(
        forPrice price: Decimal, height: CGFloat,
        priceRange: ClosedRange<Decimal>
    ) -> CGFloat {
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let p = NSDecimalNumber(decimal: price).doubleValue
        guard hi > lo else { return height / 2 }
        let yRatio = 1.0 - max(0, min(1, (p - lo) / (hi - lo)))
        return CGFloat(yRatio) * height
    }

    /// price → y（Double 输入版 · 套利 / 期权 PnL 等纯 Double 量纲用）
    public static func yPosition(
        forPrice price: Double, height: CGFloat,
        priceMin: Double, priceMax: Double
    ) -> CGFloat {
        guard height > 0, priceMax > priceMin else { return height / 2 }
        let yRatio = 1.0 - max(0, min(1, (price - priceMin) / (priceMax - priceMin)))
        return CGFloat(yRatio) * height
    }
}
