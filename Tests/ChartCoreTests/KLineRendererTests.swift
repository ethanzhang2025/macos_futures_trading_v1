// ChartCore · KLineRenderer 数据契约单元测试
// Metal-agnostic · Linux 可跑 · Mac 端 MetalKLineRenderer 实现后再补渲染验证测试

import Testing
import Foundation
import Shared
import IndicatorCore
@testable import ChartCore

// MARK: - RenderViewport

@Suite("RenderViewport · 视口操作")
struct RenderViewportTests {

    @Test("默认初始化：负 startIndex 自动 clamp 到 0 · visibleCount 至少 1")
    func defaultsClamped() {
        let v1 = RenderViewport(startIndex: -10, visibleCount: 100)
        #expect(v1.startIndex == 0)
        let v2 = RenderViewport(startIndex: 0, visibleCount: 0)
        #expect(v2.visibleCount == 1)
    }

    @Test("panned 平移视口：startIndex += delta · visibleCount 不变")
    func pannedShiftsStart() {
        let v = RenderViewport(startIndex: 100, visibleCount: 50)
        let shifted = v.panned(by: 30)
        #expect(shifted.startIndex == 130)
        #expect(shifted.visibleCount == 50)
    }

    @Test("zoomed 缩放：visibleCount × factor · startIndex 围绕中心")
    func zoomedAroundCenter() {
        let v = RenderViewport(startIndex: 100, visibleCount: 100)  // 中心 = 150
        let zoomedIn = v.zoomed(by: 0.5)  // 新宽度 50 · 中心 150 → start 125
        #expect(zoomedIn.visibleCount == 50)
        #expect(zoomedIn.startIndex == 125)
        let zoomedOut = v.zoomed(by: 2.0)  // 新宽度 200 · 中心 150 → start 50
        #expect(zoomedOut.visibleCount == 200)
        #expect(zoomedOut.startIndex == 50)
    }

    @Test("Codable 往返：含 priceRange 范围")
    func codableRoundTrip() throws {
        let v = RenderViewport(startIndex: 10, visibleCount: 50, priceRange: Decimal(3000)...Decimal(3500))
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(RenderViewport.self, from: data)
        #expect(decoded == v)
    }
}

// MARK: - RenderQuality

@Suite("RenderQuality · 渲染质量档")
struct RenderQualityTests {

    @Test("CaseIterable 3 档（balanced / high / ultra）")
    func threeQualities() {
        let all = RenderQuality.allCases
        #expect(all == [.balanced, .high, .ultra])
    }

    @Test("rawValue 与 case 名对齐（向后兼容旧 JSON 配置）")
    func rawValuesMatch() {
        #expect(RenderQuality.balanced.rawValue == "balanced")
        #expect(RenderQuality.high.rawValue == "high")
        #expect(RenderQuality.ultra.rawValue == "ultra")
    }
}

// MARK: - RenderStats

@Suite("RenderStats · 渲染统计")
struct RenderStatsTests {

    @Test("默认初始化：全 0")
    func defaults() {
        let s = RenderStats()
        #expect(s.lastFrameDuration == 0)
        #expect(s.drawCallCount == 0)
        #expect(s.visibleBarCount == 0)
        #expect(s.droppedFrameCount == 0)
    }

    @Test("isHealthy60fps：≤16.67ms + dropped ≤1 → true")
    func health60fpsHappyPath() {
        let healthy = RenderStats(lastFrameDuration: 0.016, drawCallCount: 100, visibleBarCount: 100, droppedFrameCount: 0)
        #expect(healthy.isHealthy60fps == true)
    }

    @Test("isHealthy60fps：>16.67ms → false（卡顿）")
    func health60fpsSlow() {
        let slow = RenderStats(lastFrameDuration: 0.025, drawCallCount: 100, visibleBarCount: 100, droppedFrameCount: 0)
        #expect(slow.isHealthy60fps == false)
    }

    @Test("isHealthy60fps：droppedFrame > 1 → false（频繁掉帧）")
    func health60fpsDropped() {
        let dropped = RenderStats(lastFrameDuration: 0.016, drawCallCount: 100, visibleBarCount: 100, droppedFrameCount: 5)
        #expect(dropped.isHealthy60fps == false)
    }
}

// MARK: - NoOpKLineRenderer

private func makeKLines(_ count: Int) -> [KLine] {
    (0..<count).map { i in
        KLine(
            instrumentID: "RB", period: .minute1,
            openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
            open: 3000, high: 3010, low: 2990, close: 3005,
            volume: 0, openInterest: 0, turnover: 0
        )
    }
}

@Suite("NoOpKLineRenderer · 测试占位实现")
struct NoOpKLineRendererTests {

    @Test("初始化默认 quality = .high")
    func defaultQuality() async {
        let renderer = NoOpKLineRenderer()
        #expect(await renderer.quality == .high)
    }

    @Test("setQuality 切档 · ultra")
    func setQualityUltra() async {
        let renderer = NoOpKLineRenderer()
        await renderer.setQuality(.ultra)
        #expect(await renderer.quality == .ultra)
    }

    @Test("render 记录 input + 返回模拟 60fps stats")
    func renderRecordsAndReturnsStats() async {
        let renderer = NoOpKLineRenderer()
        let input = KLineRenderInput(
            bars: makeKLines(1000),
            viewport: RenderViewport(startIndex: 0, visibleCount: 100)
        )
        let stats = await renderer.render(input)
        #expect(stats.visibleBarCount == 100)
        #expect(stats.drawCallCount == 100)
        #expect(stats.isHealthy60fps == true)
    }

    @Test("visible 数量 clamp 到 bars 实际可用范围")
    func visibleClampsToActualBars() async {
        let renderer = NoOpKLineRenderer()
        // 只有 50 根 K，但视口要 200 根 + start 30 → 实际可见 = 50 - 30 = 20
        let input = KLineRenderInput(
            bars: makeKLines(50),
            viewport: RenderViewport(startIndex: 30, visibleCount: 200)
        )
        let stats = await renderer.render(input)
        #expect(stats.visibleBarCount == 20)
    }

    @Test("renderCount 累加 · 多次 render 后等于调用次数")
    func renderCountAccumulates() async {
        let renderer = NoOpKLineRenderer()
        let input = KLineRenderInput(bars: makeKLines(10), viewport: RenderViewport(startIndex: 0, visibleCount: 5))
        for _ in 0..<7 { _ = await renderer.render(input) }
        #expect(await renderer.renderCount == 7)
    }
}
