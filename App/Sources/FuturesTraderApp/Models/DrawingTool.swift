import SwiftUI

/// 绘图工具类型
enum DrawingToolType: String, CaseIterable {
    case none = "无"
    // 线条类
    case trendLine = "趋势线"
    case ray = "射线"
    case horizontalLine = "水平线"
    case verticalLine = "垂直线"
    // 区域类
    case parallelChannel = "平行通道"
    case rectangle = "矩形"
    // 分析类
    case fibonacci = "斐波那契"
    // 标注类
    case arrow = "箭头"
    case text = "文字"

    /// 需要两次点击的工具
    var needsTwoClicks: Bool {
        switch self {
        case .trendLine, .ray, .parallelChannel, .rectangle, .fibonacci: return true
        case .horizontalLine, .verticalLine, .arrow, .text, .none: return false
        }
    }

    /// 分组（用于菜单）
    static let lineTools: [DrawingToolType] = [.trendLine, .ray, .horizontalLine, .verticalLine]
    static let areaTools: [DrawingToolType] = [.parallelChannel, .rectangle, .fibonacci]
    static let annotationTools: [DrawingToolType] = [.arrow, .text]
}

/// 绘图对象
struct DrawingObject: Identifiable, Equatable {
    let id = UUID()
    let type: DrawingToolType
    var startIndex: Int
    var startPrice: Double
    var endIndex: Int
    var endPrice: Double
    var color: Color
    var isSelected: Bool = false
    /// 平行通道宽度（价格单位）
    var channelWidth: Double = 0
    /// 文字内容
    var label: String = ""
    /// 文字框宽度（像素）
    var boxWidth: CGFloat = 200
    /// 文字框高度（像素）
    var boxHeight: CGFloat = 60

    static func == (lhs: DrawingObject, rhs: DrawingObject) -> Bool { lhs.id == rhs.id }

    static func horizontal(price: Double, index: Int) -> DrawingObject {
        DrawingObject(type: .horizontalLine, startIndex: index, startPrice: price, endIndex: index, endPrice: price, color: .yellow)
    }
    static func vertical(index: Int, price: Double) -> DrawingObject {
        DrawingObject(type: .verticalLine, startIndex: index, startPrice: price, endIndex: index, endPrice: price, color: .yellow)
    }
    static func trend(si: Int, sp: Double, ei: Int, ep: Double) -> DrawingObject {
        DrawingObject(type: .trendLine, startIndex: si, startPrice: sp, endIndex: ei, endPrice: ep, color: .orange)
    }
    static func ray(si: Int, sp: Double, ei: Int, ep: Double) -> DrawingObject {
        DrawingObject(type: .ray, startIndex: si, startPrice: sp, endIndex: ei, endPrice: ep, color: .orange)
    }
    static func fib(si: Int, sp: Double, ei: Int, ep: Double) -> DrawingObject {
        DrawingObject(type: .fibonacci, startIndex: si, startPrice: sp, endIndex: ei, endPrice: ep, color: Color(red: 0.8, green: 0.6, blue: 0.2))
    }
    static func channel(si: Int, sp: Double, ei: Int, ep: Double, width: Double) -> DrawingObject {
        DrawingObject(type: .parallelChannel, startIndex: si, startPrice: sp, endIndex: ei, endPrice: ep, color: Color(red: 0.3, green: 0.7, blue: 1.0), channelWidth: width)
    }
    static func rect(si: Int, sp: Double, ei: Int, ep: Double) -> DrawingObject {
        DrawingObject(type: .rectangle, startIndex: si, startPrice: sp, endIndex: ei, endPrice: ep, color: Color(red: 0.5, green: 0.8, blue: 0.5))
    }
    static func arrowMark(index: Int, price: Double) -> DrawingObject {
        DrawingObject(type: .arrow, startIndex: index, startPrice: price, endIndex: index, endPrice: price, color: .red)
    }
    static func textMark(index: Int, price: Double, text: String) -> DrawingObject {
        DrawingObject(type: .text, startIndex: index, startPrice: price, endIndex: index, endPrice: price, color: .white, label: text)
    }
}

/// 斐波那契回撤线配置
enum FibonacciLevels {
    static let levels: [(ratio: Double, label: String)] = [
        (0.0, "0%"), (0.236, "23.6%"), (0.382, "38.2%"),
        (0.5, "50%"), (0.618, "61.8%"), (0.786, "78.6%"), (1.0, "100%"),
    ]
    static let extLevels: [(ratio: Double, label: String)] = [
        (1.272, "127.2%"), (1.618, "161.8%"),
    ]
    static let colors: [Color] = [
        Color(red: 0.8, green: 0.4, blue: 0.4),  // 0%
        Color(red: 0.8, green: 0.6, blue: 0.3),  // 23.6%
        Color(red: 0.8, green: 0.7, blue: 0.2),  // 38.2%
        Color(red: 0.3, green: 0.8, blue: 0.3),  // 50%
        Color(red: 0.2, green: 0.7, blue: 0.8),  // 61.8%
        Color(red: 0.5, green: 0.5, blue: 0.9),  // 78.6%
        Color(red: 0.8, green: 0.4, blue: 0.7),  // 100%
    ]
}

/// 绘图状态管理
class DrawingState: ObservableObject {
    @Published var activeTool: DrawingToolType = .none
    @Published var objects: [DrawingObject] = []
    @Published var tempStartIndex: Int?
    @Published var tempStartPrice: Double?

    var isDrawing: Bool { activeTool != .none }

    func startTool(_ tool: DrawingToolType) {
        activeTool = tool; tempStartIndex = nil; tempStartPrice = nil
    }

    func cancelDrawing() {
        activeTool = .none; tempStartIndex = nil; tempStartPrice = nil
    }

    func addObject(_ obj: DrawingObject) {
        objects.append(obj); activeTool = .none; tempStartIndex = nil; tempStartPrice = nil
    }

    func deleteSelected() { objects.removeAll { $0.isSelected } }
    func deselectAll() { for i in objects.indices { objects[i].isSelected = false } }
    func clearAll() { objects.removeAll() }

    func selectNearby(index: Int, price: Double, tolerance: Double) -> Bool {
        deselectAll()
        for i in objects.indices {
            let obj = objects[i]
            switch obj.type {
            case .horizontalLine:
                if abs(obj.startPrice - price) < tolerance { objects[i].isSelected = true; return true }
            case .verticalLine:
                if abs(Double(obj.startIndex - index)) < 2 { objects[i].isSelected = true; return true }
            case .trendLine, .ray:
                if distToLine(idx: index, price: price, obj: obj) < tolerance { objects[i].isSelected = true; return true }
            case .fibonacci, .rectangle, .parallelChannel:
                let minP = min(obj.startPrice, obj.endPrice), maxP = max(obj.startPrice, obj.endPrice)
                let minI = min(obj.startIndex, obj.endIndex), maxI = max(obj.startIndex, obj.endIndex)
                if index >= minI && index <= maxI && price >= minP - tolerance && price <= maxP + tolerance {
                    objects[i].isSelected = true; return true
                }
            case .arrow, .text:
                if abs(Double(obj.startIndex - index)) < 2 && abs(obj.startPrice - price) < tolerance {
                    objects[i].isSelected = true; return true
                }
            case .none: break
            }
        }
        return false
    }

    private func distToLine(idx: Int, price: Double, obj: DrawingObject) -> Double {
        let x1 = Double(obj.startIndex), y1 = obj.startPrice
        let x2 = Double(obj.endIndex), y2 = obj.endPrice
        let dx = x2 - x1, dy = y2 - y1
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return abs(price - y1) }
        return abs(price - (y1 + dy * (Double(idx) - x1) / dx))
    }
}
