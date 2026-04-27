// ChartCore · WP-20 MetalKLineRenderer 单元测试
//
// Mac-only：#if canImport(Metal) 包裹 · Linux 端不参编（保持 swift test 全绿）
// 验证内容：
// - init 不抛错（系统有 default device · Mac 物理机必满足）
// - render 不需要 drawable 也能返回估算 stats（drawCallCount = 2）
// - drawCall 与 K 数量无关（合批契约 · M6 性能关键）
// - visibleBarCount clamp 到实际可用范围
// - setQuality 切档生效
//
// 性能 benchmark（10w K 60fps）走 Tools/MetalKLineDemo · 此处仅验协议契约 + 数据正确性

#if canImport(Metal)

import Testing
import Foundation
import Metal
import Shared
import IndicatorCore
@testable import ChartCore

private func makeKLines(_ count: Int, basePrice: Decimal = 3000) -> [KLine] {
    (0..<count).map { i in
        let drift = Decimal(i % 50) - Decimal(25)
        return KLine(
            instrumentID: "RB",
            period: .minute1,
            openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
            open: basePrice + drift,
            high: basePrice + drift + 5,
            low: basePrice + drift - 5,
            close: basePrice + drift + (i.isMultiple(of: 2) ? 2 : -2),
            volume: 100,
            openInterest: 0,
            turnover: 0
        )
    }
}

/// 测试用：无 Metal device 时构造 renderer 抛 metalNotSupported · 测试主体早退
/// 把 6 处 `guard MTLCreateSystemDefaultDevice() != nil else { return }` + `try MetalKLineRenderer()` 合并
private func makeRendererOrSkip() throws -> MetalKLineRenderer? {
    guard MTLCreateSystemDefaultDevice() != nil else { return nil }
    return try MetalKLineRenderer()
}

@Suite("MetalKLineRenderer · init + KLineRenderer 协议契约")
struct MetalKLineRendererInitTests {

    @Test("init 不抛错（Mac 默认 Metal device 存在）")
    func initSucceeds() throws {
        // 仅在有 Metal device 的机器跑（Mac CI 必满足 · Linux 已被 #if 排除）
        _ = try makeRendererOrSkip()
    }

    @Test("默认 quality = .high")
    func defaultQuality() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        #expect(await r.quality == .high)
    }

    @Test("setQuality 切档 · ultra")
    func setQualityUltra() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        await r.setQuality(.ultra)
        #expect(await r.quality == .ultra)
    }
}

@Suite("MetalKLineRenderer · render（无 drawable）估算 stats")
struct MetalKLineRendererRenderTests {

    @Test("render 100 K · drawCall = 2（实体 + 影线 · 与 K 数无关）")
    func drawCallIsTwoFor100Bars() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        let input = KLineRenderInput(
            bars: makeKLines(100),
            viewport: RenderViewport(startIndex: 0, visibleCount: 100)
        )
        let stats = await r.render(input)
        #expect(stats.drawCallCount == 2)
        #expect(stats.visibleBarCount == 100)
    }

    @Test("render 10000 K · drawCall 仍 = 2（合批契约 · M6 性能关键）")
    func drawCallStillTwoFor10kBars() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        let input = KLineRenderInput(
            bars: makeKLines(10000),
            viewport: RenderViewport(startIndex: 0, visibleCount: 1000)
        )
        let stats = await r.render(input)
        #expect(stats.drawCallCount == 2)
        #expect(stats.visibleBarCount == 1000)
    }

    @Test("空 bars · drawCall = 0 · visibleBars = 0")
    func emptyInput() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        let input = KLineRenderInput(
            bars: [],
            viewport: RenderViewport(startIndex: 0, visibleCount: 100)
        )
        let stats = await r.render(input)
        #expect(stats.drawCallCount == 0)
        #expect(stats.visibleBarCount == 0)
    }

    @Test("visibleCount > 实际可用 · clamp 到 bars.count - startIndex")
    func clampsToAvailable() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        let input = KLineRenderInput(
            bars: makeKLines(50),
            viewport: RenderViewport(startIndex: 30, visibleCount: 200)
        )
        let stats = await r.render(input)
        #expect(stats.visibleBarCount == 20)  // 50 - 30
    }

    @Test("WP-40 起步：2 个 indicator · drawCall = 4（实体 + 影线 + 2 折线 · 与 K 数无关）")
    func drawCallWithTwoIndicators() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        let bars = makeKLines(100)
        let ma20 = IndicatorSeries(
            name: "MA(20)",
            values: (0..<100).map { i in i >= 19 ? Decimal(3000 + i % 20) : nil }
        )
        let ma60 = IndicatorSeries(
            name: "MA(60)",
            values: (0..<100).map { i in i >= 59 ? Decimal(3000 + i % 60) : nil }
        )
        let input = KLineRenderInput(
            bars: bars,
            indicators: [ma20, ma60],
            viewport: RenderViewport(startIndex: 0, visibleCount: 100)
        )
        let stats = await r.render(input)
        #expect(stats.drawCallCount == 4)
        #expect(stats.visibleBarCount == 100)
    }

    @Test("lastStats 反映最近一次 render（多次连续调用）")
    func lastStatsReflectsLatest() async throws {
        guard let r = try makeRendererOrSkip() else { return }
        _ = await r.render(KLineRenderInput(
            bars: makeKLines(100),
            viewport: RenderViewport(startIndex: 0, visibleCount: 100)
        ))
        _ = await r.render(KLineRenderInput(
            bars: makeKLines(500),
            viewport: RenderViewport(startIndex: 0, visibleCount: 50)
        ))
        let stats = await r.lastStats
        #expect(stats.visibleBarCount == 50)
        #expect(stats.drawCallCount == 2)
    }
}

#endif  // canImport(Metal)
