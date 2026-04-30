// WP-42 · 画线工具 v1 测试
// 6 类型创建 · Codable 往返 · 几何（趋势线插值 / 矩形包含 / 斐波那契比例 / 平行通道副线）

import Testing
import Foundation
@testable import Shared

private func point(_ bar: Int, _ price: Int) -> DrawingPoint {
    DrawingPoint(barIndex: bar, price: Decimal(price))
}

@Suite("Drawing 创建与类型契约")
struct DrawingFactoryTests {
    @Test("8 种 factory 类型正确（v13.13 加椭圆 · v13.14 加测量工具）")
    func factoryTypes() {
        #expect(Drawing.trendLine(from: point(0, 100), to: point(10, 110)).type == .trendLine)
        #expect(Drawing.horizontalLine(price: 100).type == .horizontalLine)
        #expect(Drawing.rectangle(from: point(0, 100), to: point(10, 110)).type == .rectangle)
        #expect(Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: 5).type == .parallelChannel)
        #expect(Drawing.fibonacci(from: point(0, 100), to: point(10, 110)).type == .fibonacci)
        #expect(Drawing.text(at: point(5, 105), content: "买入").type == .text)
        #expect(Drawing.ellipse(from: point(0, 100), to: point(10, 110)).type == .ellipse)
        #expect(Drawing.ruler(from: point(0, 100), to: point(10, 110)).type == .ruler)
    }

    @Test("needsTwoPoints 契约（v13.13 ellipse · v13.14 ruler 都是双点）")
    func twoPointsContract() {
        #expect(DrawingType.trendLine.needsTwoPoints)
        #expect(DrawingType.rectangle.needsTwoPoints)
        #expect(DrawingType.parallelChannel.needsTwoPoints)
        #expect(DrawingType.fibonacci.needsTwoPoints)
        #expect(DrawingType.ellipse.needsTwoPoints)
        #expect(DrawingType.ruler.needsTwoPoints)
        #expect(!DrawingType.horizontalLine.needsTwoPoints)
        #expect(!DrawingType.text.needsTwoPoints)
    }

    @Test("文字画线携带内容")
    func textCarriesContent() {
        let d = Drawing.text(at: point(5, 105), content: "止盈")
        #expect(d.text == "止盈")
        #expect(d.endPoint == nil)
    }

    @Test("平行通道携带 offset")
    func channelCarriesOffset() {
        let d = Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: Decimal(5))
        #expect(d.channelOffset == 5)
    }
}

@Suite("Drawing Codable 往返")
struct DrawingCodableTests {
    @Test("8 种序列化 + 反序列化等价（v13.13 加椭圆 · v13.14 加测量）")
    func roundTrip() throws {
        let drawings = [
            Drawing.trendLine(from: point(0, 100), to: point(10, 120)),
            Drawing.horizontalLine(price: Decimal(string: "3550.5")!),
            Drawing.rectangle(from: point(2, 95), to: point(8, 115)),
            Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: Decimal(string: "3.5")!),
            Drawing.fibonacci(from: point(0, 100), to: point(10, 150)),
            Drawing.text(at: point(5, 105), content: "测试"),
            Drawing.ellipse(from: point(0, 100), to: point(10, 120)),
            Drawing.ruler(from: point(0, 100), to: point(10, 130))
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for d in drawings {
            let data = try encoder.encode(d)
            let back = try decoder.decode(Drawing.self, from: data)
            #expect(back == d)
        }
    }
}

// v13.11~v13.13 锁定 / 字号 / 椭圆字段
@Suite("Drawing v13.11~v13.13 isLocked + fontSize + ellipse")
struct DrawingExtraFieldsTests {
    @Test("v13.11 isLocked 默认 nil + locked computed property")
    func isLockedDefaultsAndComputed() {
        let unlocked = Drawing.trendLine(from: point(0, 100), to: point(10, 110))
        #expect(unlocked.isLocked == nil)
        #expect(unlocked.locked == false)

        let locked = Drawing(type: .trendLine, startPoint: point(0, 100), endPoint: point(10, 110), isLocked: true)
        #expect(locked.isLocked == true)
        #expect(locked.locked == true)

        let explicitFalse = Drawing(type: .text, startPoint: point(5, 105), text: "x", isLocked: false)
        #expect(explicitFalse.isLocked == false)
        #expect(explicitFalse.locked == false)  // false 也视为不锁
    }

    @Test("v13.11 isLocked 序列化往返")
    func isLockedRoundTrip() throws {
        let d = Drawing(type: .horizontalLine, startPoint: point(0, 3550), isLocked: true)
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Drawing.self, from: data)
        #expect(back == d)
        #expect(back.locked)
    }

    @Test("v13.12 fontSize 默认 nil + 自定义往返")
    func fontSizeDefaultsAndRoundTrip() throws {
        let plain = Drawing.text(at: point(5, 105), content: "x")
        #expect(plain.fontSize == nil)

        let big = Drawing(type: .text, startPoint: point(5, 105), text: "大字", fontSize: 24)
        #expect(big.fontSize == 24)
        let back = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(big))
        #expect(back == big)
        #expect(back.fontSize == 24)
    }

    @Test("v13.13 椭圆 factory + 几何（外接矩形对角两点）")
    func ellipseFactory() {
        let e = Drawing.ellipse(from: point(0, 100), to: point(10, 200))
        #expect(e.type == .ellipse)
        #expect(e.startPoint.barIndex == 0)
        #expect(e.endPoint?.barIndex == 10)
        #expect(e.text == nil)
        #expect(e.channelOffset == nil)
    }

    @Test("v13.14 测量工具 factory · 双点 + 不带 channelOffset/text")
    func rulerFactory() {
        let r = Drawing.ruler(from: point(0, 100), to: point(10, 130))
        #expect(r.type == .ruler)
        #expect(r.startPoint.barIndex == 0)
        #expect(r.startPoint.price == 100)
        #expect(r.endPoint?.barIndex == 10)
        #expect(r.endPoint?.price == 130)
        #expect(r.channelOffset == nil)
        #expect(r.text == nil)
    }

    @Test("v13.16 DrawingTemplate 内嵌 Drawing 完整快照 + 序列化往返")
    func drawingTemplateRoundTrip() throws {
        let drawing = Drawing(
            type: .trendLine,
            startPoint: point(0, 100),
            endPoint: point(10, 110),
            strokeColorHex: "FFC72C",
            strokeWidth: 2.0,
            strokeOpacity: 0.8
        )
        let template = DrawingTemplate(name: "前高阻力", drawing: drawing)
        #expect(template.name == "前高阻力")
        #expect(template.drawing.type == .trendLine)
        #expect(template.drawing.strokeColorHex == "FFC72C")

        let data = try JSONEncoder().encode(template)
        let back = try JSONDecoder().decode(DrawingTemplate.self, from: data)
        #expect(back.id == template.id)
        #expect(back.name == "前高阻力")
        #expect(back.drawing == drawing)
    }

    @Test("v13.16 DrawingTemplate 数组序列化（UserDefaults 持久化路径）")
    func drawingTemplateArrayRoundTrip() throws {
        let templates = [
            DrawingTemplate(name: "支撑位", drawing: Drawing.horizontalLine(price: 3500)),
            DrawingTemplate(name: "阻力位", drawing: Drawing.horizontalLine(price: 3700)),
            DrawingTemplate(name: "上升通道", drawing: Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: 5))
        ]
        let data = try JSONEncoder().encode(templates)
        let back = try JSONDecoder().decode([DrawingTemplate].self, from: data)
        #expect(back.count == 3)
        #expect(back[0].name == "支撑位")
        #expect(back[1].drawing.startPoint.price == 100 || back[1].drawing.startPoint.price == 3700)  // horizontalLine 用 price 作为 startPoint.price
        #expect(back[2].drawing.type == .parallelChannel)
        #expect(back[2].drawing.channelOffset == 5)
    }

    @Test("v13.15 strokeOpacity 默认 nil + 自定义往返")
    func strokeOpacityRoundTrip() throws {
        let plain = Drawing.trendLine(from: point(0, 100), to: point(10, 110))
        #expect(plain.strokeOpacity == nil)

        let semi = Drawing(
            type: .rectangle,
            startPoint: point(0, 100),
            endPoint: point(10, 110),
            strokeColorHex: "FF8C00",
            strokeOpacity: 0.5
        )
        #expect(semi.strokeOpacity == 0.5)
        let back = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(semi))
        #expect(back == semi)
        #expect(back.strokeOpacity == 0.5)
    }

    @Test("v13.11~v13.13 老 JSON（无 isLocked / fontSize / ellipse 字段）兼容")
    func legacyJsonStillDecodes() throws {
        // 模拟 v13.10- 旧 JSON · 不含 v13.11/v13.12 任何字段
        let legacyJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "type": "trendLine",
            "startPoint": { "barIndex": 0, "price": 100 },
            "endPoint": { "barIndex": 10, "price": 110 },
            "strokeColorHex": "FF8C00",
            "strokeWidth": 2.0
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let d = try JSONDecoder().decode(Drawing.self, from: data)
        #expect(d.isLocked == nil)
        #expect(d.fontSize == nil)
        #expect(!d.locked)
        // v13.8 字段保留
        #expect(d.strokeColorHex == "FF8C00")
        #expect(d.strokeWidth == 2.0)
    }
}

// v13.8 颜色 / 线宽自定义字段
@Suite("Drawing v13.8 strokeColorHex + strokeWidth")
struct DrawingStrokeStyleTests {
    @Test("默认值：工厂方法 + init 缺省 → 都是 nil（用类型默认色 / 1.5 宽）")
    func defaultsAreNil() {
        let trend = Drawing.trendLine(from: point(0, 100), to: point(10, 110))
        #expect(trend.strokeColorHex == nil)
        #expect(trend.strokeWidth == nil)

        let plain = Drawing(type: .horizontalLine, startPoint: point(0, 100))
        #expect(plain.strokeColorHex == nil)
        #expect(plain.strokeWidth == nil)
    }

    @Test("自定义构造：color hex + width 序列化往返保持")
    func customStyleRoundTrip() throws {
        let d = Drawing(
            type: .trendLine,
            startPoint: point(0, 100),
            endPoint: point(10, 110),
            strokeColorHex: "FF8C00",
            strokeWidth: 2.5
        )
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Drawing.self, from: data)
        #expect(back == d)
        #expect(back.strokeColorHex == "FF8C00")
        #expect(back.strokeWidth == 2.5)
    }

    @Test("老 JSON 兼容：缺 strokeColorHex / strokeWidth 字段 → 解码 nil")
    func legacyJsonDecodesNil() throws {
        // 模拟 v13.7- 旧 JSON · 不含 v13.8 两个字段
        let legacyJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "type": "trendLine",
            "startPoint": { "barIndex": 0, "price": 100 },
            "endPoint": { "barIndex": 10, "price": 110 }
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let d = try JSONDecoder().decode(Drawing.self, from: data)
        #expect(d.type == .trendLine)
        #expect(d.strokeColorHex == nil)
        #expect(d.strokeWidth == nil)
    }

    @Test("仅 strokeColorHex 自定义 · width 仍 nil")
    func partialCustomColorOnly() throws {
        let d = Drawing(
            type: .horizontalLine,
            startPoint: point(0, 100),
            strokeColorHex: "00FF7F"
        )
        #expect(d.strokeColorHex == "00FF7F")
        #expect(d.strokeWidth == nil)
        // 序列化往返保持
        let back = try JSONDecoder().decode(Drawing.self, from: JSONEncoder().encode(d))
        #expect(back == d)
    }

    @Test("仅 strokeWidth 自定义 · color 仍 nil")
    func partialCustomWidthOnly() {
        let d = Drawing(
            type: .text,
            startPoint: point(5, 105),
            text: "标注",
            strokeWidth: 3.0
        )
        #expect(d.strokeWidth == 3.0)
        #expect(d.strokeColorHex == nil)
        #expect(d.text == "标注")
    }
}

@Suite("Drawing 几何")
struct DrawingGeometryTests {
    @Test("趋势线在中点插值")
    func trendLineInterpolation() {
        let d = Drawing.trendLine(from: point(0, 100), to: point(10, 200))
        // 中点 bar=5 → price = 150
        #expect(DrawingGeometry.linePrice(of: d, atBar: 5) == 150)
        // 端点
        #expect(DrawingGeometry.linePrice(of: d, atBar: 0) == 100)
        #expect(DrawingGeometry.linePrice(of: d, atBar: 10) == 200)
        // 外推
        #expect(DrawingGeometry.linePrice(of: d, atBar: 20) == 300)
    }

    @Test("水平线读价格")
    func horizontalPrice() {
        let d = Drawing.horizontalLine(price: Decimal(string: "3550.5")!)
        #expect(DrawingGeometry.horizontalPrice(of: d) == Decimal(string: "3550.5"))
    }

    @Test("矩形归一化 + 包含判定")
    func rectangleBounds() {
        // 倒序输入：start=(10, 200) end=(0, 100)
        let d = Drawing.rectangle(from: point(10, 200), to: point(0, 100))
        let b = DrawingGeometry.rectangleBounds(of: d)!
        #expect(b.minBar == 0 && b.maxBar == 10)
        #expect(b.minPrice == 100 && b.maxPrice == 200)
        #expect(DrawingGeometry.rectangle(d, contains: 5, price: 150))
        #expect(!DrawingGeometry.rectangle(d, contains: 5, price: 250))
        #expect(!DrawingGeometry.rectangle(d, contains: 15, price: 150))
    }

    @Test("斐波那契 7 档比例")
    func fibonacciLevels() {
        let d = Drawing.fibonacci(from: point(0, 100), to: point(10, 200))  // span 100
        let prices = DrawingGeometry.fibonacciPrices(for: d)
        #expect(prices.count == 7)
        #expect(prices[0] == 100)   // 0%
        #expect(prices[3] == 150)   // 50%
        #expect(prices[6] == 200)   // 100%
        // 38.2% = 100 + 100 * 0.382 = 138.2
        #expect(prices[2] == Decimal(string: "138.2"))
    }

    @Test("平行通道副线 = 主轴 + offset")
    func channelOffsetLine() {
        let d = Drawing.parallelChannel(from: point(0, 100), to: point(10, 200), offset: Decimal(20))
        // 主轴 bar=5 价格 150；副线 = 170
        #expect(DrawingGeometry.linePrice(of: d, atBar: 5) == 150)
        #expect(DrawingGeometry.channelOffsetPrice(of: d, atBar: 5) == 170)
    }

    @Test("非匹配类型返回 nil")
    func typeMismatch() {
        let h = Drawing.horizontalLine(price: 100)
        #expect(DrawingGeometry.linePrice(of: h, atBar: 5) == nil)
        #expect(DrawingGeometry.rectangleBounds(of: h) == nil)
        #expect(DrawingGeometry.fibonacciPrices(for: h).isEmpty)
    }

    @Test("priceDistance 趋势线垂直差")
    func priceDistance() {
        let d = Drawing.trendLine(from: point(0, 100), to: point(10, 200))
        // bar=5 趋势线价 = 150；点价 = 145 → 距离 5
        #expect(DrawingGeometry.priceDistance(from: d, atBar: 5, price: 145) == 5)
    }
}
