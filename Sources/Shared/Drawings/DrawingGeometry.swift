// WP-42 · 画线几何辅助 · 数据空间几何计算
// 这里只做"数据坐标系"的几何（barIndex 视为 X，price 视为 Y），单位非同质 → tolerance 由调用方按当前缩放传入
// 真正的"屏幕像素 hit-test"在 WP-40 ChartCore 实现（屏幕坐标系下点距 ≤ 像素阈值）

import Foundation

public enum FibonacciLevels {
    /// 标准斐波那契回调比例（0%、23.6%、38.2%、50%、61.8%、78.6%、100%）
    public static let standard: [Decimal] = [
        0,
        Decimal(string: "0.236")!,
        Decimal(string: "0.382")!,
        Decimal(string: "0.5")!,
        Decimal(string: "0.618")!,
        Decimal(string: "0.786")!,
        1
    ]

    /// 扩展位（含 1.272 / 1.618 / 2.618，给 WP-40 渲染时可选）
    public static let extended: [Decimal] = standard + [
        Decimal(string: "1.272")!,
        Decimal(string: "1.618")!,
        Decimal(string: "2.618")!
    ]
}

public enum DrawingGeometry {

    /// 斐波那契回调线的价格序列
    /// - Parameters:
    ///   - drawing: type 必须为 .fibonacci
    ///   - levels: 比例集合（默认 standard 7 档）
    /// - Returns: 与 levels 同长的价格数组；非 fibonacci 类型或缺 endPoint 返回空
    public static func fibonacciPrices(for drawing: Drawing, levels: [Decimal] = FibonacciLevels.standard) -> [Decimal] {
        guard drawing.type == .fibonacci, let end = drawing.endPoint else { return [] }
        let p0 = drawing.startPoint.price
        let p1 = end.price
        let span = p1 - p0
        return levels.map { p0 + span * $0 }
    }

    /// 矩形归一化（保证 min/max 顺序）
    public static func rectangleBounds(of drawing: Drawing) -> (minBar: Int, maxBar: Int, minPrice: Decimal, maxPrice: Decimal)? {
        guard drawing.type == .rectangle, let end = drawing.endPoint else { return nil }
        let s = drawing.startPoint
        return (
            minBar: min(s.barIndex, end.barIndex),
            maxBar: max(s.barIndex, end.barIndex),
            minPrice: min(s.price, end.price),
            maxPrice: max(s.price, end.price)
        )
    }

    /// 矩形是否包含某点（数据空间）
    public static func rectangle(_ drawing: Drawing, contains barIndex: Int, price: Decimal) -> Bool {
        guard let b = rectangleBounds(of: drawing) else { return false }
        return barIndex >= b.minBar && barIndex <= b.maxBar
            && price >= b.minPrice && price <= b.maxPrice
    }

    /// 水平线在指定 barIndex 处的价格（即 startPoint.price，水平线全图同价）
    public static func horizontalPrice(of drawing: Drawing) -> Decimal? {
        guard drawing.type == .horizontalLine else { return nil }
        return drawing.startPoint.price
    }

    /// 趋势线 / 平行通道主轴 在指定 barIndex 处插值得到的价格
    /// 两点之外的 barIndex 按线段所在直线外推
    /// - Returns: 仅 trendLine / parallelChannel 类型且 endPoint 存在时有值
    public static func linePrice(of drawing: Drawing, atBar barIndex: Int) -> Decimal? {
        guard drawing.type == .trendLine || drawing.type == .parallelChannel,
              let end = drawing.endPoint else { return nil }
        let s = drawing.startPoint
        // 端点同 barIndex → 退化为水平线
        if s.barIndex == end.barIndex { return s.price }
        let dx = Decimal(end.barIndex - s.barIndex)
        let dy = end.price - s.price
        return s.price + dy * Decimal(barIndex - s.barIndex) / dx
    }

    /// 平行通道副线在指定 barIndex 处的价格（主轴 + offset）
    public static func channelOffsetPrice(of drawing: Drawing, atBar barIndex: Int) -> Decimal? {
        guard drawing.type == .parallelChannel,
              let main = linePrice(of: drawing, atBar: barIndex),
              let offset = drawing.channelOffset else { return nil }
        return main + offset
    }

    /// 数据空间内点到趋势线的"价格方向距离"（绝对值）· 简易 hit-test
    /// 真正的屏幕 hit 由 WP-40 转换屏幕坐标后做欧氏距离
    public static func priceDistance(from drawing: Drawing, atBar barIndex: Int, price: Decimal) -> Decimal? {
        guard let onLine = linePrice(of: drawing, atBar: barIndex) else { return nil }
        return abs(onLine - price)
    }
}
