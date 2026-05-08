# ChartCore · WP-40 Metal 图表引擎

> 中国期货 Mac/iPad 原生 K 线渲染管线 · 60fps 自研 Metal 引擎 · M6 生死核心卖点

## 一句话定位

**SwiftUI 上层用 `KLineMetalView(renderer:input:)` 即可挂图表 · 内部走 Metal vertex/fragment shader · 单 vertex layout + 合批 drawCall · 10w K 60fps（M2 Pro 实测）**

---

## 模块组成

| 文件 | 职责 | 行数 |
|---|---|---|
| `KLineRenderer.swift` | 协议契约（KLineRenderInput / RenderViewport / RenderStats / RenderQuality） | ~200 |
| `Metal/MetalKLineRenderer.swift` | Metal 渲染核心 · 顶点构建 + GPU encode + 合批 | ~430 |
| `Metal/KLineShaders.metal` | reference 文件（Xcode 浏览 + 高亮） | ~30 |
| `Metal/KLineShaderSource.swift` | shader 字符串 · 运行时 `device.makeLibrary(source:)` 编译 | ~60 |
| `Bridging/KLineMetalView.swift` | Mac NSViewRepresentable 包 MTKView | ~93 |
| `Bridging/KLineMetalView_iOS.swift` | iPad UIViewRepresentable（v15.34 + 与 Mac 镜像） | ~95 |
| `Bridging/KLineGridView.swift` | 5×5 网格背景（SwiftUI Canvas） | ~48 |
| `Bridging/KLineAxisView.swift` | 时间轴 / 价格轴（v15.34 session-aware 智能化） | ~150 |
| `Bridging/KLineCrosshairView.swift` | 十字光标 + OHLC 浮窗 | ~276 |
| `Bridging/KLineSessionDividerView.swift` | session/day 分界竖线（v15.34 P1 新增） | ~115 |
| `Bridging/SessionAxisHelper.swift` | session/day gap 检测 + 夜盘段判定（v15.34 P1 新增） | ~115 |
| `Bridging/DrawingsOverlayView.swift` | 画线叠加层（WP-42 用） | ~389 |
| `Bridging/RenderError.swift` | Metal 异常类型 | ~25 |

---

## 调用方式

### 最简：单图主图

```swift
import ChartCore

let renderer = try MetalKLineRenderer()  // 一次构造 · 复用 device + pipeline
KLineMetalView(
    renderer: renderer,
    input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport),
    clearColor: KLineMetalView.defaultClearColor  // 或 lightClearColor
)
```

### iPad（与 Mac 镜像）

```swift
KLineMetalView_iOS(
    renderer: renderer,
    input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport)
)
```

### 完整图表（K 线 + 十字光标 + 网格 + 时间轴 + session 分界）

```swift
ZStack(alignment: .topLeading) {
    KLineMetalView(renderer: renderer, input: input)
    KLineGridView()
    KLineSessionDividerView(bars: bars, viewport: viewport, gaps: sessionGaps)
    KLineCrosshairView(bars: bars, viewport: viewport, ...)
}
.overlay(alignment: .bottom) {
    KLineAxisView(bars: bars, viewport: viewport, priceRange: priceRange,
                  orientation: .time, sessionGaps: sessionGaps)
        .frame(height: 28)
}
```

---

## 设计决策（按优先级）

### 1. 为何 final class @unchecked Sendable + NSLock，而不是 actor

- MTLRenderPassDescriptor / MTLDrawable 跨 actor 边界触发 Swift 6 SendingRisksDataRace
- NSLock 同步阻塞主线程时间 = 顶点构建 + GPU encode + waitUntilCompleted ~3-5ms（10w K · M2 Pro）
- MTKViewDelegate.draw 同步调用 · 简化 Coordinator · 不开 Task / 不跨 actor

### 2. 单 vertex layout（24 bytes/vertex）

- position(float2 = [barIndex, price]) + color(float4 = rgba)
- 严格 24 bytes stride · 与 MSL VertexIn 对齐
- 不用 SIMD2 + SIMD4：alignment=16 会插 padding · stride 错位 · GPU 读垃圾

### 3. GPU 端 viewMatrix transform

- 顶点是逻辑坐标 · zoom/pan 仅更新 4×4 ortho matrix
- 60fps zoom 关键 · 不重建 vertex buffer
- 顶点缓存：K 数据 hash（count + 首/末 close + indicator name/count）变化才重建

### 4. 合批 drawCall

- K 实体：1 draw call（triangleList · 6 顶点/K）
- 影线：1 draw call（line · 2 顶点/K）
- 每个 indicator 折线：1 draw call（line · 自动跳 nil 邻接）
- 总 drawCall = 2 + N（与 K 数无关）

### 5. fire-and-forget（UI 路径不 wait GPU）

- `renderToDrawable`：commit + present · 不 waitUntilCompleted · 主线程立刻返回
- 拖拽丝滑关键 · GPU 异步并行 · 主线程立即处理下一 drag event
- `renderHeadless`：commit + waitUntilCompleted（benchmark / 截图 / CI 路径）

### 6. session-aware 时间轴（v15.34 新增）

- 基于 bar.openTime 时间戳差自动检测 session/day 缺口（不依赖 ProductTradingHours · 容错强）
- session gap 阈值：> 2 × period（午休 / 夜盘日盘衔接）
- day gap 阈值：> 6h（跨日 / 周末 / 节假日）
- daily 周期不检测（K 周期本身已大）
- 时间标签智能化：可视范围跨日 → "MM-dd HH:mm"，同日 → "HH:mm"
- 标签智能避让：raw 索引落在 gap ±1 → 平移到 gap 后侧

---

## 性能基线（PoC 阶段）

| 场景 | drawCall | 帧时间 | FPS |
|---|---|---|---|
| 1w K | 2 | < 5ms | 60 |
| 10w K（M2 Pro · M6 生死核心） | 2 | < 16.67ms | 60 |
| 10w K + 5 indicators | 7 | < 16.67ms | 60 |
| 6 cell × 10w K（待 Mac 实测） | 12 + 6×N | TBD | 目标 60 |

**Mac 端 benchmark**：`Tools/MetalKLineDemo` CLI · 100 帧 baseline + 帧时分布
**Mac 端窗口 demo**：`Tools/MetalKLineWindowDemo` · 10w K + 双指缩放 + 拖拽

---

## 性能红线（DoD · WP-40 完整验收）

- ✅ 10 万 K 线 60fps
- ⬜ 延迟 < 16ms（Mac 实测待）
- ⬜ 首次交互 < 100ms（Mac 实测待）
- ⬜ 内存 < 500MB（Mac 实测待）
- ✅ session-aware 时间轴（夜盘/日盘分界正确 · v15.34 完工）
- ⬜ 至少支持 6 同屏图表容器（⌘⌥M MultiChartHost 已 done · cell 用 SwiftUI Canvas · 待 Mac 实测决定是否 Metal 化）
- ⬜ Tick < 1ms · 整屏不抖动重绘（Mac 实测待）

---

## 跨平台约束

- 全文件 `#if canImport(Metal)` 包裹
- Linux 端不参编（保 swift test 全绿）
- shader 通过字符串运行时编译（不依赖 .metal compiler）
- `KLineMetalView` 限 macOS / `KLineMetalView_iOS` 限 iOS+iPadOS（macCatalyst 显式排除）

---

## 已知限制 + 待改进

| 限制 | 说明 | 解锁条件 |
|---|---|---|
| 副图 SwiftUI Canvas | 主图 Metal · 副图（MACD/KDJ/RSI/Vol/OBV/CCI/WR/OI 8 种）走 SwiftUI Canvas | Mac 实测 6 副图同屏掉帧时升级 |
| MultiChart cell 用 SwiftUI Canvas | ⌘⌥M 6 cell 同屏走 MultiChartCellCanvas（1518 行 trader 功能） | 同上 · 性能不足时新增 Metal cell 方案 |
| 中间 K 修改不刷新 | bars.count 不变 + 中间数据修改 → 缓存命中 stale buffer（实战 onTick 仅 append-only · 不暴露） | v2 完整 hash（性能成本不值得） |
| 美式期权用 BS 近似 | 不在 ChartCore 范围 · OptionGreeks 内 · 详 `Sources/DataCore/Option/` | v3 接二叉树 / 蒙特卡洛 |

---

## 历史里程碑

- **v15.34（2026-05-08）**：WP-40 P1 session-aware 时间轴完工 + iOS UIViewRepresentable 镜像版 + 完整文档
- **v15.32（2026-05-08）**：MetalKLineRenderer 接入 ChartScene 主图 · 5 indicators 合批
- **v15.16+（2026-05-01）**：viewport / priceRange / hotfix 防一字板 K 除零
- **v6.0（2026-04-26）**：MetalKLineRenderer + KLineShaders + Demo · WP-20 PoC 完工
