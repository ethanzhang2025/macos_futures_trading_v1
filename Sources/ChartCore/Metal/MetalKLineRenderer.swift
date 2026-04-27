// ChartCore · WP-20 Metal K 线渲染器（M6 生死核心 PoC）
//
// 设计要点（与 KLineRenderer 协议契约对齐）：
// - actor 隔离：device/commandQueue/pipelineState 持有 + 顶点缓存 _vertexHash 一并隔离
// - 单 vertex layout：position(float2 = [barIndex, price]) + color(float4 = rgba) → 24 bytes/vertex
// - GPU 端 viewMatrix transform · 顶点是逻辑坐标 · zoom/pan 仅更新 4×4 matrix（M6 60fps zoom 关键）
// - 单合批：实体 1 draw call（triangleList · 6 顶点/K）· 影线 1 draw call（line · 2 顶点/K）· 总 drawCall = 2
// - 顶点缓存：K 数据 hash（count + 首/末 close）变化才重建 buffer · 视口变化只更新 matrix
//
// 跨平台约束：
// - 全文件 #if canImport(Metal) 包裹 · Linux 端不参编（保持 swift test 全绿）
// - shader 通过 KLineShaderSource.metalSourceCode 字符串运行时编译（device.makeLibrary(source:)）
//
// 性能验收（PoC 阶段 · MetalKLineDemo / Instruments 上达成）：
// - 1w K 60fps · 10w K 60fps（M6 ¥399/年订阅卖点）· drawCall = 2（独立于 K 数）

#if canImport(Metal)

import Foundation
import Metal
import simd
import Shared
import IndicatorCore
import QuartzCore  // CACurrentMediaTime

public actor MetalKLineRenderer: KLineRenderer {

    // MARK: - 不变状态（init 注入）

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let pixelFormat: MTLPixelFormat

    // MARK: - 可变状态（actor 隔离）

    private var _quality: RenderQuality = .high
    private var _lastStats = RenderStats()

    private var bodyVertexBuffer: MTLBuffer?
    private var wickVertexBuffer: MTLBuffer?
    private var cachedVertexHash = 0
    private var cachedBarsCount = 0

    // MARK: - 顶点结构（与 MSL VertexIn 严格内存对齐 · 24 bytes/vertex）

    private struct KLineVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    // MARK: - 涨跌色（中国期货约定：涨红跌绿）

    private static let upColor = SIMD4<Float>(0.96, 0.27, 0.27, 1.0)   // #F54545
    private static let downColor = SIMD4<Float>(0.18, 0.74, 0.42, 1.0)  // #2DBC6B

    /// K 实体宽度（占 1 单位 bar 的 70% · 留 30% 间距 · 文华惯例）
    private static let bodyWidthRatio: Float = 0.7
    /// 价格 padding（visible priceRange 上下各加 5% · 让 K 不顶到边）
    private static let priceRangePadding: Float = 0.05

    /// Decimal → Float（顶点坐标用 · 6 处共用 · NSDecimalNumber 是 Decimal → Float 唯一标准路径）
    private static func float(_ d: Decimal) -> Float {
        NSDecimalNumber(decimal: d).floatValue
    }

    // MARK: - init

    /// - Parameter pixelFormat: MTKView.colorPixelFormat（默认 .bgra8Unorm）
    public init(pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.metalNotSupported
        }
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.pipelineCreationFailed("makeCommandQueue 失败")
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: KLineShaderSource.metalSourceCode, options: nil)
        } catch {
            throw RenderError.shaderCompilationFailed("\(error)")
        }
        guard let vertexFn = library.makeFunction(name: KLineShaderSource.vertexFunctionName) else {
            throw RenderError.shaderCompilationFailed("vertex function 缺失：\(KLineShaderSource.vertexFunctionName)")
        }
        guard let fragmentFn = library.makeFunction(name: KLineShaderSource.fragmentFunctionName) else {
            throw RenderError.shaderCompilationFailed("fragment function 缺失：\(KLineShaderSource.fragmentFunctionName)")
        }
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFn
        pipelineDesc.fragmentFunction = fragmentFn
        pipelineDesc.colorAttachments[0].pixelFormat = pixelFormat
        // vertex descriptor · 与 MSL `[[stage_in]]` 自动绑定
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float4
        vd.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<KLineVertex>.stride
        vd.layouts[0].stepFunction = .perVertex
        pipelineDesc.vertexDescriptor = vd
        let state: MTLRenderPipelineState
        do {
            state = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            throw RenderError.pipelineCreationFailed("\(error)")
        }
        self.device = device
        self.commandQueue = queue
        self.pipelineState = state
        self.pixelFormat = pixelFormat
    }

    // MARK: - KLineRenderer 协议

    public var quality: RenderQuality { _quality }
    public var lastStats: RenderStats { _lastStats }

    public func setQuality(_ quality: RenderQuality) { _quality = quality }

    /// 暴露 MTLDevice（demo / SwiftUI 桥接需要构造同 device 的 texture / drawable）
    /// nonisolated：MTLDevice 文档保证 thread-safe
    public nonisolated var metalDevice: MTLDevice { device }

    /// 协议 render · 无 drawable 上下文（如纯单元测试 / Linux 占位语义）：
    /// - 仍按 input 重建 vertex buffer（验顶点构造正确性）
    /// - 不实际提交 GPU 命令 · 返回估算 stats（drawCallCount = 2 · visibleBarCount 实际可见）
    /// - Mac UI 渲染走 renderToDrawable(input:passDescriptor:drawable:)
    @discardableResult
    public func render(_ input: KLineRenderInput) -> RenderStats {
        rebuildVertexBuffersIfNeeded(input: input)
        let visible = effectiveVisibleCount(input: input)
        let stats = RenderStats(
            lastFrameDuration: RenderStats.frameBudget60fps,
            drawCallCount: visible > 0 ? 2 : 0,
            visibleBarCount: visible,
            droppedFrameCount: 0
        )
        _lastStats = stats
        return stats
    }

    // MARK: - Mac 实际绘制入口

    /// 提交一帧渲染到 drawable（MTKViewDelegate.draw 主线程拿到 drawable 后调用）
    /// `sending` 标记跨 actor 转移所有权（MTLRenderPassDescriptor / MTLDrawable 非 Sendable · Swift 6 strict 要求）
    @discardableResult
    public func renderToDrawable(
        input: KLineRenderInput,
        passDescriptor: sending MTLRenderPassDescriptor,
        drawable: sending any MTLDrawable
    ) -> RenderStats {
        encodeAndCommit(input: input, passDescriptor: passDescriptor, drawable: drawable)
    }

    /// Headless 渲染（offscreen texture · 用于 benchmark / 截图 / CI）· 不 present · 仅 commit
    /// passDescriptor 由调用方构造 · colorAttachments[0].texture 指向 MTLTexture（非 CAMetalDrawable）
    @discardableResult
    public func renderHeadless(
        input: KLineRenderInput,
        passDescriptor: sending MTLRenderPassDescriptor
    ) -> RenderStats {
        encodeAndCommit(input: input, passDescriptor: passDescriptor, drawable: nil)
    }

    // MARK: - 渲染共享逻辑

    private func encodeAndCommit(
        input: KLineRenderInput,
        passDescriptor: sending MTLRenderPassDescriptor,
        drawable: sending (any MTLDrawable)?
    ) -> RenderStats {
        let frameStart = CACurrentMediaTime()
        rebuildVertexBuffersIfNeeded(input: input)
        let visible = effectiveVisibleCount(input: input)
        guard visible > 0,
              let bodyBuf = bodyVertexBuffer,
              let wickBuf = wickVertexBuffer,
              let cmdBuf = commandQueue.makeCommandBuffer()
        else {
            return _lastStats
        }
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            cmdBuf.commit()  // encoder 失败 · commit 空 buffer 让 GPU 释放资源
            return _lastStats
        }
        encoder.setRenderPipelineState(pipelineState)
        var matrix = makeViewMatrix(input: input, visible: visible)
        encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
        let startBody = input.viewport.startIndex * 6
        let startWick = input.viewport.startIndex * 2
        encoder.setVertexBuffer(bodyBuf, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: startBody, vertexCount: visible * 6)
        encoder.setVertexBuffer(wickBuf, offset: 0, index: 0)
        encoder.drawPrimitives(type: .line, vertexStart: startWick, vertexCount: visible * 2)
        encoder.endEncoding()
        if let drawable { cmdBuf.present(drawable) }
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()  // PoC stats 精确测量 · 生产改 addCompletedHandler 异步
        let stats = RenderStats(
            lastFrameDuration: CACurrentMediaTime() - frameStart,
            drawCallCount: 2,
            visibleBarCount: visible,
            droppedFrameCount: 0
        )
        _lastStats = stats
        return stats
    }

    // MARK: - 内部辅助

    private func effectiveVisibleCount(input: KLineRenderInput) -> Int {
        let avail = max(0, input.bars.count - input.viewport.startIndex)
        return min(input.viewport.visibleCount, avail)
    }

    /// K 数据 hash（count + 首/末 close）· 检测是否需要重建 vertex buffer
    /// （PoC 假设：K 数据 append-only · count 变化 + 末根 close 变化即视为新数据 · 误判率极低）
    private func vertexHash(input: KLineRenderInput) -> Int {
        let count = input.bars.count
        let firstClose = input.bars.first.map { Self.float($0.close).bitPattern } ?? 0
        let lastClose = input.bars.last.map { Self.float($0.close).bitPattern } ?? 0
        var h = count
        h = h &* 31 &+ Int(firstClose)
        h = h &* 31 &+ Int(lastClose)
        return h
    }

    private func rebuildVertexBuffersIfNeeded(input: KLineRenderInput) {
        let hash = vertexHash(input: input)
        if hash == cachedVertexHash, bodyVertexBuffer != nil, wickVertexBuffer != nil { return }
        cachedVertexHash = hash
        cachedBarsCount = input.bars.count
        let halfBar = Self.bodyWidthRatio * 0.5
        var body: [KLineVertex] = []
        var wick: [KLineVertex] = []
        body.reserveCapacity(input.bars.count * 6)
        wick.reserveCapacity(input.bars.count * 2)
        for (i, k) in input.bars.enumerated() {
            let xCenter = Float(i) + 0.5
            let xLeft = xCenter - halfBar
            let xRight = xCenter + halfBar
            let openF = Self.float(k.open)
            let closeF = Self.float(k.close)
            let highF = Self.float(k.high)
            let lowF = Self.float(k.low)
            let color = closeF >= openF ? Self.upColor : Self.downColor
            let yTop = max(openF, closeF)
            let yBot = min(openF, closeF)
            // 实体矩形 · 2 三角形 · triangleList 共 6 顶点
            let lt = KLineVertex(position: SIMD2(xLeft, yTop), color: color)
            let rt = KLineVertex(position: SIMD2(xRight, yTop), color: color)
            let lb = KLineVertex(position: SIMD2(xLeft, yBot), color: color)
            let rb = KLineVertex(position: SIMD2(xRight, yBot), color: color)
            body.append(lt); body.append(rt); body.append(lb)
            body.append(rt); body.append(rb); body.append(lb)
            // 影线 · high → low · line 共 2 顶点
            wick.append(KLineVertex(position: SIMD2(xCenter, highF), color: color))
            wick.append(KLineVertex(position: SIMD2(xCenter, lowF), color: color))
        }
        let bodyBytes = MemoryLayout<KLineVertex>.stride * body.count
        let wickBytes = MemoryLayout<KLineVertex>.stride * wick.count
        bodyVertexBuffer = bodyBytes > 0
            ? device.makeBuffer(bytes: body, length: bodyBytes, options: .storageModeShared)
            : nil
        wickVertexBuffer = wickBytes > 0
            ? device.makeBuffer(bytes: wick, length: wickBytes, options: .storageModeShared)
            : nil
    }

    private func makeViewMatrix(input: KLineRenderInput, visible: Int) -> simd_float4x4 {
        let xLeft = Float(input.viewport.startIndex)
        let xRight = Float(input.viewport.startIndex + visible)
        let priceRange = input.viewport.priceRange ?? derivePriceRange(input: input, visible: visible)
        let yBottom = Self.float(priceRange.lowerBound)
        let yTop = Self.float(priceRange.upperBound)
        let pad = (yTop - yBottom) * Self.priceRangePadding
        return Self.orthographic(left: xLeft, right: xRight, bottom: yBottom - pad, top: yTop + pad)
    }

    private func derivePriceRange(input: KLineRenderInput, visible: Int) -> ClosedRange<Decimal> {
        guard visible > 0 else { return Decimal(0)...Decimal(1) }
        let start = input.viewport.startIndex
        let slice = input.bars[start..<(start + visible)]
        let lo = slice.map(\.low).min() ?? Decimal(0)
        let hi = slice.map(\.high).max() ?? Decimal(1)
        return lo...max(hi, lo + Decimal(1))
    }

    /// 正交投影矩阵（column-major · 与 simd_float4x4 / MSL float4x4 内存布局对齐）
    /// NDC 约定：x [-1, 1] 左→右；y [-1, 1] 下→上；z 透传（顶点 z=0）
    private static func orthographic(left l: Float, right r: Float, bottom b: Float, top t: Float) -> simd_float4x4 {
        let m00 = 2.0 / (r - l)
        let m11 = 2.0 / (t - b)
        let m30 = -(r + l) / (r - l)
        let m31 = -(t + b) / (t - b)
        return simd_float4x4(
            SIMD4<Float>(m00, 0, 0, 0),
            SIMD4<Float>(0, m11, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(m30, m31, 0, 1)
        )
    }
}

#endif  // canImport(Metal)
