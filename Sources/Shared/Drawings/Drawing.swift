// WP-42 · 画线工具 v1 数据模型 · 6 种
// 趋势线 / 水平线 / 矩形 / 平行通道 / 斐波那契 / 文字
// 数据空间锚点（barIndex + 价格 Decimal），与屏幕坐标解耦；屏幕渲染与像素 hit-test 留给 WP-40 ChartCore

import Foundation

/// 画线类型 v1（Stage A 6 种）· v13.13 椭圆 · v13.14 测量 · v13.17 Pitchfork · v13.31 多边形 · v15.87 斐波那契扇形 · v15.88 价格区域 · v15.89 江恩扇形 · v15.90 斐波那契时间区 · v17.8 垂直线 · v17.10 射线 · v17.11 通道线 · v17.14 箭头 · v17.15 价格标签 · v17.16 斐波扩展 = 20 种
public enum DrawingType: String, Sendable, Codable, CaseIterable {
    case trendLine          // 趋势线（两点）
    case horizontalLine     // 水平线（单点价格）
    case verticalLine       // 垂直线（单点 · 时间锚点 · 横跨全价格 · v17.8 A3.4）
    case priceLabel         // 价格标签（v17.15 A5.3 · 单点 · 水平虚线 + 右侧醒目价格 chip · 关键支撑/阻力快速标）
    case ray                // 射线（两点定方向 · 从 start 经 end 延伸到画布边界 · v17.10 A3.2）
    case arrow              // 箭头（v17.14 A5.2 · 两点定方向 · start → end + 实心三角箭头头 · 信号标记）
    case rectangle          // 矩形（对角两点）
    case parallelChannel    // 平行通道（两点定主轴 + 偏移定副线）
    case channel            // 通道线（v17.11 A3.1 · 两点定 bar 范围 · 内部线性回归 + ±1σ 平行线 · 自动等距）
    case fibonacci          // 斐波那契回调（两点定 0/100%）
    case fibonacciExtension // 斐波扩展（v17.16 A4.1 · 两点定 0/100% · 外推到 1.272/1.414/1.618/2/2.618 · 突破后目标位）
    case text               // 文字标注（单点位置）
    case ellipse            // 椭圆（两点定外接矩形对角 · v13.13）
    case ruler              // 测量工具（两点 · 渲染显示价格差/百分比/bar 数 · v13.14）
    case pitchfork          // Andrew's Pitchfork（3 点定中线 · 上下平行 · v13.17）
    case polygon            // 多边形（任意 N≥3 点闭合 · v13.31 · 用户连续点击 + 工具栏"完成"按钮触发）
    case fibonacciFan       // 斐波那契扇形（v15.87 · 两点定 0/100% · 从 start 发射 3 条核心 fib 射线 38.2%/50%/61.8%）
    case priceZone          // 价格区域（v15.88 · 两点定上下价格 · 全图横跨 · 半透明填充 · 关键支撑/阻力带）
    case gannFan            // 江恩扇形（v15.89 · 两点定 1×1 单位 · 从 start 发射 9 角度射线 1×8/1×4/1×3/1×2/1×1/2×1/3×1/4×1/8×1）
    case fibonacciTimeZone  // 斐波那契时间区（v15.90 · 两点定 1 fib 时间间隔 · 8 条全图垂直线 F1/F2/F3/F5/F8/F13/F21/F34）

    /// 完成画线所需的点数 · v13.31 polygon 用 0 表示动态（用户主动触发完成）
    public var pointsNeeded: Int {
        switch self {
        case .horizontalLine, .verticalLine, .priceLabel, .text: return 1
        case .trendLine, .ray, .arrow, .rectangle, .parallelChannel, .channel, .fibonacci, .fibonacciExtension, .fibonacciFan, .ellipse, .ruler, .priceZone, .gannFan, .fibonacciTimeZone: return 2
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

    /// v13.35 文字标注下划线（仅 .text 类型生效）· nil 视为 false
    public var isUnderline: Bool?

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
        isItalic: Bool? = nil,
        isUnderline: Bool? = nil
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
        self.isUnderline = isUnderline
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

    /// 垂直线（v17.8 A3.4 · 时间锚点 · 单点决定一条横跨整价格的垂直线 · price 任意 · barIndex 决定位置）
    public static func verticalLine(barIndex: Int, price: Decimal = 0) -> Drawing {
        Drawing(type: .verticalLine, startPoint: DrawingPoint(barIndex: barIndex, price: price))
    }

    /// 射线（v17.10 A3.2 · 两点定方向 · 从 start 出发经 end 延伸到画布边界 · 半线）
    public static func ray(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .ray, startPoint: start, endPoint: end)
    }

    /// 通道线（v17.11 A3.1 · 两点 barIndex 定 range · 价格忽略 · 内部线性回归 + ±1σ 平行线 · 自动等距）
    public static func channel(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .channel, startPoint: start, endPoint: end)
    }

    /// 箭头（v17.14 A5.2 · 两点定方向 · 末端三角箭头头 · 信号标记 / 复盘标注）
    public static func arrow(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .arrow, startPoint: start, endPoint: end)
    }

    /// 价格标签（v17.15 A5.3 · 单点 · 水平虚线 + 右侧填充 chip 显示价格 · 可选文字 label）
    public static func priceLabel(price: Decimal, barIndex: Int = 0, label: String? = nil) -> Drawing {
        Drawing(type: .priceLabel, startPoint: DrawingPoint(barIndex: barIndex, price: price), text: label)
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

    /// 斐波扩展（v17.16 A4.1 · 突破后目标位 · 两点定 0/100% · 外推到 1.272/1.414/1.618/2/2.618）
    public static func fibonacciExtension(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .fibonacciExtension, startPoint: start, endPoint: end)
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

    /// 斐波那契扇形（v15.87 · 两点定 0%（start）/ 100%（end）· 从 start 发射 3 条核心 fib 射线 38.2/50/61.8）
    public static func fibonacciFan(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .fibonacciFan, startPoint: start, endPoint: end)
    }

    /// 价格区域（v15.88 · 两点定上下价格 · 全图横跨 · 半透明填充 · barIndex 仅作锚点 · 渲染忽略）
    public static func priceZone(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .priceZone, startPoint: start, endPoint: end)
    }

    /// 江恩扇形（v15.89 · 两点定 1×1 单位（dx bar = dy price）· 9 角度射线从 start 发射）
    public static func gannFan(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .gannFan, startPoint: start, endPoint: end)
    }

    /// 斐波那契时间区（v15.90 · 两点定 1 fib 时间间隔 dx · 8 条全图垂直线在 start + dx × [1,2,3,5,8,13,21,34]）
    public static func fibonacciTimeZone(from start: DrawingPoint, to end: DrawingPoint) -> Drawing {
        Drawing(type: .fibonacciTimeZone, startPoint: start, endPoint: end)
    }
}
