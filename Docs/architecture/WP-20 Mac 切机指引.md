# WP-20 Metal K 线 PoC · Mac 切机执行指引

> **Linux 端切机包就绪**（v5.0+ · 2026-04-26）：ChartCore `KLineRenderer` 协议 + 数据契约（RenderViewport / RenderQuality / RenderStats / KLineRenderInput）+ NoOpKLineRenderer 测试占位 + 16 单元测试已就位 · Mac 端 git pull 即可上手 Metal 渲染层。

---

## 0 · 切机前确认（Linux 端最后状态）

| 项 | 值 |
|----|---|
| 最新 commit | （执行 `git log --oneline -1` 查看）|
| 测试基线 | 597+/147+ 全绿（含 ChartCoreTests v2）|
| 加密层 | WP-19b v1+v2 ✅（6 store 加密直通 · brew sqlcipher 必需）|
| ChartCore | 接口骨架 ✅（Linux 可编译 · Metal 实现留 Mac）|
| 真数据 demo | 15 个 ✅（Mac 端 swift run 应全跑通）|

---

## 1 · Mac 物理机切机命令清单

### 1.1 切到 Mac 工作目录

```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
git pull origin main
git log --oneline -3   # 验证最新 commit 与 Linux 一致
```

### 1.2 安装 Mac 端依赖（一次性）

```bash
# SQLCipher（WP-19b 加密层 · 6 store 全部依赖）
brew install sqlcipher

# 验证
pkg-config --modversion sqlcipher   # 期望 >= 4.5.0
```

### 1.3 验证 Linux 端代码在 Mac 仍能编译 + 测试

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3   # 期望 597+/147+ 全绿
```

> ⚠️ **若 sqlcipher 头文件路径与 Linux 不同**，可能需要调 `Sources/CSQLite/shim.h`（Linux 是 `<sqlcipher/sqlite3.h>` · macOS brew 装的可能直接 `<sqlite3.h>`）。优先尝试编译错信息，再决定是否分平台 #if 处理。

### 1.4 跑所有 demo 验证 Mac 行为一致

```bash
swift run SinaTickDemo                 # 真网络 Sina 实时
swift run EndToEndDemo                 # 6 Core 联通 60s
swift run UDSHistoryMergeDemo          # UDS v2 历史合并
swift run IndicatorAlertDemo           # 指标 + 预警联动
swift run WatchlistWorkspacePersistDemo # 持久化端到端
swift run AlertHistorySmokeDemo        # 索引 54.5x 加速
swift run WenhuaCSVImportDemo          # 文华 CSV 解析
swift run JournalGeneratorDemo         # 半自动日志初稿
swift run EncryptionDemo               # SQLCipher 字节对比 · brew sqlcipher 必需
swift run ReviewReplayDemo             # 复盘 + 回放联动
swift run MultiPeriodKLineDemo         # 多周期合成
swift run ReviewSmokeDemo              # 8 聚合算法
swift run ReplaySmokeDemo              # 5 速度 + 3 态
swift run AlertSmokeDemo               # 4 类预警
swift run IndicatorSmokeDemo           # 6 指标真数据
```

期望：15 个 demo 全部 🎉 通过。

---

## 2 · WP-20 Metal K 线 PoC 实施

### 2.1 文件结构（Mac 端新增）

```
Sources/ChartCore/
├── KLineRenderer.swift                   # 已就位（Linux 写好 · Mac-agnostic 接口）
├── Metal/                                # 🆕 Mac 端新建
│   ├── MetalKLineRenderer.swift          # actor · 实现 KLineRenderer
│   ├── KLineShaders.metal                # MSL Shader（vertex + fragment）
│   ├── MetalRenderPipeline.swift         # MTLRenderPipelineState 封装
│   ├── KLineVertexBuffer.swift           # MTLBuffer 管理 · 顶点 layout
│   └── ViewportTransform.swift           # NDC 映射（RenderViewport → MTLViewport）
└── Bridging/                             # 🆕 SwiftUI 集成
    ├── KLineMetalView.swift              # NSViewRepresentable · 包 MTKView
    └── KLineChartView.swift              # SwiftUI 公开组件
```

### 2.2 关键实现要点

#### MetalKLineRenderer（actor）

```swift
import Metal
import MetalKit
import Shared

public actor MetalKLineRenderer: KLineRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var _quality: RenderQuality = .high
    private var _lastStats: RenderStats = RenderStats()

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.metalNotSupported }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.pipelineState = try MetalRenderPipeline.makeDefault(device: device)
    }

    public var quality: RenderQuality { _quality }
    public var lastStats: RenderStats { _lastStats }
    public func setQuality(_ q: RenderQuality) { _quality = q }

    @discardableResult
    public func render(_ input: KLineRenderInput) -> RenderStats {
        let start = CACurrentMediaTime()
        // 1. 生成顶点 buffer（visibleBars × 6 顶点 · OHLC 实体 + 影线）
        // 2. 提交 command buffer + draw indexed
        // 3. 统计 fps + drawCall
        let stats = RenderStats(
            lastFrameDuration: CACurrentMediaTime() - start,
            drawCallCount: 1,  // 单 draw call 合批所有 K 线（性能关键！）
            visibleBarCount: input.viewport.visibleCount,
            droppedFrameCount: 0
        )
        _lastStats = stats
        return stats
    }
}
```

#### KLineShaders.metal（最简骨架）

```metal
#include <metal_stdlib>
using namespace metal;

struct KLineVertex {
    float2 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut kline_vertex(KLineVertex in [[stage_in]],
                                constant float4x4 &viewMatrix [[buffer(1)]]) {
    VertexOut out;
    out.position = viewMatrix * float4(in.position, 0, 1);
    out.color = in.color;
    return out;
}

fragment float4 kline_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
```

### 2.3 性能验收（PoC 阶段）

| 指标 | 目标 | 验收命令 |
|------|------|---------|
| 1w K 线 | 60fps（16.67ms/frame）| `RenderStats.isHealthy60fps == true` × 100 帧连续 |
| 10w K 线 | 60fps | 同上（M6 生死核心 · 必达）|
| 冷启动 | < 1s | 时间从 App 启动到第一帧 render 完成 |
| 内存 | < 500MB（10w K）| Activity Monitor / Instruments Memory |
| 交互响应 | < 100ms（zoom/pan）| 用户交互到 render 完成的 wall-clock |

### 2.4 Instruments 截图清单（M6 提案 / 销售素材）

1. **Time Profiler**：10w K 渲染 · 1 帧 < 16.67ms
2. **Metal System Trace**：drawCall 数量（合批后应是个位数）
3. **Memory**：内存曲线（10w K · 加载 + 渲染 · < 500MB）
4. **Energy Log**：能耗（M2 Pro 应为 Low · 不掉电）
5. **fps 曲线**：60s 滚动 + zoom + pan 交互 · fps 不掉

---

## 3 · 写完后回流 Linux 流程

```bash
# Mac 端
git add -A
git commit -m "WP-20 · MetalKLineRenderer PoC（10w K 60fps）"
git push origin main

# Linux 端（beelink）
cd /home/beelink/macos_tmp/macos_futures_trading_v1
git pull origin main
swift build 2>&1 | tail -5  # 期望 Metal 文件在 Linux 仍能 import 失败优雅处理
```

> ⚠️ **关键设计约束**：Mac 端新增的 `Sources/ChartCore/Metal/*.swift` 必须用 `#if canImport(Metal)` 包裹整个文件内容，否则 Linux 端 swift build 会失败。详见 §2.2 MetalKLineRenderer 顶部应加：
>
> ```swift
> #if canImport(Metal)
> import Metal
> import MetalKit
> // ... 全部 Metal 实现 ...
> #endif
> ```

---

## 4 · M6 生死节点对齐

- **M6 = Pro ¥399/年订阅上线**
- **核心卖点 = Mac 原生 + Metal 流畅图表（10w K 60fps）**
- **WP-20 不达标 = M6 不可能 = 项目战略失败**

PoC 阶段（1-2 周）只需证明 **1w K 60fps** + **架构可扩展到 10w**。完整图表引擎（WP-40）M2-M4 推进 6-8 周。

---

## 5 · 已完成准备（Linux 端 · 2026-04-26）

- ✅ ChartCore 接口骨架（KLineRenderer / RenderViewport / RenderQuality / RenderStats / KLineRenderInput）
- ✅ NoOpKLineRenderer 测试占位（actor · 模拟 60fps stats · 验证协议契约）
- ✅ 16 单元测试（ChartCoreTests · 全 Linux 跑过）
- ✅ 数据契约 Codable + Sendable（跨端 / Codable 持久化基础）
- ✅ 本指引文档（路径 / 命令 / 验收 / Instruments 清单）

---

## 6 · 切机决策

由用户在 Mac 物理机执行 §1 + §2。本指引可在 Mac 端打印或参照。

执行命令：`open Docs/architecture/WP-20\ Mac\ 切机指引.md`（macOS Finder 默认用编辑器打开）。
