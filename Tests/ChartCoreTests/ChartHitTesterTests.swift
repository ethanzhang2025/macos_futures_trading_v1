// ChartHitTester 单测（v15.39 · ChartCore hit-test helper 抽象）

import Foundation
import Testing
@testable import ChartCore
import Shared

@Suite("ChartHitTester · 像素 ↔ bar/price 双向坐标转换")
struct ChartHitTesterTests {

    // MARK: - viewport 模式 hit-test

    @Test("barIndex(viewport) · 中点对应 startIndex + visibleCount/2")
    func viewportBarIndexAtCenter() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        // x = 250 (中点) · width = 500 · ratio = 0.5 · idx = 100 + 25 = 125
        let idx = ChartHitTester.barIndex(atX: 250, width: 500, viewport: vp, barCount: 200)
        #expect(idx == 125)
    }

    @Test("barIndex(viewport) · 左边界 = startIndex")
    func viewportBarIndexAtLeft() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        let idx = ChartHitTester.barIndex(atX: 0, width: 500, viewport: vp, barCount: 200)
        #expect(idx == 100)
    }

    @Test("barIndex(viewport) · 右边界 clamp 到 visibleCount-1 + startIndex")
    func viewportBarIndexAtRight() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        let idx = ChartHitTester.barIndex(atX: 500, width: 500, viewport: vp, barCount: 200)
        // x/width=1 · raw=100+50=150 · clamp 到 100+50-1=149
        #expect(idx == 149)
    }

    @Test("barIndex(viewport) · barCount 不足 visibleCount · clamp 到 barCount-1")
    func viewportBarIndexClampedToBarCount() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        // bars 只有 120 根 · visibleCount=50 但实际只能到 119
        let idx = ChartHitTester.barIndex(atX: 500, width: 500, viewport: vp, barCount: 120)
        #expect(idx == 119)
    }

    @Test("barIndex(viewport) · barCount=0 返 nil")
    func viewportBarIndexEmpty() {
        let vp = RenderViewport(startIndex: 0, visibleCount: 50)
        #expect(ChartHitTester.barIndex(atX: 100, width: 500, viewport: vp, barCount: 0) == nil)
    }

    @Test("barIndex(viewport) · width=0 返 nil（防除零）")
    func viewportBarIndexZeroWidth() {
        let vp = RenderViewport(startIndex: 0, visibleCount: 50)
        #expect(ChartHitTester.barIndex(atX: 100, width: 0, viewport: vp, barCount: 100) == nil)
    }

    @Test("barIndex(viewport) · x 越界负值 clamp 到 startIndex")
    func viewportBarIndexNegativeX() {
        let vp = RenderViewport(startIndex: 50, visibleCount: 30)
        let idx = ChartHitTester.barIndex(atX: -100, width: 500, viewport: vp, barCount: 200)
        #expect(idx == 50)
    }

    // MARK: - 全 bars 模式 hit-test

    @Test("barIndex(full) · 中点 = barCount/2")
    func fullBarIndexAtCenter() {
        let idx = ChartHitTester.barIndex(atX: 250, width: 500, barCount: 100)
        #expect(idx == 50)
    }

    @Test("barIndex(full) · 边界 clamp")
    func fullBarIndexBoundaries() {
        #expect(ChartHitTester.barIndex(atX: 0, width: 500, barCount: 100) == 0)
        #expect(ChartHitTester.barIndex(atX: 500, width: 500, barCount: 100) == 99)
        #expect(ChartHitTester.barIndex(atX: 1000, width: 500, barCount: 100) == 99)
    }

    @Test("barIndex(full) · barCount=0 返 nil")
    func fullBarIndexEmpty() {
        #expect(ChartHitTester.barIndex(atX: 100, width: 500, barCount: 0) == nil)
    }

    // MARK: - 反向 xPosition

    @Test("xPosition(viewport) · 中心点偏移 0.5")
    func viewportXPositionCenter() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        // barIndex=125 · 在 viewport 中心 · 应在 width 中心
        // (125-100+0.5)/50 = 25.5/50 = 0.51 · 500 × 0.51 = 255
        let x = ChartHitTester.xPosition(forBarIndex: 125, width: 500, viewport: vp)
        #expect(abs((x ?? 0) - 255) < 0.01)
    }

    @Test("xPosition(viewport) · barIndex 不在可视范围返 nil")
    func viewportXPositionOutOfRange() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        // barIndex=99（在 startIndex 之前）
        #expect(ChartHitTester.xPosition(forBarIndex: 99, width: 500, viewport: vp) == nil)
        // barIndex=150（超出 visibleCount）
        #expect(ChartHitTester.xPosition(forBarIndex: 150, width: 500, viewport: vp) == nil)
    }

    @Test("xPosition(full) · 中心点偏移 0.5")
    func fullXPositionCenter() {
        // barIndex=49 · barCount=100 · (49+0.5)/100 = 0.495 · 500 × 0.495 = 247.5
        let x = ChartHitTester.xPosition(forBarIndex: 49, width: 500, barCount: 100)
        #expect(abs((x ?? 0) - 247.5) < 0.01)
    }

    @Test("xPosition(full) · barIndex 越界返 nil")
    func fullXPositionOutOfRange() {
        #expect(ChartHitTester.xPosition(forBarIndex: -1, width: 500, barCount: 100) == nil)
        #expect(ChartHitTester.xPosition(forBarIndex: 100, width: 500, barCount: 100) == nil)
    }

    // MARK: - price 双向

    @Test("price(at y) · y=0 顶 = upperBound")
    func priceAtTop() {
        let range = Decimal(100)...Decimal(200)
        let p = ChartHitTester.price(atY: 0, height: 500, priceRange: range)
        #expect(p == 200)
    }

    @Test("price(at y) · y=height 底 = lowerBound")
    func priceAtBottom() {
        let range = Decimal(100)...Decimal(200)
        let p = ChartHitTester.price(atY: 500, height: 500, priceRange: range)
        #expect(p == 100)
    }

    @Test("price(at y) · 中点 = (lower + upper) / 2")
    func priceAtMiddle() {
        let range = Decimal(100)...Decimal(200)
        let p = ChartHitTester.price(atY: 250, height: 500, priceRange: range)
        // y=250 中点 · yRatio=0.5 → price = 100 + 100×0.5 = 150
        #expect(p == 150)
    }

    @Test("price(at y) · y 越界 clamp")
    func priceClamped() {
        let range = Decimal(100)...Decimal(200)
        // y < 0 视为顶
        #expect(ChartHitTester.price(atY: -100, height: 500, priceRange: range) == 200)
        // y > height 视为底
        #expect(ChartHitTester.price(atY: 1000, height: 500, priceRange: range) == 100)
    }

    @Test("yPosition(forPrice) · upperBound 在 y=0")
    func yPositionAtTop() {
        let range = Decimal(100)...Decimal(200)
        let y = ChartHitTester.yPosition(forPrice: 200, height: 500, priceRange: range)
        #expect(abs(y - 0) < 0.01)
    }

    @Test("yPosition(forPrice) · lowerBound 在 y=height")
    func yPositionAtBottom() {
        let range = Decimal(100)...Decimal(200)
        let y = ChartHitTester.yPosition(forPrice: 100, height: 500, priceRange: range)
        #expect(abs(y - 500) < 0.01)
    }

    @Test("yPosition(forPrice) · 中点价格 → 中心 y")
    func yPositionAtMiddle() {
        let range = Decimal(100)...Decimal(200)
        let y = ChartHitTester.yPosition(forPrice: 150, height: 500, priceRange: range)
        #expect(abs(y - 250) < 0.01)
    }

    @Test("yPosition(forPrice) · 价格越界 clamp")
    func yPositionClamped() {
        let range = Decimal(100)...Decimal(200)
        // 超过 upper · y 应 = 0
        #expect(ChartHitTester.yPosition(forPrice: 300, height: 500, priceRange: range) == 0)
        // 低于 lower · y 应 = height
        #expect(ChartHitTester.yPosition(forPrice: 50, height: 500, priceRange: range) == 500)
    }

    @Test("yPosition(forPrice Double) · 与 Decimal 版语义对齐")
    func yPositionDouble() {
        let y = ChartHitTester.yPosition(forPrice: 150, height: 500, priceMin: 100, priceMax: 200)
        #expect(abs(y - 250) < 0.01)
    }

    @Test("yPosition · priceMax == priceMin（一字板 · 防除零）")
    func yPositionFlatRange() {
        let y = ChartHitTester.yPosition(forPrice: 100, height: 500, priceMin: 100, priceMax: 100)
        // 应返回中点（避免除零 crash）
        #expect(y == 250)
    }

    // MARK: - 双向往返一致性

    @Test("往返：barIndex → x → barIndex 同值（viewport）")
    func roundTripViewport() {
        let vp = RenderViewport(startIndex: 100, visibleCount: 50)
        for idx in [100, 110, 125, 140, 149] {
            let x = ChartHitTester.xPosition(forBarIndex: idx, width: 500, viewport: vp)!
            let back = ChartHitTester.barIndex(atX: x, width: 500, viewport: vp, barCount: 200)
            #expect(back == idx)
        }
    }

    @Test("往返：barIndex → x → barIndex 同值（full）")
    func roundTripFull() {
        for idx in [0, 25, 50, 75, 99] {
            let x = ChartHitTester.xPosition(forBarIndex: idx, width: 500, barCount: 100)!
            let back = ChartHitTester.barIndex(atX: x, width: 500, barCount: 100)
            #expect(back == idx)
        }
    }
}
