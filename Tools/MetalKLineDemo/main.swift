// WP-20 Metal K 线 PoC 性能验收 demo
//
// 运行：swift run MetalKLineDemo
//
// 设计：
// - Headless（offscreen MTLTexture · 不开窗口 · 自动退出）· 适合 swift run / CI / Instruments attach
// - 1w K 100 帧 baseline · 10w K 100 帧 M6 生死核心
// - 报告：avg / max frame duration（ms）· 60fps 健康率 · drawCall · visibleBars
// - Linux 端仅打印 "Metal unavailable on Linux · skip" 退出 0（保持 swift build 跨平台）
//
// 验收基准（M6）：
// - 1w K：avg < 16.67ms · healthy60fps ≥ 95/100
// - 10w K：avg < 16.67ms · healthy60fps ≥ 90/100（生死核心）
// - drawCall = 2（合批契约）

#if canImport(Metal)

import Foundation
import Metal
import Shared
import ChartCore

@main
struct MetalKLineDemoMain {

    static func main() async {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("⚠️ Metal not available · 退出")
            return
        }
        print("=== WP-20 Metal K 线 PoC 性能验收 ===")
        print("（headless · offscreen 1280x720 · 100 帧 baseline）")
        print("")
        let renderer: MetalKLineRenderer
        do {
            renderer = try MetalKLineRenderer()
        } catch {
            print("❌ MetalKLineRenderer init 失败：\(error)")
            return
        }
        let texture = makeOffscreenTexture(device: renderer.metalDevice, width: 1280, height: 720)
        guard let texture else {
            print("❌ Offscreen texture 创建失败")
            return
        }

        // 1w K · baseline
        await runBenchmark(
            label: "1w K（PoC baseline）",
            renderer: renderer,
            barCount: 10_000,
            visibleCount: 1_000,
            frames: 100,
            texture: texture
        )
        print("")
        // 10w K · M6 生死
        await runBenchmark(
            label: "10w K（M6 生死核心）",
            renderer: renderer,
            barCount: 100_000,
            visibleCount: 1_000,
            frames: 100,
            texture: texture
        )
        print("")
        print("=== 验收完成 · 详细 GPU 时间走 Instruments → Metal System Trace ===")
    }

    // MARK: - K 模拟数据（random walk · 起价 3000 · ±5 步长）

    static func generateMockBars(_ count: Int, basePrice: Double = 3000) -> [KLine] {
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price = basePrice
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count {
            let drift = Double.random(in: -2...2, using: &rng)
            let open = price
            let close = max(100, price + drift)
            let high = max(open, close) + Double.random(in: 0...3, using: &rng)
            let low = min(open, close) - Double.random(in: 0...3, using: &rng)
            bars.append(KLine(
                instrumentID: "RB",
                period: .minute1,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: 100,
                openInterest: 0,
                turnover: 0
            ))
            price = close
        }
        return bars
    }

    // MARK: - Offscreen 渲染目标

    static func makeOffscreenTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// `sending` 返回类型：标记 descriptor unique-owner · 调用方可直接 send 给 actor（Swift 6 strict concurrency）
    static func makePassDescriptor(texture: MTLTexture) -> sending MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColorMake(0.07, 0.08, 0.10, 1.0)
        return desc
    }

    // MARK: - Benchmark 循环

    static func runBenchmark(
        label: String,
        renderer: MetalKLineRenderer,
        barCount: Int,
        visibleCount: Int,
        frames: Int,
        texture: MTLTexture
    ) async {
        let bars = generateMockBars(barCount)
        let viewport = RenderViewport(
            startIndex: max(0, barCount - visibleCount),
            visibleCount: visibleCount
        )
        let input = KLineRenderInput(bars: bars, viewport: viewport)
        var durations: [TimeInterval] = []
        var lastStats = RenderStats()
        durations.reserveCapacity(frames)
        // 每帧重建 passDescriptor（sending 参数语义 · MTLRenderPassDescriptor 非 Sendable · 不能跨 actor 重复 send）
        // class init 开销极小（几 µs · 远小于 16.67ms 帧预算）
        // 第一帧不算（顶点 buffer 构建 cold path · 单独打印）
        let coldStats = await renderer.renderHeadless(
            input: input,
            passDescriptor: makePassDescriptor(texture: texture)
        )
        let coldMs = coldStats.lastFrameDuration * 1000
        for _ in 0..<frames {
            let stats = await renderer.renderHeadless(
                input: input,
                passDescriptor: makePassDescriptor(texture: texture)
            )
            durations.append(stats.lastFrameDuration)
            lastStats = stats
        }
        let avgMs = durations.reduce(0, +) / Double(durations.count) * 1000
        let maxMs = (durations.max() ?? 0) * 1000
        let minMs = (durations.min() ?? 0) * 1000
        let healthy = durations.filter {
            $0 <= RenderStats.frameBudget60fps + RenderStats.healthyFrameTolerance
        }.count
        print("📊 \(label)")
        print("   bars: \(barCount) · visible: \(visibleCount) · frames: \(frames)")
        print("   cold(顶点构建首帧): \(formatMs(coldMs)) ms")
        print("   avg: \(formatMs(avgMs)) ms · min: \(formatMs(minMs)) · max: \(formatMs(maxMs))")
        print("   60fps 健康: \(healthy)/\(frames) · drawCall: \(lastStats.drawCallCount) · visibleBars: \(lastStats.visibleBarCount)")
        print("   60fps 预算: \(formatMs(RenderStats.frameBudget60fps * 1000)) ms")
        let pass = avgMs <= RenderStats.frameBudget60fps * 1000 && healthy >= frames * 9 / 10
        print("   验收：\(pass ? "🎉 通过" : "⚠️  未达标 · 见 Instruments Metal System Trace 定位瓶颈")")
    }

    static func formatMs(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

#else

@main
struct MetalKLineDemoMain {
    static func main() {
        print("⚠️  Metal 仅在 macOS 可用 · 当前平台跳过 PoC benchmark")
    }
}

#endif
