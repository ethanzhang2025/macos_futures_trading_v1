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
    @Test("6 种 factory 类型正确")
    func factoryTypes() {
        #expect(Drawing.trendLine(from: point(0, 100), to: point(10, 110)).type == .trendLine)
        #expect(Drawing.horizontalLine(price: 100).type == .horizontalLine)
        #expect(Drawing.rectangle(from: point(0, 100), to: point(10, 110)).type == .rectangle)
        #expect(Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: 5).type == .parallelChannel)
        #expect(Drawing.fibonacci(from: point(0, 100), to: point(10, 110)).type == .fibonacci)
        #expect(Drawing.text(at: point(5, 105), content: "买入").type == .text)
    }

    @Test("needsTwoPoints 契约")
    func twoPointsContract() {
        #expect(DrawingType.trendLine.needsTwoPoints)
        #expect(DrawingType.rectangle.needsTwoPoints)
        #expect(DrawingType.parallelChannel.needsTwoPoints)
        #expect(DrawingType.fibonacci.needsTwoPoints)
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
    @Test("6 种序列化 + 反序列化等价")
    func roundTrip() throws {
        let drawings = [
            Drawing.trendLine(from: point(0, 100), to: point(10, 120)),
            Drawing.horizontalLine(price: Decimal(string: "3550.5")!),
            Drawing.rectangle(from: point(2, 95), to: point(8, 115)),
            Drawing.parallelChannel(from: point(0, 100), to: point(10, 110), offset: Decimal(string: "3.5")!),
            Drawing.fibonacci(from: point(0, 100), to: point(10, 150)),
            Drawing.text(at: point(5, 105), content: "测试")
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
