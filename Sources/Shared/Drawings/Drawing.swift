// WP-42 · 画线工具 v1 数据模型 · 6 种
// 趋势线 / 水平线 / 矩形 / 平行通道 / 斐波那契 / 文字
// 数据空间锚点（barIndex + 价格 Decimal），与屏幕坐标解耦；屏幕渲染与像素 hit-test 留给 WP-40 ChartCore

import Foundation

/// 画线类型 v1（Stage A 6 种）· v13.13 椭圆 · v13.14 测量 · v13.17 Pitchfork · v13.31 多边形 = 10 种
public enum DrawingType: String, Sendable, Codable, CaseIterable {
    case trendLine        // 趋势线（两点）
    case horizontalLine   // 水平线（单点价格）
    case rectangle        // 矩形（对角两点）
    case parallelChannel  // 平行通道（两点定主轴 + 偏移定副线）
    case fibonacci        // 斐波那契回调（两点定 0/100%）
    case text             // 文字标注（单点位置）
    case ellipse          // 椭圆（两点定外接矩形对角 · v13.13）
    case ruler            // 测量工具（两点 · 渲染显示价格差/百分比/bar 数 · v13.14）
    case pitchfork        // Andrew's Pitchfork（3 点定中线 · 上下平行 · v13.17）
    case polygon          // 多边形（任意 N≥3 点闭合 · v13.31 · 用户连续点击 + 工具栏"完成"按钮触发）

    /// 完成画线所需的点数 · v13.31 polygon 用 0 表示动态（用户主动触发完成）
    public var pointsNeeded: Int {
        switch self {
        case .horizontalLine, .text: return 1
        case .trendLine, .rectangle, .parallelChannel, .fibonacci, .ellipse, .ruler: return 2
        case .pitchfork: return 3
        case .polygon: return 0  // 0 = 动态点数 · 用户点 N 次后主动触发完成
        }
    }

    /// 是否需要两次点击确定（v1 输入端契约 · 历史 API · 现在用 pointsNeeded == 2 等价）
    public var needsTwoPoints: Bool { pointsNeeded == 2 }
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

    /// v13.11 锁定标志 · true 时拖动 anchor / Delete / ⌘D 都不响应（防误改重要支撑阻力）· nil 视为 false
    public var isLocked: Bool?

    /// v13.12 文字标注字体大小（pt · 仅 .text 类型生效）· nil 用默认 12
    public var fontSize: Double?

    /// v13.15 透明度 0.0~1.0 · nil 用 1.0 · 用于 strokeColor 描边 + 填充共同透明度
    public var strokeOpacity: Double?

    /// v13.17 额外锚点（3 点画线如 Pitchfork 用 [C] · 多边形可扩展用更多）· 兼容老 JSON nil
    public var extraPoints: [DrawingPoint]?

    /// v13.26 文字标注加粗（仅 .text 类型生效）· nil 视为 false
    public var isBold: Bool?

    /// v13.26 文字标注斜体（仅 .text 类型生效）· nil 视为 false
    public var isItalic: Bool?

    public init(
        id: UUID = UUID(),
        type: DrawingType,
        startPoint: DrawingPoint,
        endPoint: DrawingPoint? = nil,
        text: String? = nil,
        channelOffset: Decimal? = nil,
        strokeColorHex: String? = nil,
        strokeWidth: Double? = nil,
        isLocked: Bool? = nil,
        fontSize: Double? = nil,
        strokeOpacity: Double? = nil,
        extraPoints: [DrawingPoint]? = nil,
        isBold: Bool? = nil,
        isItalic: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.text = text
        self.channelOffset = channelOffset
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
        self.isLocked = isLocked
        self.fontSize = fontSize
        self.strokeOpacity = strokeOpacity
        self.extraPoints = extraPoints
        self.isBold = isBold
        self.isItalic = isItalic
    }

    /// v13.11 便利访问 · isLocked nil 视为 false
    public var locked: Bool { isLocked == true }
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

    /// 椭圆（v13.13 · 对角两点定外接矩形 · 内接椭圆 · 顶点未规定顺序）
    public static func ellipse(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .ellipse, startPoint: start, endPoint: end)
    }

    /// 测量工具（v13.14 · 两点定线段 · 渲染时显示价格差 / 百分比 / bar 数）
    public static func ruler(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .ruler, startPoint: start, endPoint: end)
    }

    /// Andrew's Pitchfork（v13.17 · 3 点 · A 中线起点 / B 上轨锚 / C 下轨锚 · 中线方向 = A → midpoint(B,C)）
    public static func pitchfork(handle: DrawingPoint, upper: DrawingPoint, lower: DrawingPoint) -> Drawing {
        Drawing(type: .pitchfork, startPoint: handle, endPoint: upper, extraPoints: [lower])
    }

    /// 多边形（v13.31 · 任意 N≥3 点闭合 · startPoint = 第 1 点 · extraPoints = 第 2~N 点）
    /// 渲染时连接所有点 + 闭合到第 1 点 · 半透明填充
    public static func polygon(points: [DrawingPoint]) -> Drawing? {
        guard points.count >= 3 else { return nil }
        return Drawing(
            type: .polygon,
            startPoint: points[0],
            extraPoints: Array(points.dropFirst())
        )
    }
}
