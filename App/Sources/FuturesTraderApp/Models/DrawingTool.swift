import SwiftUI

/// 绘图工具类型
enum DrawingToolType: String, CaseIterable {
    case none = "无"
    case trendLine = "趋势线"
    case horizontalLine = "水平线"
}

/// 绘图对象
struct DrawingObject: Identifiable, Equatable {
    let id = UUID()
    let type: DrawingToolType
    /// 起始点（K线索引, 价格）
    var startIndex: Int
    var startPrice: Double
    /// 终止点（趋势线用）
    var endIndex: Int
    var endPrice: Double
    /// 颜色
    var color: Color = Color.yellow
    /// 是否选中
    var isSelected: Bool = false

    static func == (lhs: DrawingObject, rhs: DrawingObject) -> Bool {
        lhs.id == rhs.id
    }

    /// 创建水平线
    static func horizontal(price: Double, index: Int) -> DrawingObject {
        DrawingObject(type: .horizontalLine, startIndex: index, startPrice: price, endIndex: index, endPrice: price, color: Color.yellow)
    }

    /// 创建趋势线
    static func trend(startIndex: Int, startPrice: Double, endIndex: Int, endPrice: Double) -> DrawingObject {
        DrawingObject(type: .trendLine, startIndex: startIndex, startPrice: startPrice, endIndex: endIndex, endPrice: endPrice, color: Color.orange)
    }
}

/// 绘图状态管理
class DrawingState: ObservableObject {
    @Published var activeTool: DrawingToolType = .none
    @Published var objects: [DrawingObject] = []
    @Published var tempStartIndex: Int?
    @Published var tempStartPrice: Double?

    var isDrawing: Bool { activeTool != .none }

    func startTool(_ tool: DrawingToolType) {
        activeTool = tool
        tempStartIndex = nil
        tempStartPrice = nil
    }

    func cancelDrawing() {
        activeTool = .none
        tempStartIndex = nil
        tempStartPrice = nil
    }

    func addObject(_ obj: DrawingObject) {
        objects.append(obj)
        activeTool = .none
        tempStartIndex = nil
        tempStartPrice = nil
    }

    func deleteSelected() {
        objects.removeAll { $0.isSelected }
    }

    func deselectAll() {
        for i in objects.indices { objects[i].isSelected = false }
    }

    func clearAll() {
        objects.removeAll()
    }

    /// 选中最近的绘图对象（点击位置附近）
    func selectNearby(index: Int, price: Double, tolerance: Double) -> Bool {
        deselectAll()
        for i in objects.indices {
            let obj = objects[i]
            switch obj.type {
            case .horizontalLine:
                if abs(obj.startPrice - price) < tolerance {
                    objects[i].isSelected = true
                    return true
                }
            case .trendLine:
                let dist = distanceToLine(
                    px: Double(index), py: price,
                    x1: Double(obj.startIndex), y1: obj.startPrice,
                    x2: Double(obj.endIndex), y2: obj.endPrice
                )
                if dist < tolerance {
                    objects[i].isSelected = true
                    return true
                }
            case .none:
                break
            }
        }
        return false
    }

    private func distanceToLine(px: Double, py: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        let dx = x2 - x1, dy = y2 - y1
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1)) }
        let t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / lenSq))
        let projX = x1 + t * dx, projY = y1 + t * dy
        return abs(py - projY) // 只看价格距离，忽略X轴
    }
}
