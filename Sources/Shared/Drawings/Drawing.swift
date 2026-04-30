// WP-42 · 画线工具 v1 数据模型 · 6 种
// 趋势线 / 水平线 / 矩形 / 平行通道 / 斐波那契 / 文字
// 数据空间锚点（barIndex + 价格 Decimal），与屏幕坐标解耦；屏幕渲染与像素 hit-test 留给 WP-40 ChartCore

import Foundation

/// 画线类型 v1（Stage A 6 种）
public enum DrawingType: String, Sendable, Codable, CaseIterable {
    case trendLine        // 趋势线（两点）
    case horizontalLine   // 水平线（单点价格）
    case rectangle        // 矩形（对角两点）
    case parallelChannel  // 平行通道（两点定主轴 + 偏移定副线）
    case fibonacci        // 斐波那契回调（两点定 0/100%）
    case text             // 文字标注（单点位置）

    /// 是否需要两次点击确定（v1 输入端契约）
    public var needsTwoPoints: Bool {
        switch self {
        case .trendLine, .rectangle, .parallelChannel, .fibonacci: return true
        case .horizontalLine, .text: return false
        }
    }
}

/// 数据空间锚点 · K 线索引 + 价格
public struct DrawingPoint: Sendable, Codable, Equatable, Hashable {
    public let barIndex: Int
    public let price: Decimal

    public init(barIndex: Int, price: Decimal) {
        self.barIndex = barIndex
        self.price = price
    }
}

/// 画线对象 · 平铺设计便于 Codable 与序列化
/// 不同 type 用不同字段（startPoint 必填，endPoint / text / channelOffset 按 type 解读）
public struct Drawing: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var type: DrawingType

    /// 起点（所有类型必填）
    public var startPoint: DrawingPoint

    /// 终点（双点画线必填，单点画线为 nil）
    public var endPoint: DrawingPoint?

    /// 文字内容（仅 type == .text 时使用）
    public var text: String?

    /// 平行通道副线相对主轴的价格偏移（仅 type == .parallelChannel 时使用）
    public var channelOffset: Decimal?

    /// v13.8 自定义描边色 6 位 RGB hex（如 "FFC72C"）· nil 用类型默认色 · 老 JSON 缺该字段自动 nil
    public var strokeColorHex: String?

    /// v13.8 自定义线宽（pt）· nil 用 1.5 默认 · 选中态在此基础上 +1.0
    public var strokeWidth: Double?

    public init(
        id: UUID = UUID(),
        type: DrawingType,
        startPoint: DrawingPoint,
        endPoint: DrawingPoint? = nil,
        text: String? = nil,
        channelOffset: Decimal? = nil,
        strokeColorHex: String? = nil,
        strokeWidth: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.text = text
        self.channelOffset = channelOffset
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
    }
}

// MARK: - 类型安全的工厂方法

extension Drawing {
    /// 趋势线：两点定一线段
    public static func trendLine(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .trendLine, startPoint: start, endPoint: end)
    }

    /// 水平线：单点决定一条横跨整图的水平线
    public static func horizontalLine(price: Decimal, barIndex: Int = 0) -> Drawing {
        Drawing(type: .horizontalLine, startPoint: DrawingPoint(barIndex: barIndex, price: price))
    }

    /// 矩形：对角两点定一矩形（顶点未规定顺序，几何辅助会归一化）
    public static func rectangle(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .rectangle, startPoint: start, endPoint: end)
    }

    /// 平行通道：两点定主轴线段 + offset 决定副线在主轴价格方向上的偏移
    public static func parallelChannel(from start: DrawingPoint, to end: DrawingPoint, offset: Decimal) -> Drawing {
        Drawing(type: .parallelChannel, startPoint: start, endPoint: end, channelOffset: offset)
    }

    /// 斐波那契回调：两点定 0%（start.price）与 100%（end.price），其他比例由 fibonacciLevels 推导
    public static func fibonacci(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .fibonacci, startPoint: start, endPoint: end)
    }

    /// 文字标注
    public static func text(at point: DrawingPoint, content: String) -> Drawing {
        Drawing(type: .text, startPoint: point, text: content)
    }
}
