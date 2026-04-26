# Stage A 工作包清单 · 中国期货 Mac/iPad 原生交易终端

> **本文档用途**：M0-M9 阶段 A 全部执行任务的主索引。每次会话开工前对照本清单选 WP 推进，完成后更新状态。
>
> **源头**：基于 D1 顶层设计 + D2 Stage A 执行 + D3 风险与危机预案整理而来。任何 D1/D2/D3 决策变动时回本文档同步更新。
>
> **文档版本**：v1.0 · 2026-04-24
> **维护节奏**：M3 / M6 / M9 checkpoint 修订；平时按 WP 推进状态增量更新。

---

## 使用方式

1. **选 WP 开工**：开新会话时说"推进 WP-XX"，我会对照本清单读相关文档后执行
2. **状态标记**：每个 WP 前用 emoji 标状态 —— ⬜ 待开始 / 🟨 进行中 / ✅ 完成 / ⏸️ 暂缓 / ❌ 取消
3. **节拍**：M1 起每月末 Standup 时 review 一次本清单进度（D3 §1）
4. **Legacy 迁移细节**：见独立方案 `Legacy迁移融合方案.md`，本清单只保留 3 个 WP 占位
5. **文档字段约定**：每个 WP 标注「时点 · 负责 · 依赖 · 交付 · DoD · 锚点」六要素（v1.2 起核心工程 WP 增加「禁做」字段）
6. **禁做项参考**：未显式列"禁做"的工程 WP，实施时必须参照 `Claude Code 启动 prompt 模板.md` §"常见禁做项库"
7. **ChatGPT 对应包**：需 Claude Code 编码时，查 `工作包映射表.md` 找对应 `chatgpt_工作包清单/` 独立包，取其启动 prompt 喂入代理

---

## 领域（Epic）总览

| Epic | 名称 | WP 数 | 主时段 | 进度 |
|------|------|------|-------|------|
| E1 | 合规与法律 | 5 | M1 / M5 | 0/5 |
| E2 | 团队与治理 | 4 | M1 | 0/4 |
| E3 | 技术 PoC 与架构基础 | **5** | M1-M2 | **2/5** |
| E4 | Legacy 代码迁移 | 3 | M1-M3 | **1/3** |
| E5 | 产品 · 图表与指标 | 5 | M2-M3 | **5/5**（除 WP-40 Metal 引擎留 Mac）|
| E6 | 产品 · 工作流功能 | 6 | M3-M5 | **4/6** |
| E7 | 产品 · 多端与麦语言 | 5 | M7-M8 | 0/5 |
| E8 | 后端与基础设施 | 5 | M1-M6 | 0/5 |
| E9 | 商业化与支付 | **7** | M3-M6 | 0/7 |
| E10 | 品牌与对外物料 | 5 | M1-M6 | 0/5 |
| E11 | GTM · 冷启动 | 4 | M1-M9 | 0/4 |
| E12 | 运维与事故响应 | 5 | M1-M6 | 0/5 |
| E13 | 死亡率自检与风险管理 | 4 | 全周期月度 | 0/4 |

**合计 63 个工作包**（v1.0: 55 → v1.1: 61 → v1.2: 63，融合 ChatGPT 清单新增 WP-24 Swift Package 骨架 + WP-96 CI benchmark 门禁）。

---

## E1 · 合规与法律

### ⬜ WP-01 · 公司注册与 ICP 备案
- **时点**：M1 Week 1 启动，Week 4 基本就绪
- **负责**：你
- **依赖**：WP-10 股权协议拍板
- **交付**：营业执照、公章、对公银行账户、ICP 备案启动单
- **DoD**：营业执照下来 + 对公账户开通
- **锚点**：D2 §7 Week 1、§9 Phase 0

### ⬜ WP-02 · 金融律师付费咨询
- **时点**：M1 Week 1
- **负责**：你
- **依赖**：无
- **交付**：合规边界纪要，必须专项问清以下 4 点：
  1. 软件提供方定位 + 不下单 Stage A 合规范围
  2. 麦语言兼容话术红线 + 用户协议框架
  3. **CloudKit 境外存储与《个保法》第 40 条个人信息出境规则的冲突**（详 StageA补遗 G1）
  4. **期货软件是否需向中期协备案 + 模拟训练合规边界**（详 StageA补遗 G6）
- **DoD**：1 份律师咨询纪要归档，4 项均有明确结论
- **锚点**：D2 §9 Phase 0、D1 §5、StageA补遗 G1/G6
- **预算**：¥1-3 万

### ⬜ WP-03 · 软件著作权登记
- **时点**：M1 末启动（提交后 1-3 月下证）
- **负责**：你
- **依赖**：WP-01 公司注册
- **交付**：软著证书
- **DoD**：软著受理号下来
- **锚点**：D2 §9 Phase 0

### ⬜ WP-04 · 等保 2.0 预评估
- **时点**：M1
- **负责**：你
- **依赖**：无
- **交付**：等保要求差距清单、初步整改方向
- **DoD**：预评估报告（第三方或自查）
- **锚点**：D2 §9 Phase 0

### ⬜ WP-05 · 用户协议与隐私政策 + Apple 审核防御
- **时点**：M5 上线前
- **负责**：你（主）+ 律师审一次
- **依赖**：WP-02 律师咨询、MVP 清单锁定
- **交付**：
  - 《用户协议》《隐私政策》《个保法合规说明》
  - 《境内数据存储 + 加密实现说明》（分级加密详 StageA补遗 G11：Keychain / SQLCipher / 明文）
  - Apple 金融类 App 审核材料（律师函 / Demo 账号 / Review Notes 中英双语）
  - **Apple 金融类审核拒审 Top 10 对策清单**（详 StageA补遗 G7）
- **DoD**：律师审过 + Apple 审核材料就绪 + 拒审 Top 10 对策落地
- **锚点**：D2 §9 Phase 1、StageA补遗 G7/G11

---

## E2 · 团队与治理

### 🟨 WP-10 · 两人股权与合伙协议（初稿已起草）
- **时点**：M1 Week 1
- **负责**：你 + 合伙人共议，律师出草（可合并到 WP-02）
- **交付**：股权协议（含 vesting / 竞业 / 回购 / 合伙人离开条款）
- **DoD**：双方签字
- **锚点**：D2 §7 Week 1、D3 §7 风险"合伙人离开"
- **已交付**（2026-04-25）：
  - `合伙协议-初稿.md`（44 条 + 4 附件 + 律师 checklist）· 创始人内部协商版
  - 6 个核心参数已拍板：
    - 股权 70/20/10（甲/乙/期权池）
    - Vesting 4+1（双方均适用）
    - Bad/Good Leaver 双档回购（公允价值 = 外部估值或现金净值较低者）
    - 重大事项甲方单方决定 + 30 天通知 + 乙方反对披露权
    - 乙方月薪 ¥1.2w + M6 后业绩奖金 5/10% 分段
    - 通用条款全采用（竞业 24 月 / IP 全归公司 / 永久保密 / 创始人意外条款）
- **下一步**：
  1. 与 Hunter 1 次 60-90 分钟当面会议过条款（预期争议点：单方决定权 / 月薪 / Bad Leaver 标准）
  2. 律师审定（合并 WP-02，预期 5-8 小时）
  3. 律师返修后签字 + 公证 → DoD = ✅

### 🟨 WP-11 · 兼职顾问确定与评审机制（机制设计稿已起草）
- **时点**：M1 Week 1-4
- **负责**：你
- **交付**：1-2 位兼职顾问（产品/设计方向）、周评审节奏约定
- **DoD**：首次周评审召开 + 顾问期权比例敲定
- **锚点**：D2 §7 Week 1、§10 团队分工
- **已交付**（2026-04-25）：
  - `兼职顾问招募与评审机制.md`（10 章 · 招募方向/画像/渠道/期权/评审/续聘）
  - 期权额度规划：核心顾问 0.5-1% × vesting 4+1；外包朋友 0.5-2% × 3+0.5
  - 期权池总分配：顾问 2.5-4% / 外包 3-6% / 后续核心员工 2-3.5%
  - M1 内执行计划：Week 1-2 cold reach / Week 3 试用 / Week 4 签约 + 首次评审
- **下一步**：M1 Week 1-2 启动招募 → Week 4 首次评审 → DoD ✅

### 🟨 WP-12 · 月度 Standup + WAPU 看板机制（模板就绪）
- **时点**：M1 末首次召开，全周期月度
- **负责**：你 + 合伙人
- **依赖**：WP-130 两指标看板
- **交付**：月度 15 分钟 standup 模板、飞书文档归档
- **DoD**：M1 末首次 standup 完成 + 模板沉淀
- **锚点**：D3 §1 死亡率自检、D1 §4 北极星 SOP
- **已交付**（2026-04-25）：
  - `月度Standup与WAPU看板.md`（10 章 · WAPU 定义/2 指标看板/15 min SOP/议程模板/纪要模板/Plan B 触发）
  - 看板模板：TestFlight 周新增 + 累计 Pro 付费数（红/黄/绿三档 × 月份阶梯）
  - 时间锚定：每月最后周五 15:00 / 严格 15 分钟
  - Plan B 触发：任一指标连续 2 月红灯
  - 与 WP-130/131/132/133 联动路径
- **下一步**：M1 Week 2-4 飞书看板 + 模板就绪 → M1 末首次 standup → DoD ✅

### 🟨 WP-13 · 团队分工与协作约定（初稿已起草）
- **时点**：M1 Week 1
- **负责**：你 + 合伙人
- **交付**：分工文件（你=工程+架构+产品，合伙人=Hunter+访谈+运营+客服）、沟通节奏（日常异步 + 每周 1 次 1on1）
- **DoD**：分工文件签字或飞书公开
- **锚点**：D2 §10
- **已交付**(2026-04-25）：
  - `团队分工与协作约定.md`（9 章 · 角色定位/RACI 矩阵 7 类/沟通节奏 5 档/工具栈/决策流程/远程协作/知识管理/利益冲突）
  - RACI 覆盖：工程 / 产品 / 销售运营 / 商业 / 财务法务 / 生死自检 / 不可抗力
  - 沟通节奏：日常异步 + 周 1on1（周一 10:00）+ 月 standup（最后周五 15:00）+ 季度 review（M3/M6/M9）+ 紧急
  - 工具栈：飞书（主）+ GitHub + 微信（紧急备用）
  - 决策流程引用合伙协议 §13-14
- **下一步**：与 Hunter 1 次会议（合并 WP-10/11/12/13 共议）→ 飞书已读确认 → DoD ✅

---

## E3 · 技术 PoC 与架构基础

### 🟨 WP-20 · Metal + SwiftUI K 线渲染 PoC（Linux 切机包 ✅ / Mac Metal 实现待）
- **时点**：M1 Week 2-3
- **负责**：你
- **依赖**：Mac Studio + Xcode + Cursor/Claude 环境
- **交付**：PoC demo（目标 10 万根 K 线 60fps + 滚动缩放流畅）
- **DoD**：实测 10 万根 60fps 通过、延迟 <16ms
- **锚点**：D2 §7 Week 2-3、产品设计书 §3.4 性能基准

**Linux 切机包已交付**（v5.0+ · 2026-04-26）：
- **`Sources/ChartCore/KLineRenderer.swift`**（~150 行 · Metal-agnostic 接口骨架）：
  - `RenderViewport`（startIndex / visibleCount / priceRange · 含 panned/zoomed 操作）
  - `RenderQuality`（balanced / high / ultra · M6 Pro 订阅可解锁 .ultra）
  - `KLineRenderInput`（bars + indicators 预算好的 IndicatorSeries + viewport + quality · 渲染线程不算指标）
  - `RenderStats`（lastFrameDuration / drawCallCount / visibleBarCount / droppedFrameCount · isHealthy60fps 判断）
  - `KLineRenderer` 协议（quality / setQuality / render / lastStats · 全 async）
  - `NoOpKLineRenderer` actor（测试占位 · 模拟 60fps stats · Linux 可跑）
  - `RenderStats.frameBudget60fps` / `.healthyFrameTolerance` 命名常量
- **`Tests/ChartCoreTests/KLineRendererTests.swift`**（+15 测试 +4 suite）：
  - RenderViewport（4 测试 · 默认 clamp / panned / zoomed / Codable）
  - RenderQuality（2 测试 · CaseIterable / rawValue）
  - RenderStats（4 测试 · 默认 / 60fps 健康判断 3 档）
  - NoOpKLineRenderer（5 测试 · setQuality / render 记录 / visible clamp / count 累加）
- **`Docs/architecture/WP-20 Mac 切机指引.md`**：step-by-step 命令清单 · brew sqlcipher 安装 · 15 demo 验证 · MetalKLineRenderer 实施要点 + KLineShaders.metal 骨架 · 性能验收（10w K 60fps + Instruments 截图清单 5 项）· #if canImport(Metal) 包裹模式
- **回归**：592/146 → **607/150 全绿**（基线维持 + 15 新测试）
- **代码质量**：code-simplifier 1 轮过审 · 抽 frameBudget60fps + healthyFrameTolerance 命名常量

**Mac 端待执行**（用户切到 `/Users/admin/...` 后实施 1-2 周）：
- `brew install sqlcipher` 验证 Mac 端 6 store 加密层
- 15 demo Mac 端跑通验证（swift run 各 demo 行为与 Linux 一致）
- `Sources/ChartCore/Metal/MetalKLineRenderer.swift` 实现（actor + MTLDevice/CommandQueue/PipelineState）
- `Sources/ChartCore/Metal/KLineShaders.metal` 顶点 + 片段 shader
- `Sources/ChartCore/Bridging/KLineMetalView.swift`（NSViewRepresentable 包 MTKView）
- 性能验收：1w K 60fps（PoC）→ 10w K 60fps（生死核心）+ Instruments 5 项截图

### 🟨 WP-21 · CTP SimNow 行情订阅 PoC + 数据管线（21a Linux 子集完成）
- **时点**：M1 Week 2-3
- **负责**：你
- **依赖**：SimNow 账号（免费申请）
- **交付**：CTP Level 1 行情订阅 demo、Tick/KLine 数据模型、多周期聚合器、本地缓存、断线重连状态机 v1、统一 DataSource 协议（历史+实时）
- **DoD**：订阅成功 + 数据落到 SwiftUI demo、夜盘日盘分界正确、实时与缓存切换不闪烁
- **禁做**：
  - ❌ 不把历史数据读取和实时流处理写成两套 UI 逻辑
  - ❌ 不先上复杂消息总线（Stage A 单机够用）
  - ❌ 不把多合约订阅串线（必须 contract-id 明确隔离）
- **锚点**：D2 §7 Week 2-3、§4 技术栈、ChatGPT A02

**分阶段策略**（Linux 全验子集 + Mac 真接入）：
- **WP-21a** Linux 全验子集（无真 CTP 库依赖；本会话推进中）
- **WP-21b** Mac 真 CTP 接入（D2 §4 Obj-C++ 桥接路线，留待 Mac 切机）

**WP-21a 已交付**（Sources/DataCore/）：
- **断线重连**（`MarketData/Connection/`）：BackoffPolicy 协议 + ExponentialBackoff（指数退避 + cap + ±jitter + RNG 注入便于测试）+ NoBackoff · ConnectionStateMachine actor（纯状态机：状态转移 + attempt 计数 + AsyncStream 多订阅者推送，不持有 Task / 不主动 sleep / 时间外置 → 测试 100% 确定性）+ reset/reportConnecting/reportConnected/reportDisconnected/reportConnectionLost/reportError 6 事件
- **行情模拟 provider**（`MarketData/Simulated/SimulatedMarketDataProvider.swift`）：actor 实现 MarketDataProvider 协议 + 集成 ConnectionStateMachine + connect/disconnect/simulateConnectionLost/simulateError/push/pushBatch/subscriberCount/isSubscribed · 多合约严格隔离（push 按 instrumentID 精确分发，未订阅静默丢弃）· production-ready 用作 SwiftUI demo 数据源 + 集成测试 fixture + WP-21b 真 CTP 实现的契约参考
- **K 线本地缓存层**（`Cache/`）：KLineCacheStore 协议（load/save/append/clear/clearAll · 顺序保证按 openTime 升序）· InMemoryKLineCacheStore actor（测试 / 临时场景）· JSONFileKLineCacheStore actor（production · 文件路径 `{root}/{sanitized-instrumentID}_{period.rawValue}.json` · iso8601 日期 + sortedKeys 输出 · sanitize 防路径穿越）· merged 静态合并（去重 + 排序 + maxBars 截尾保留最近 N） · KLine 加 Codable conformance（在 Sources/Shared/Models/KLine.swift 原文件加，让自动合成可用）
- **TradingCalendar 完善**（`ContractManager/TradingCalendar.swift`）：expectedTradingDay(actionDay:hour:) 算夜盘归属（hour<3 凌晨夜盘归当日 / hour≥20 夜盘开始归下一工作日 / 其他归 actionDay） · isWeekend(actionDay:) 周末判断 · nextWeekday(after:) 跳周末（周五 → 周一 / 跨月正确）· 不依赖 DateFormatter（无 Sendable 顾虑 + 性能）· 不含节假日表（v2 接 JSON）· chinaCalendar 私有 static let DRY · while 防御死循环
- **统一数据源 Facade**（`DataSource/UnifiedDataSource.swift`）：actor 组装 cache + realtime + KLineBuilder · start(instrumentID:period:) → AsyncStream<DataSourceUpdate> · 工作流：立即 emit .snapshot(cached) → 实时 Tick → KLineBuilder → .completedBar + 增量持久化 · stop/stopAll · 同 (instrumentID, period) 重复 start 自动替换 · 同 instrumentID 多 period 共享 realtime 订阅（最后一个 period stop 才 unsubscribe）· KLine 加 Equatable conformance · v1 不做 historical 合并（HistoricalKLine vs KLine 适配留 v2）
- **数据管线时序图 docs**（`Docs/architecture/data-pipeline.md`）：架构总览 + 4 个 Mermaid 时序图（启动恢复 / 实时流 / 断线重连 / stop 清理）+ 各组件职责对照表 + WP-21b Mac 切机指引（必做 CTPMarketDataProvider Obj-C++ 桥接 / 接口契约位置 / 替换流程 / 真接入后 DoD 验收 5 项）+ 8 项关键设计取舍记录 + 测试覆盖摘要
- **测试**：92 测试 20 suites（退避/状态机/Provider 集成 + Cache 内存/JSON 持久化/合并/sanitize/多合约多周期隔离 + TradingCalendar 边界 36 case + UnifiedDataSource 启动快照 2 / 实时流 2 / 生命周期 3 / 多合约多周期 2）
- **代码质量**：code-simplifier 4 轮过审（子模块 1+2 0 改动 / 3 净 -9 行 / 5 净 0 行 3 处 DRY / 4 净 +1 行 防御 mutation 遍历）
- **commits**：`f28b096` 状态机 + 模拟 provider · `0c63466` · `5ba6069` 缓存层 · `c9ac216` · `9bad509` TradingCalendar · `73c5746` · `4cc72d4` Facade · `86d6631` · 子模块 6 docs 待 commit

**WP-21a 全部 6 子模块完成 ✅**（端到端闭环：cache + realtime + KLineBuilder + ConnectionStateMachine 通过 UnifiedDataSource Facade 完整组装）

**WP-21b 留给 Mac 切机器**：CTP Obj-C++ 桥接层 / CTPMarketDataProvider Swift 实现（替换 SimulatedMarketDataProvider 成为生产数据源）/ SimNow 账号实测 / SwiftUI demo 显示

### ⬜ WP-22 · PoC 结果评估 + MVP 清单锁死
- **时点**：M1 Week 4
- **负责**：你（主）+ 合伙人旁听
- **依赖**：WP-20 / WP-21 / WP-111 访谈完成
- **交付**：PoC 评估纪要、MVP v1 最终锁死清单（基于访谈痛点 Top10 + 付费意愿锚点）
- **DoD**：产品清单一次定稿，M2 起不再随意扩
- **锚点**：D2 §7 Week 4

### ✅ WP-23 · Feature Flag 基础设施（v1）
- **时点**：M2 Week 5
- **负责**：你
- **工作量**：约 1 天
- **交付**：UserDefaults 本地 flag + 远程 JSON 配置读取
- **DoD**：可通过远程 JSON 动态开关任一功能
- **禁做**：不在业务层散落 `if flag.xxx` 判断，统一由门控服务读取
- **锚点**：D2 §2 设计原则、ChatGPT A01

**已交付**（Sources/Shared/FeatureFlags/）：
- **FeatureFlag enum**（`FeatureFlag.swift`）：11 个 flag 分 5 命名空间（subscription / import / replay+review / alert / experimental）+ rawValue 与远程 JSON key 对齐（点号分隔）+ defaultValue（已实现功能默认开 / 商业化+实验性默认关）+ namespace 自动派生
- **Store + Service 体系**（`FeatureFlagService.swift`）：FeatureFlagStore 协议 + 4 实现：
  - InMemoryFlagStore actor（测试驱动）
  - UserDefaultsFlagStore struct @unchecked Sendable（本地 override，自定义 keyPrefix 防冲突）
  - RemoteJSONFlagStore actor（fetcher 闭包注入便于测试不依赖 URLSession，refresh 失败保留缓存，lastFetched 时间戳）
  - CompositeFlagStore（按顺序优先级链 短路返回）
  - FeatureFlagService actor（业务唯一入口 D2 §2 落实，isEnabled 用 ?? 兜底，snapshot 全量查询，makeDefault 默认装配）
- **测试**：18 测试 6 suites（FeatureFlag 默认值 + namespace + Codable / InMemory CRUD / UserDefaults 隔离 suite + key 命名 / Remote refresh 成功+失败+lastFetched / Composite 3 层优先级链 / Service store 命中+miss 用默认值+snapshot+完整链路集成）
- **代码质量**：code-simplifier 1 轮过审 · 净 -1 行（isEnabled 用 ?? 替代 if let 兜底，更直白表达优先级链语义）

**留给后续 WP**：
- 远程 fetcher 接 URLSession 真实 endpoint（需阿里云配置 + 后端 WP-80 提供 JSON）
- UI 设置面板（开发调试用 / Mac SwiftUI）
- 灰度发布按 Cohort 分配（v2，需后端 ID 哈希）
- A/B 测试桩（v2，需事件埋点 WP-87）

**禁做项**（已落实）：
- ✅ 业务层 import Shared 后只调 service.isEnabled(_:)，不直接读 store / UserDefaults / JSON
- ✅ 数据模型层不 import SwiftUI/AppKit
- ✅ 远程 JSON 不依赖第三方库（用闭包注入解耦 URLSession）
- ✅ UserDefaults 内部线程安全（@unchecked Sendable + 注释说明）

### ✅ WP-24 · Swift Package 模块骨架（源自 ChatGPT A01）· 完成 2026-04-24 · commit b1805e1
- **时点**：M1 Week 2-3（与 PoC 同期启动）
- **负责**：你
- **交付**：按业务域拆分的 Swift Package 模块骨架：
  - **ChartCore**（Metal 图表渲染管线）
  - **IndicatorCore**（56 指标 + 麦语言底层函数）
  - **DataCore**（Tick / K 线 / 合约 / 数据源协议）
  - **JournalCore**（交易日志 + 复盘分析）
  - **AlertCore**（条件预警）
  - **ReplayCore**（K 线回放）
  - **WorkspaceCore**（工作区模板 + 自选）
  - **Shared**（跨端共用模型 / 协议 / 工具）
- **DoD**：
  - Monorepo 目录结构就位（macOS App / iPad App / Shared / Backend / docs）
  - 每个 Core 有 README + 至少 1 个示例 API + 单元测试骨架
  - 至少 1 个 Core 被 macOS App 和 iPad App 两端同时引用
  - 新人拉代码后 30 min 内能跑起空 App + 空 Backend
- **禁做**：
  - 不把 UI 状态和业务状态混写在单个 ViewModel
  - 不为 Stage A 未验证需求上重架构（如微服务 / 多租户）
  - 不把业务域边界和 UI 层强耦合
- **锚点**：ChatGPT A01、D2 §4 技术栈

---

## E4 · Legacy 代码迁移（引用独立方案）

### ✅ WP-30 · 直接拷贝 Legacy 5 大模块 · 完成 2026-04-24 · commit 262cd6d（Linux build 全绿，Mac 测试待验）
- **时点**：M1-M2（Legacy 方案 Week 1-2）
- **负责**：你
- **模块**：Shared / FormulaEngine / TradingEngine / KLineBuilder / DrawingTool
- **交付**：模块拷贝进主仓、Swift 6 严格并发适配、单元测试跑通
- **DoD**：原 Legacy 11 个测试全绿 + CI 跑通
- **锚点**：Legacy迁移融合方案.md §4 Week 1-2

### 🟨 WP-31 · 参考改动 Legacy 3 大模块 · 部分完成 · commits 871d950 / 80dc6e2 / WP-31a

**已做**：
- **2026-04-24（WP-31 v1）**：MarketData → MarketDataProvider 协议抽象 + Legacy SinaMarketData 适配 HistoricalKLineProvider + MockMarketDataProvider 测试载体 + 6 合约测试
- **2026-04-25（WP-31a · Sina 实时推送适配 ✅）**：
  - `SinaQuoteFetching` 协议（fetchQuotes 抽象，便于测试注入 stub）
  - `SinaQuoteToTick` 转换（5 档盘口补 0 / 缺失字段兜底 / tradingDay 时间注入）
  - `SinaMarketDataProvider` actor 实现 `MarketDataProvider`（actor 不持 Task / pollOnce 外置驱动 / 失败上报状态机）
  - `SinaPollingDriver` 持续轮询驱动器（production 用，默认 3s 间隔）
  - `UnifiedDataSource.realtime` 解耦：`SimulatedMarketDataProvider` → `any MarketDataProvider`（向后兼容）
  - 22 新测试 / 5 新 suite · Linux swift test 433/117 → **455/122 全绿**
  - **战略意义**：Stage A M1-M3 PoC 阶段不再需要 SimNow / Mac 切机器，11/12 WP 可在 Linux 跑真实合约数据（如 RB0/IF0/AU0）；SimNow 推迟到 M3-M4 配套 WP-54 模拟训练；实盘 CTP 推迟到 M5+

**留到对应 WP**：ContractManager CTP 适配（WP-21b SimNow 真接入推迟 M3-M4）· KLineChartView 拆分（WP-40 Metal 图表主体工作）
- **时点**：M2-M3（Legacy 方案 Week 3-5）
- **负责**：你
- **模块**：MarketData / ContractManager / KLineChartView（985 行拆分 + Metal 重写）
- **交付**：新 Metal 版图表引擎融合原设计思路
- **DoD**：Metal 图表模块能显示基础 K 线
- **锚点**：Legacy迁移融合方案.md §4 Week 3-5

### ⬜ WP-32 · 完全新写模块清单化
- **时点**：M1-M9（贯穿）
- **负责**：你
- **范围**：Metal 图表引擎完整版 / CTP Bridge / 交易日志 / K 线回放 / 工作区模板 / CloudKit / IAP / 用户系统
- **依赖**：各功能 WP（E5-E9）
- **交付**：对应功能 WP 完成即代表新写模块完成
- **锚点**：Legacy迁移融合方案.md §4 Week 6-8 及后续

---

## E5 · 产品 · 图表与指标

### ⬜ WP-40 · Metal 图表引擎（核心差异化）
- **时点**：M2-M4
- **负责**：你
- **依赖**：WP-20 PoC、WP-24 Swift Package 骨架、WP-31 Legacy KLineChartView 融合
- **交付**：全市场合约实时行情、多周期切换（1m/5m/15m/30m/1h/4h/日/周/月）、多窗口布局（最多 6 同屏）
- **DoD**：10 万 K 线 60fps、延迟 <16ms、首次交互 <100ms、内存 <500MB、session-aware 时间轴（夜盘/日盘分界正确）
- **禁做**：
  - ❌ 不在渲染线程算指标（计算/渲染分离）
  - ❌ 不用 WebView 图表库兜底
  - ❌ 不混写 Shader 与 UI 状态
  - ❌ 不把单次 Tick 更新触发整屏重绘
- **锚点**：产品设计书 §3.1 模块①、D2 §2、ChatGPT A03

### ✅ WP-41 · 指标库 v1 · 56 个 · 完成 2026-04-24 · commit 9067d86 + 1a7c828

**实际交付**：**44 真实指标 + 10 期货占位说明 = 54 项**（原 56 扣 2：Andrew's Pitchfork 归 WP-42 画线，Elliott Wave 不做留 Stage C）

**分类完成度**：
- 趋势 10/10 ✅ MA/EMA/WMA/DEMA/TEMA/HMA/VWAP/SAR/Supertrend/ADX
- 震荡 12/12 ✅ RSI/MACD/KDJ/Stochastic/CCI/WR/ROC/TRIX/BIAS/PSY/DMI/CMO
- 量价 8/8 ✅ OBV/Volume/MFI/CMF/VR/PVT/ADL/VOSC
- 波动率 8/8 ✅ BOLL/ATR/KC/Donchian/StdDev/HV/PriceChannel/Envelopes
- 结构 4/6（其余 2 归属调整，见上）
- 期货特有 2/12（OI/ΔOI 真实；10 占位需扩 KLineSeries/FuturesContext 或 Tick 级数据，详 `Sources/IndicatorCore/Indicators/Futures.swift` 顶注）

**测试**：28 个指标测试（12 第一批 + 16 第二批）· swift test 136/35 全绿 0.127s

**code-simplifier 过审**：2 轮（第一批 intValue / MACD 去冗余；第二批 nextEMA / slidingSum 消重复）
- **时点**：M3
- **负责**：你（AI 批量生成骨架 + 对照 TradingView/文华手动校验）
- **依赖**：FormulaEngine（Legacy）、WP-24 IndicatorCore 模块
- **交付**：10 趋势 + 12 震荡 + 8 量价 + 8 波动率 + 6 结构 + **12 期货特有**
- **DoD**：全部 56 个指标可叠加到图表、期货 12 个数据口径正确
- **禁做**：
  - ❌ 不把指标计算绑进渲染线程（必须异步）
  - ❌ 不重复实现已存在于 Legacy FormulaEngine 的函数
  - ❌ 期货特有 12 指标数据口径不得和国内主流终端偏差 > 1%
- **锚点**：D2 §2、产品设计书 §3.1 模块②、ChatGPT A04

### ✅ WP-42 · 画线工具 v1 · 数据模型层完成 2026-04-24 · commit b41acc9

**已交付**（Sources/Shared/Drawings/）：6 类型枚举（trendLine/horizontalLine/rectangle/parallelChannel/fibonacci/text）+ DrawingPoint（barIndex+Decimal 价格）+ Drawing 平铺 struct（Codable/Sendable/Identifiable）+ 6 类型安全 factory + DrawingGeometry（线段插值 / 矩形归一化 / 斐波那契 7 档 / 平行通道副线 / priceDistance）+ 12 测试

**留给 WP-40**：屏幕像素级 hit-test · Metal 渲染 · 颜色/线型样式
**禁做**：✅ 数据模型层不 import SwiftUI（Sources/Shared 跨端层）

### ✅ WP-43 · 自选管理（数据模型层 v1）
- **时点**：M2
- **负责**：你
- **交付**：多分组（无上限）+ 每组合约无上限 + 拖拽排序
- **DoD**：CloudKit 数据结构预埋、本地完整可用
- **锚点**：D2 §2

**已交付**（Sources/Shared/Watchlists/）：Watchlist struct（id/name/sortIndex/instrumentIDs/timestamps · Codable/Sendable/Identifiable/Hashable）+ WatchlistBook 聚合根（按 sortIndex 维护有序性 · 自动 normalize 连续整数）+ 分组级 CRUD（add/rename/remove/moveGroup）+ 合约级 CRUD（add/remove + 同组去重）+ 拖拽排序（同组 moveInstrument(in:from:to:) + 跨组 moveInstrument(_:from:to:targetIndex:) 含目标去重）+ 查询（contains/group(id:)/groups(containing:)）+ 通用 moveElement<T> 私有泛型函数（语义同 SwiftUI onMove）· CloudKit 字段映射预埋（cloudKitRecordType/CloudKitField 常量/cloudKitFields()/init?(cloudKitRecordName:fields:) · 不 import CloudKit · Linux 跨端兼容）· 25 测试 7 suites（CRUD/拖拽/去重/边界/Codable 往返/CloudKit 字段往返）· code-simplifier 1 轮过审

**留给后续 WP**：拖拽 UI（SwiftUI/AppKit DnD）· 实际 CloudKit 同步（A12 M7-M9：CKContainer/CKSubscription/冲突合并）· 本地持久化层（SQLite/JSON 文件，归 WP-19 数据持久化）
**禁做**：✅ 数据模型层不 import SwiftUI/AppKit/CloudKit（Sources/Shared 跨端层）· ✅ 不只存 UI 截图式快照，存结构化数据

### ✅ WP-44 · 多周期切换 + 多窗口布局（数据模型层 v1）
- **时点**：M2-M3
- **负责**：你
- **交付**：9 个周期快捷切换、最多 6 窗口同屏、键盘快捷键全覆盖
- **DoD**：窗口布局保存到工作区模板（WP-55）
- **锚点**：D2 §2、D1 §3 原则 5 键盘一等

**已交付**（Sources/Shared/Workspaces/）：
- **PeriodSwitcher**（`PeriodSwitcher.swift`）：default9Periods（1m/5m/15m/30m/1h/4h/日/周/月）+ defaultShortcut(for:) → Cmd+1~9 + period(forShortcut:) 反查 + defaultShortcutMap 一次性注册集 · digitKeyCodes 数组硬编码 Apple HID Usage 顺序（1-9 keyCode 不连续）· 数据层只承担"映射数据"，UI 层负责实际键盘事件绑定
- **WindowGridPreset**（`WindowGrid.swift`）：6 网格预设（single / horizontal2 / vertical2 / grid2x2 / grid2x3 / grid3x2）· dimensions 单一信息源（rows × cols 派生 maxWindows）· layout(forWindowCount:) 返回 0..1 归一化 LayoutFrame（先列后行）· applyTo([WindowLayout]) 替换 frame 保留其他字段 · 多余窗口自动截断
- **测试**：22 测试 4 suites（PeriodSwitcher 8 case：9 周期顺序/Cmd 边界/非默认 nil/反查/modifier 校验/正反查闭环 + WindowGridPreset 14 case：6 case 全枚举/maxWindows/dimensions/各预设布局/边界 0/负数/超出 max/applyTo 三 case）
- **代码质量**：code-simplifier 1 轮过审 · 净 -7 行（maxWindows 由 dimensions 派生，单一信息源）

**留给后续 UI WP**：实际键盘事件绑定（NSEvent 监听 + 触发周期切换）· 多窗口同屏渲染（SwiftUI/AppKit 多 NSWindow + frame 桥接 CGRect）· 窗口拖拽 + 调整大小（与 WP-40 Metal 图表协作）· 网格预设切换动画
**禁做**：✅ 数据模型层不 import SwiftUI/AppKit/CoreGraphics · ✅ 不实际绑定键盘事件 · ✅ 不算具体像素尺寸（只算 0..1 归一化）

---

### ✅ UnifiedDataSource v2 · 历史 K 线合并（v5.0+ · cache + historical provider 启动合并去重）

- **来源**：UDS v1 注释明确写"留 v2 做 HistoricalKLineProvider 历史合并"；UI 启动场景实战必备（开图表立刻看到完整历史 K + 实时合成最新一根）
- **改动**：仅 `Sources/DataCore/DataSource/UnifiedDataSource.swift` 一文件
- **已交付**：
  - `init` 加 `historical: (any HistoricalKLineProvider)? = nil` 可选注入（默认 nil = 行为同 v1）
  - `start` 内 `loadHistorySnapshot` helper：拉历史 K + 与 cache 合并去重 → yield 单次 `.snapshot(merged)`
  - **合并语义**：按 openTime 字典键去重，**cache 优先**（cache 经 KLineBuilder 严格合成，比 historical 原始数据可靠）
  - **失败静默回退**：historical fetch 失败 / 不支持的 period（仅 minute5/minute15/hour1）→ 不阻断启动，回退到仅 cache snapshot
  - **支持 period**：minute5(=5min) / minute15(=15min) / hour1(=60min) · 对齐 Sina 历史 K 周期；其他 period 跳过 historical
  - HistoricalKLine → KLine 转换：date 字符串 Asia/Shanghai 解析（3 种格式 fallback "yyyy-MM-dd HH:mm:ss" / "HH:mm" / "yyyy-MM-dd"）
- **测试**：+7 测试 +1 suite（UnifiedDataSource v2 · 历史 K 线合并）
  - nilHistoricalSameAsV1（v1 兼容）
  - emptyCachePlusHistorical（cache 空时拉 historical）
  - overlapCachePreferred（重叠 openTime · cache 优先）
  - historicalFetchFailureFallsBack（fetch 失败静默回退）
  - unsupportedPeriodSkipsHistorical（minute1 不查历史）
  - mergedSnapshotRespectsCacheMaxBars（截尾应用合并后）
  - intervalMinutesMapping（5/15/60 映射）
- **回归**：556/139 → **563/140 全绿**（v1 已有 WP-44b/WP-44c 测试不破坏）
- **代码质量**：code-simplifier 1 轮过审 · 确认无可改（4 个 static helper 单一职责 + double-guard 各承担一类回退）
- **使用**：`UnifiedDataSource(cache: …, realtime: provider, historical: SinaMarketData())` · UI 层启动直接获得完整历史 + 实时拼接

---

### ✅ WP-44c · MarketDataProvider 同合约多 handler 字典（端到端 demo 暴露问题修复）

- **来源**：v5.0+ 端到端业务流 demo 暴露——同合约不能同时被 UnifiedDataSource + AlertEvaluator 订阅（原 `handlers[id] = handler` 字典覆盖语义）
- **范围**：协议 + 3 个 provider 实现 + UDS 四处协同改动
- **已交付**：
  - `MarketDataProvider` 协议：`subscribe` 改 `@discardableResult` 返回 `SubscriptionToken`（typealias UUID）+ 新增 `unsubscribe(_:token:)` 精确退订；保留 `unsubscribe(_:)` 清空合约语义
  - 3 个实现统一改 `[String: [SubscriptionToken: handler]]` 字典：`SinaMarketDataProvider` / `SimulatedMarketDataProvider` / `MockMarketDataProvider`（pollOnce/push 内 `for handler in bucket.values { handler(tick) }`）
  - `UnifiedDataSource` 保存 `realtimeTokens: [String: SubscriptionToken]`，cleanup 用 token 精确退订（不再调 `unsubscribe(_:)` 误清同合约其他模块的 handler）
  - 新增内省 API `handlerCount(for:)`（同合约多订阅者计数）
- **测试**：+6 测试 / +1 suite（`WP-44c 多 handler`）：sameInstrument/byToken/lastToken/unsubscribeAll/mixed/unknownToken
- **回归**：527 → **533 测试 / 134 → 135 suite 全绿**（向后兼容：原协议方法签名保持，加 `@discardableResult` 老 caller 不破）
- **demo 受益验证**：`Tools/EndToEndDemo` 段 3 改用 RB0 + IF0（替换原 AU0/IF0），RB0 同时被 UDS + AlertEvaluator 订阅；运行时 `handlerCount(for: "RB0") == 2` + 单次 HTTP 拉取 bucket 内 2 handler 都收 tick + RB0 必触发预警 ×2 全过
- **代码质量**：code-simplifier 1 轮过审 · 净改动 2 行（`isSubscribed` 表达式简化）· actor 隔离边界保持 · 跨 actor 重复代码不硬抽（actor 不支持继承）

**留待**：CTPMarketDataProvider（WP-220 Stage B）按同协议实现即可

---

### ✅ 端到端业务流真数据冒烟（v5.0+ 跨 5 Core 集成 demo · 第 7 个真数据 demo）

- **位置**：`Tools/EndToEndDemo/main.swift` · `swift run EndToEndDemo`（60s 真网络）
- **拓扑**：段 1 自选簿 + sina.fetchMinute60KLines × 3 合约 + IndicatorCore 末值 / 段 2 UnifiedDataSource(cache + RB0 .second30) 实时合成 / 段 3 SinaProvider 直订 RB0+IF0 → AlertEvaluator 真触发 + history 落库
- **共享**：1 个 SinaMarketDataProvider + 1 个 SinaPollingDriver；WP-44c 修复后 RB0 同时被 UDS + AlertEvaluator 订阅（同合约多 handler）
- **6 Core 联通**：Shared(Watchlist) ✅ + DataCore-Sina ✅ + DataCore-UDS ✅ + IndicatorCore ✅ + AlertCore ✅ · code-simplifier 1 轮过审
- **暴露 → 修复**：同合约多订阅暴露 SinaProvider.subscribe 字典覆盖问题 → WP-44c 已修（多 handler 字典 + token 化退订）
- **回归**：527/134 → 533/135 swift test 全绿（demo 不带测试，executableTarget 不入测试套）

---

### ✅ ContractStore + ProductSpecLoader 真数据冒烟（v5.0+ · 第 16 个真数据 demo · DataCore 矩阵补全）

- **位置**：`Tools/ContractStoreDemo/main.swift` · `swift run ContractStoreDemo`（~1s 纯本地）
- **拓扑**（5 段）：
  - 段 1 · 嵌入 5 品种 JSON（RB/IF/AU/CU/MA · 覆盖 SHFE+CFFEX+CZCE 三大所）
  - 段 2 · ProductSpecLoader.load → 5 ProductSpec
  - 段 3 · generateContracts(months: [1, 5, 10]) → 15 合约
  - 段 4 · ContractStore 查询全套（get / byProduct / byExchange / search / mainContract）
  - 段 5 · 跨 Core 乘数校验（与 WenhuaCSVImportDemo / PositionMatcher 实战一致）
- **真验证**（夜盘 14:48）：
  - 5 品种解析 + 15 合约生成 ✅（rb201/rb205/rb210 / if201/if205/if210 / MA01/MA05/MA10 等）
  - 5 种查询全部命中 ✅
    · get("rb201") → 螺纹钢201 · 乘数 10
    · byProduct("RB") → 3 合约
    · byExchange SHFE/CFFEX/CZCE → 9/3/3 合约
    · search("黄金") + search("HS") → 各 3 合约（productName + pinyinInitials 匹配）
    · mainContract → rb205（持仓量 120k 最高 · 与 50k/80k 对比）
  - 5 个乘数全过 ✅（RB×10 / IF×300 / AU×1000 / CU×5 / MA×10）
  - 🎉 通过
- **价值**：
  - DataCore demo 矩阵补全（之前 demo 都用硬编码 multipliers · 这次完整加载链路）
  - 5 大交易所典型品种 instrumentID 生成规则文档化（CZCE 大写 / 其他小写 · 当前 API 硬编码年首位 "2"）
  - 验证 ContractStore 5 种查询模式可用（productID 大写约定 + 拼音首字母搜索 + 主力合约持仓量）
- **代码质量**：code-simplifier 1 轮过审 · simple-executor 修编译错（productID 大写 + 适配 instrumentID 格式 + 去冗余 await · final class 不是 actor）
- **回归**：607/150 swift test 全绿（基线维持）

---

### ✅ JournalGenerator 半自动日志初稿真数据冒烟（v5.0+ · 第 14 个真数据 demo · 文华没有的差异化能力）

- **位置**：`Tools/JournalGeneratorDemo/main.swift` · `swift run JournalGeneratorDemo`（~1s 纯本地）
- **拓扑**（5 段）：
  - 段 1 · 构造 7 笔 3 合约 trades（RB d1 三段时段 / IF d2-d3 三笔 / AU d2 单笔）· 跨 3 天分散
  - 段 2 · 默认 8h 窗口生成草稿 · 详细打印第 1 条（title / reason 模板 / tradeIDs.count）
  - 段 3 · windowSeconds 配置对比（1h / 8h / 24h）→ 7 / 6 / 3 完美递减
  - 段 4 · A09 禁做项 ② 验证（generator 调 3 次后 trades == tradesBefore · 单向引用）
  - 段 5 · 总结
- **真验证**（夜盘 2026-04-26 14:43）：
  - 段 2 默认 8h 生成 6 条草稿（按 createdAt 倒序）：IF[1][2][3] 各独立 / AU[4] / RB[5] 22:30 单独 / RB[6] 09:30+14:00 合并
  - 段 3 配置对比：**1h=7 / 8h=6 / 24h=3 完美递减** ✅
  - 段 4 trades 集合在 3 次 generateDrafts 后保持不变 ✅（A09 禁做项 ② 落实）
  - 🎉 通过
- **价值**：
  - 演示 P3 文华迁移用户的差异化能力："导入交割单后自动生成日志草稿"（文华没有）
  - 验证 windowSeconds 不同配置对聚合行为的影响（用户可按交易风格调整）
  - 验证 A09 禁做项 ②（generator 单向，journal.tradeIDs 不污染 trades）
  - JournalCore 端到端用户旅程：CSV → Trade → ClosedPosition + **TradeJournal 草稿**
- **代码质量**：code-simplifier 1 轮过审 · 段 4 改用数组循环 + 抽 tradeTimeFormatter static let 复用（避免每笔 mk 新建 DateFormatter）
- **回归**：586/145 swift test 全绿（基线维持）

---

### ✅ 文华交割单 CSV 真实样本解析真数据冒烟（v5.0+ · 第 13 个真数据 demo · P3 文华迁移核心通路）

- **位置**：`Tools/WenhuaCSVImportDemo/main.swift` · `swift run WenhuaCSVImportDemo`（~1s 纯本地）
- **拓扑**（5 段）：
  - 段 1 · 嵌入文华 5.0 格式 CSV 字符串（5 笔成交：RB2510 多 + IF2506 空 + AU2510 多未平）
  - 段 2 · DealCSVParser.parse(.wenhua) → [RawDeal]（CSV 行 1:1 映射 · 全 String 字段）
  - 段 3 · RawDeal.toTrade() 显式转换边界 → [Trade]（A09 禁做项 ① 落实：中文「买/卖/开/平」→ Direction/OffsetFlag enum）
  - 段 4 · PositionMatcher.match + ReviewAnalytics（monthlyPnL / profitLossRatio / instrumentMatrix）
  - 段 5 · 负向场景（缺列 / 非法 direction `购买` / 非法成交价 `not-a-number` 三档 · DealCSVError 显式可感知）
- **真验证**（夜盘 2026-04-26 14:43）：
  - 段 2 解析 5 条 RawDeal ✅
  - 段 3 转 5 笔 Trade（含中文 → enum 转换）✅
  - 段 4 FIFO 配对：闭合 2 笔 + 未平 1 组 · RB +1591 / IF +20995.40（IF300 倍乘数）/ 月度总盈 22586.40 ✅
  - 段 5 三个负向场景全部抛 DealCSVError ✅
    · `missingColumn(name=开平, line=1)`
    · `invalidValue(field=买卖, value=购买, line=2)`
    · `invalidValue(field=成交价, value=not-a-number, line=2)`
  - 🎉 通过
- **价值**：
  - 验证 P3 文华迁移用户首要场景（"我能把文华历史交易导进来吗？"）
  - A09 禁做项 ① 转换层（RawDeal → Trade）显式可见
  - 多合约多 multiplier（RB=10 / IF=300 / AU=1000）真实数据验证
  - DealCSVError 4 类全覆盖（除 .invalidEncoding 需特殊编码场景）
- **代码质量**：code-simplifier 1 轮过审 · 净 -3 行（错误测试用 `[(label, work)]` 数组循环消除 3 段重复）
- **回归**：586/145 swift test 全绿（基线维持）

---

### ✅ AlertHistory 时间区间查询真数据冒烟（v5.0+ · 第 12 个真数据 demo · 索引性能验证 54.5x）

- **位置**：`Tools/AlertHistorySmokeDemo/main.swift` · `swift run AlertHistorySmokeDemo`（~20s 含 10000 条注入）
- **拓扑**（5 段）：
  - 段 1 · 注入 50 条历史（5 个 alertID 轮询 · 时刻分布 24h 内 · 每 28.8min 一条）
  - 段 2 · 区间查询 3 档（最近 1h / 6h / 24h）
  - 段 3 · 负向场景（from > to 返空 · 不抛错）
  - 段 4 · 性能压测（10000 条注入 + 区间查询耗时）
  - 段 5 · 索引命中对比（SQL BETWEEN + idx_alert_history_ts vs allHistory + Swift filter）
- **真验证**（夜盘 2026-04-26 14:41）：
  - 区间命中：1h=3 条 / 6h=13 条 / 24h=50 条 · 递增 ✅
  - 注入 10000 条耗时：~17s（actor hop × 10000 next）· 单条 ~1.7ms
  - 区间查询性能：1h=16ms / 6h=69ms / 24h=552ms（数据量越大耗时越多）
  - **索引加速比 54.5x**（11.37ms vs 619.30ms · 同样取 1h 区间 417 条）✅
  - 🎉 通过
- **价值**：
  - 验证 `idx_alert_history_ts` 索引在 SQLite 层真实生效（54.5x 不会撒谎）
  - 确认 UI 历史面板"最近 7 天"等区间查询场景在万级数据下毫秒级响应
  - 演示 Karpathy 第 4 要点"可验证成功标准"（性能数据替代主观判断）
- **Swift 6 严格并发修复**：`timed<T: Sendable>(@Sendable () async throws -> T)` · 闭包跨 main actor 边界须 Sendable
- **代码质量**：code-simplifier 1 轮过审 · 净 1 处简化（samples 抽常量消除 min(3, count) + prefix(3) 重复）
- **回归**：586/145 swift test 全绿（基线维持）

---

### ✅ Watchlist + Workspace 持久化端到端真数据冒烟（v5.0+ · 第 11 个真数据 demo · WP-19a-5/6 验收）

- **位置**：`Tools/WatchlistWorkspacePersistDemo/main.swift` · `swift run WatchlistWorkspacePersistDemo`（~1s 纯本地）
- **拓扑**（5 段）：
  - 段 1 · 准备临时 SQLite 文件路径（不依赖 Sina 网络）
  - 段 2 · 写入：WatchlistBook 3 组 9 合约（核心 / 备选 / 套利）+ WorkspaceBook 3 模板（盘前 / 盘中（激活，2 窗口）/ 盘后）+ Cmd+1 快捷键 · save + close
  - 段 3 · 模拟进程重启 · 重新打开同 path → load 验证完整往返（==）
  - 段 4 · 文件大小内省（各 8192 字节 = SQLite 默认页大小 · 数据 < 几 KB）
  - 段 5 · 负向场景 · 脏 JSON 触发 `WatchlistBookStoreError.decodeFailed`（不静默吞数据）
- **真验证**（夜盘 23:38）：
  - WatchlistBook load 完整往返 ✅（3 组 9 合约逐字恢复）
  - WorkspaceBook load 完整往返 ✅（含 templates / windows / shortcut / activeTemplateID 全字段）
  - 脏 JSON 显式抛 decodeFailed ✅（UI 层可感知 · 不丢数据）
  - 🎉 通过
- **价值**：验证 WP-19a-5/6 在 production-like "持久化 → 进程退出 → 重启 → 恢复" 链路工作 · UI 启动恢复自选 + 工作区铺路 · UI 层数据契约就绪
- **代码质量**：code-simplifier 1 轮过审 · 确认无可改（do-catch + bool 标志在 Result(catching:) 不支持 async 闭包约束下已最简）
- **回归**：586/145 swift test 全绿（基线维持）

---

### ✅ IndicatorCore + AlertCore 联动真数据冒烟（v5.0+ · 第 10 个真数据 demo · 6 Core 全闭环）

- **位置**：`Tools/IndicatorAlertDemo/main.swift` · `swift run IndicatorAlertDemo`（~70s 真网络）
- **拓扑**（5 段）：
  - 段 1 · UDS v2 加载 200 根历史 K → IndicatorCore 计算初始 MA20=3186.75
  - 段 2 · 注册 2 预警（静态 priceAbove 必触发 / 动态 priceCrossAbove 跟随 MA20）+ 2 真通道（ConsoleChannel + FileChannel）
  - 段 3 · 跑 60s · WP-44c 同合约 UDS + Alert 双订阅 · UDS .completedBar → 重算 MA20 → updateAlert（保留 lastTriggeredAt）
  - 段 4 · 触发统计 + FileChannel log 文件读回末 N 行
  - 段 5 · 6 Core 联通校验
- **6 Core 全闭环**：Shared + DataCore-Sina + DataCore-UDS v2 + IndicatorCore + AlertCore + AlertChannels（Console + File）全部真落地
- **真验证**（夜盘 23:55 跑通）：
  - 静态预警必触发 1 次（priceAbove(3136.75)）→ 触发 stream + console stdout（`[ALERT-CN] [2026-04-26 13:55:30] 🔔 ...`）+ FileChannel log 文件 1 行
  - history 落库 1 条 · 动态预警 0 次（价格未跨 MA20，符合预期）
  - 🎉 通过
- **代码质量**：code-simplifier 1 轮过审 · 净 +5 行（抽 makeDynamicAlert helper 收口 7 字段不变量）
- **修复**：KLine.openInterest(Decimal) → KLineSeries.openInterests([Int]) 类型差 + 三层 Optional 表达式编译挂掉 · 共 2 个手术式修复
- **回归**：575/144 swift test 全绿（基线维持）

---

### ✅ UDS v2 历史合并真数据冒烟（v5.0+ · 第 9 个真数据 demo · v1 vs v2 对比）

- **位置**：`Tools/UDSHistoryMergeDemo/main.swift` · `swift run UDSHistoryMergeDemo`（~70s 真网络 · 60s 等实时 + 网络拉历史）
- **拓扑**：
  - 段 1（v1 基线对照）：UDS 不注入 historical → snapshot 0 根（cache 空 + 无 historical 兜底）
  - 段 2（v2 历史合并）：注入 `SinaMarketData` 作为 historical → snapshot 200 根真实历史 K · 时间范围 03-09 14:15 ~ 04-24 23:00 · 起 3,114.00 → 末 3,194.00
  - 段 3（实时拼接）：跑 60s SinaPollingDriver 3s 间隔 · 跨周期时 yield .completedBar 增量
- **跨 Core 一致性校验**：snapshot 末尾 close=3,194.00 · Sina 实时 last=3,193.00 · 差 1.00（夜盘价差正常）
- **输出对比验证**：v1=0 vs v2=200 → 启动即有完整历史 K（UI 层"开图表立刻有完整图"实战必备）
- **代码质量**：code-simplifier 1 轮过审 · printSample 合并 head/tail 重复 + 3 个 formatter 抽 static let（避免每次调用 alloc · 段 3 60s 内调几十次的优化）
- **回归**：563/140 swift test 全绿

---

### ✅ 复盘 + 回放联动真数据冒烟（v5.0+ 跨 3 Core 集成 demo · 第 8 个真数据 demo）

- **位置**：`Tools/ReviewReplayDemo/main.swift` · `swift run ReviewReplayDemo`（~3s 真网络 + 本地回放）
- **拓扑**：拉 Sina RB0 60min K 线最近 80 根 → 基于真实 K 收盘价 + 时间动态构造 7 笔模拟成交（4 段：3 闭合 + 1 未平仓）→ 同一组 trades 同时驱动两条业务流
  - 段 1（JournalCore）：PositionMatcher.match → ClosedPosition[] → ReviewAnalytics 5/8 个聚合算法（monthlyPnL / pnlDistribution / winRateCurve / profitLossRatio / sessionPnL）
  - 段 2（ReplayCore）：trades → TradeMark[] → ReplayPlayer.load(bars, marks) → 8x 回放（每 30ms 一根 K · 80 根 ≈ 2.4s）→ 每 K emit 时 player.tradeMarksAtCurrentBar 查询 + 标注打印
  - 段 3（跨 Core 一致性）：trade 总数 == TradeMark 标注命中数 ✅ + ClosedPosition.openPrice/closePrice ⊆ trades 价位集合 ✅ + 价位锚定真实 K close ✅
- **3 Core 联通**：DataCore-Sina（fetchMinute60KLines）✅ + JournalCore（FIFO 配对 + 5 聚合算法）✅ + ReplayCore（5 档速度 + TradeMark 时间窗匹配）✅
- **价值**：为 M4 复盘界面"图表 + 成交点叠加"准备数据流契约；同一交割单驱动两条业务流，任何一边跑偏会被对方暴露
- **代码质量**：code-simplifier 1 轮过审 · 净 -12 行（链式调用 / count(where:) / map(\\.price) / allSatisfy 等 Karpathy 偏好）
- **回归**：533/135 swift test 全绿（基线维持）
- **v2 ReplayDriver 集成**（v5.0+ · 2026-04-26）：段 2 手动 for 循环 stepForward 升级为 `ReplayDriver(player, baseInterval=0.24)` · driver.start + Task.sleep(3s 安全余量) + driver.stop · 末尾自动停（cursor.isAtEnd=true / player .paused / driver.isRunning=false）· ReplayDriver 首次正式纳入 demo 生态（之前仅 unit test 验证）

---

## E6 · 产品 · 工作流功能

### ✅ WP-50 · 复盘分析 v1 · 8 张图（数据计算层）
- **时点**：M4
- **负责**：你
- **依赖**：WP-53 交易日志（数据源）或 CSV 导入
- **交付**：月度盈亏 / 分布直方 / 胜率曲线 / 品种矩阵 / 持仓时间 / 最大回撤 / 盈亏比 / 时段分析
- **DoD**：8 图均可从交割单 CSV 生成
- **锚点**：D2 §2、产品设计书 §3.1 模块④、ChatGPT A09

**已交付**（Sources/JournalCore/）：
- **ClosedPosition + PositionMatcher**（`ClosedPosition.swift` + `PositionMatcher.swift`）：PositionSide enum（long/short）+ ClosedPosition struct（开+平 trades + 持仓时长 + 已实现 PnL + 总手续费）+ PositionMatcher.match(trades:multipliers:) FIFO 配对算法（按 (instrumentID, side) 队列；多空方向自动推导 buy-open→long / sell-open→short；4 种平仓 flag 全识别 close/closeToday/closeYesterday/forceClose；部分平仓拆 ClosedPosition；跨多笔开仓拆配对；手续费按手数比例分摊）+ OpenRemaining 未平仓快照
- **8 张图数据契约**（`ReviewChartData.swift`）：MonthlyPnLBucket+MonthlyPnL / PnLDistributionBin+PnLDistribution / WinRatePoint+WinRateCurve / InstrumentMatrixCell+InstrumentMatrix / HoldingDurationBucket+HoldingDurationStats / EquityPoint+MaxDrawdownCurve / ProfitLossRatio / TradingSlot+SessionPnLBucket+SessionPnL · 全 Codable Sendable Equatable
- **8 张图聚合算法**（`ReviewAnalytics.swift`）：8 个静态方法（monthlyPnL 跨月聚合 + pnlDistribution 单遍分桶+正负计数 + winRateCurve 累计胜率 + instrumentMatrix 按合约聚合排序 + holdingDurationStats 6 桶分布 + 中位/均值/min/max + maxDrawdownCurve 三变量状态机 + profitLossRatio 含 0 兜底 + sessionPnL 4 时段+other）+ Asia/Shanghai 时区注入
- **测试**：23 测试 9 suites（FIFO 配对 10 case：空/多空 PnL/FIFO 顺序/部分平仓/跨多笔开仓/多合约隔离/手续费分摊/平今平昨强平识别/multiplier fallback + 8 图各自典型场景：跨月聚合/分布桶/胜率曲线 0.75/品种矩阵排序/持仓时间 median/最大回撤区间识别/盈亏比 ratio=2/4 时段聚合）
- **代码质量**：code-simplifier 1 轮过审 · 净 -1 行（closeSide switch 编译器穷尽校验 / pnlBeforeFees 直接 switch 删 IIFE / pnlDistribution 单遍统计省 2×O(N) 扫描 / 显性注释）

**留给后续 UI WP（Mac 切机）**：8 图 SwiftUI/Metal 渲染（折线 / 柱状 / 直方 / 矩阵热图）· 时段分析配 TradingCalendar 完整集合竞价支持 · 年度/季度切换聚合
**留给 v2**：分布直方支持自适应 binSize（基于 IQR）· 持仓时间支持自定义桶 · 复合指标（夏普 / Sortino / Calmar）· 标签维度交叉分析（按 JournalEmotion / JournalDeviation 切片）
**禁做**：✅ 数据计算层不 import SwiftUI/AppKit/Charts · ✅ 金额必须 Decimal 不用 Double（精度）· ✅ FIFO 配对手续费按手数比例分摊（不直接累加全额）· ✅ 单 trade 拆多 ClosedPosition（不强行合并）

### ✅ WP-51 · K 线回放（数据模型层 v1）
- **时点**：M4
- **负责**：你
- **交付**：历史日期+品种选择、回放控制（播放/暂停/2x-8x 加速/倒退/单步）、当日成交点叠加
- **DoD**：任意合约任意日期均可回放、帧率稳定
- **锚点**：D2 §2、产品设计书 §3.1 模块⑤、ChatGPT A07

**已交付**（Sources/ReplayCore/）：
- **ReplayPlayerTypes**（`ReplayPlayerTypes.swift`）：ReplaySpeed 5 档（x05/x1/x2/x4/x8 + multiplier）+ ReplayState 3 态（stopped/playing/paused）+ ReplayDirection（forward/backward）+ ReplayCursor（currentIndex/totalCount/progress/isAtEnd/isAtStart）+ ReplayUpdate 4 case（barEmitted/stateChanged/seekFinished/tradeMarks）+ TradeMarkSide（buy/sell）+ TradeMark（id/instrumentID/time/price/side/volume）
- **ReplayPlayer**（`ReplayPlayer.swift`）：actor 包装 + load(bars:tradeMarks:) 自动按 openTime 升序 + play/pause/stop（仅在 playing 时 pause；stop 重置 cursor）+ stepForward(count:)/stepBackward(count:) 边界 clamp + 实际推进数返回 + 末尾 stepForward 自动 paused（A07 验收）+ seek(to:) clamp + emit seekFinished 不 emit bar + setSpeed/setDirection 配置 + cursor/currentBar/currentState 查询 + tradeMarksAtCurrentBar 时间窗 [openTime, nextOpen)（最后一根用 .distantFuture 开放右边界）+ AsyncStream<ReplayUpdate> 多订阅者 + broadcast helper DRY + pauseIfPlayingAtEnd helper 自动暂停语义集中
- **测试**：23 测试 8 suites（ReplaySpeed/Cursor/TradeMark Codable + 加载（空/N/乱序）+ 状态转移（play 需 loaded/pause 仅 playing/stop 重置）+ 步进（默认 1/N/末尾 clamp/末尾继续 0/起点 clamp）+ seek（指定/越界/当前 noop）+ speed/direction 设置 + AsyncStream 推送序列 + seek 推 seekFinished + TradeMark 时间窗（含 openTime 边界 + 不同 instrument 不串线））
- **代码质量**：code-simplifier 1 轮过审 · 净 -7 行 DRY（broadcast helper 消除 3 处订阅者遍历重复 + pauseIfPlayingAtEnd 集中"playing 末尾必 paused"语义）

**留给后续 UI WP**：回放控制栏 UI（播放/暂停按钮 / 速度滑块 / 进度条）· 成交点叠加层（SwiftUI/Metal 渲染，复用图表代码）· 实时↔回放数据源切换（UnifiedDataSource 注入 ReplayPlayer 适配器）· CSV 历史数据导入
**禁做**：✅ A07 不为回放复制图表代码（提供 KLine 流，UnifiedDataSource 切换数据源）· ✅ 数据模型层不持有 Timer/Task（时间外置）· ✅ 不 import SwiftUI/AppKit/CoreGraphics

**Timer 驱动器已交付**（v5.0+ · 2026-04-26）：
- **`Sources/ReplayCore/ReplayDriver.swift`**：actor 包 Task 自动循环 stepForward · ~55 行
  - init(player, baseInterval=1.0)：注入 ReplayPlayer + 1x 速度下每步基础间隔（默认 1s · UI 60fps 可设 0.016）
  - start：启动 Task.detached 循环 · 每步动态读 player.currentSpeed → 间隔 = baseInterval / multiplier · setSpeed 不需重启 driver，下一步循环自动应用
  - 自动停 3 条件（任一）：① player.currentState != .playing（pause/stop 后）② stepForward(count:1) == 0（末尾）③ 显式 stop()/cancel
  - 重复 start 自动 cancel 旧 task（防双 task 抢推进）
  - max(0.001, ...) 兜底防极端 multiplier 死循环
- **测试**：+7 测试 +1 suite（ReplayDriver · Timer 自动驱动）：cursor 推进 / 末尾自动停 + player .paused / pause 后 driver 自动停 / 重复 start 不双 task / setSpeed 动态切换 / stop 立即停 / isRunning 内省
- **回归**：575/144 → **582/145 全绿**
- **代码质量**：code-simplifier 1 轮过审 · 净 -2 行（Task.sleep(for: .seconds) 替代 nanoseconds 字面量魔术 · isRunning 单行 ?.isCancelled == false）
- **修订路线图**：原"留给后续 UI WP"中的"Timer 驱动器（60fps DisplayLink）"已交付（数据层 60fps 即 baseInterval=0.016s × x1 = 16ms）· UI 层只需 SwiftUI 按钮调 driver.start/stop

### ✅ WP-52 · 条件预警中心（数据模型层 v1）
- **时点**：M4
- **负责**：你
- **交付**：价格预警 / 画线预警 / 波动率成交量异常、统一面板、通知渠道（App 内 / 通知中心 / 声音）、历史记录
- **DoD**：3 类预警均可配置触发、无漏发
- **锚点**：D2 §2、产品设计书 §3.1 模块⑥、ChatGPT A08

**已交付**（Sources/AlertCore/）：
- **Alert 数据模型**（`Alert.swift`）：AlertCondition 6 类（priceAbove/Below/CrossAbove/CrossBelow + horizontalLineTouched + volumeSpike + priceMoveSpike）+ AlertStatus 4 态（active/triggered/paused/cancelled）+ NotificationChannelKind 3 渠道（inApp/systemNotice/sound）+ Alert struct（id/name/instrumentID/condition/status/channels/cooldownSeconds/timestamps）+ canTrigger(at:) 状态+冷却查询
- **AlertHistory**（`AlertHistory.swift`）：AlertHistoryEntry struct（含 conditionSnapshot 触发瞬间快照）+ AlertHistoryStore 协议 + InMemoryAlertHistoryStore actor（按 triggeredAt 降序）
- **NotificationChannel 统一层**（`NotificationChannel.swift`，A08 禁做项落实）：NotificationEvent + NotificationChannel 协议 + LoggingNotificationChannel（默认 + 注入 logger 便于测试）+ NotificationDispatcher actor（注册/移除/选择性广播；按 Alert.channels 过滤）
- **AlertEvaluator**（`AlertEvaluator.swift`）：actor 包装 onTick(_:now:) 主驱动 + addAlert/removeAlert（联动清 history）/updateAlert（保留 lastTriggeredAt 不被覆盖）/pauseAlert/resumeAlert（仅 paused→active）+ 滑动窗口（volume capacity 1000 / price 时间 3600s）+ 频控冷却（A08 验收硬要求"边界不重复疯狂触发"）+ AsyncStream<AlertTriggeredEvent> 推送 + dispatcher 联动 + 时间外置 now 注入
- **测试**：27 测试 9 suites（Alert 数据契约 + Codable / AlertHistory CRUD / NotificationChannel + Dispatcher 选择性广播 / Evaluator CRUD 含 updateAlert 保留频控 / 价格 6 子类含 cross 边界不重复 / 频控冷却 60s 边界 / volumeSpike 6 期均值倍数 / priceMoveSpike 时间窗口百分比 / 多 alert 多合约隔离 / removeAlert 联动 / 通知 dispatcher 联动选择性）
- **代码质量**：code-simplifier 1 轮过审 · 净 -3 行（命名 tuple `outcome` / `abs(move)` / 删除 `.triggered → .active` 假动作 / averageVolume 窗口语义清晰化 / NotificationChannel 注入指引）

**留给后续 UI WP**：实际通知通道（InAppOverlayChannel SwiftUI / SystemNoticeChannel UserNotifications / SoundChannel NSSound 留 Mac 切机）· 预警面板 UI（列表 + 编辑 + 启停按钮）· 画线预警 v2（趋势线/矩形/斐波那契接 DrawingGeometry，本 v1 仅 horizontalLine）· 后续 SQLite AlertHistoryStore（WP-19 数据持久化）
**禁做**：✅ 通知发送逻辑统一在 NotificationChannel 层，不散落（A08 验收）· ✅ 数据模型层不 import SwiftUI/AppKit/UserNotifications · ✅ 不引入 print 散落生产路径（默认 logger 仅供测试）· ✅ 频控不依赖 wall-clock 真实时间（now 参数注入 → 100% 确定测试）

**AlertHistory 时间区间查询已交付**（v5.0+ · 2026-04-26 · UI 历史面板必需）：
- **协议**：`AlertHistoryStore` 加 `history(from: Date, to: Date) async throws -> [AlertHistoryEntry]`（[from, to] 闭区间，按 triggeredAt 降序）
- **InMemory 实现**：`guard from <= to else { return [] }` + filter + sorted 降序
- **SQLite 实现**：`WHERE triggered_at BETWEEN ? AND ?` 命中现有 `idx_alert_history_ts` 索引（O(log N) 查询）
- **边界一致性**：from > to 双实现都返回空数组（不抛错）；from = to 命中精确时刻
- **测试**：+4 测试（区间命中降序 / from=to 闭区间 / from>to 返空 / 空 store 返空）· 双实现等价
- **回归**：582/145 → **586/145 全绿**
- **代码质量**：code-simplifier 1 轮过审 · SQLite 抽 file-private `toMs/fromMs` helper（与 JournalCore 项目惯例一致 · 消除 4 处魔数 1000）

**Linux 通道 v1 已交付**（v5.0+ · 2026-04-25）：
- **NotificationChannelKind 扩展**：原 3 case（inApp/systemNotice/sound）+ 2 新 case（**console / file**）· rawValue 与 case 名对齐（向后兼容旧 JSON）
- **`Sources/AlertCore/Channels/ConsoleChannel.swift`**：`struct` · stdout 调试通道 · 注入 prefix / timestampFormatter / writer · static let DateFormatter 复用（每次 send 不 alloc）
- **`Sources/AlertCore/Channels/FileChannel.swift`**：`actor` · 本地文件追加日志 · FileHandle seekToEnd · 显式 close() · close 后 send 静默 noop · 跨实例打开同 path 追加不覆盖
- **测试**：+12 测试 +4 suite（ConsoleChannel 3 / FileChannel 5 / Dispatcher 集成 2 / NotificationChannelKind 扩展 2）
- **回归**：563/140 → **575/144 全绿**
- **代码质量**：code-simplifier 1 轮过审 · 抽 static let timestampFormatter（与 SinaQuoteToTick / DealCSVParser 项目惯例一致）· actor 不能继承 / 跨文件 helper 不抽 · 无可改时明说
- **流程修订**：本次开始严格执行 simplifier → build → test → run（一次到位）顺序，避免重复跑 build/test
- **AlertCore 闭环**：NotificationDispatcher → LoggingChannel + **ConsoleChannel + FileChannel**（Linux 端通知通道 v1 完整）· macOS UserNotifications + NSSound 仍留 Mac 切机时做

### ✅ WP-53 · 交易日志（数据模型层 v1 · 最强粘性）
- **时点**：M5
- **负责**：你
- **交付**：交割单 CSV 导入（含文华格式适配）、半自动日志生成、手动补原因/情绪、标签+搜索、月度/季度总结
- **DoD**：文华交割单可无损导入、日志沉淀跨会话稳定
- **禁做**：
  - ❌ 不把原始交割单数据直接当业务模型使用（必须有 Trade 标准模型做转换层）
  - ❌ 不让日志编辑反向污染成交记录（一对多映射单向）
  - ❌ 日志内容不出 SQLCipher 加密边界
- **锚点**：D2 §2、产品设计书 §3.1 模块⑦、ChatGPT A09

**已交付**（Sources/JournalCore/）：
- **Trade 标准模型**（`Trade.swift`）：Trade struct（id/tradeReference/instrumentID/direction/offsetFlag/price/volume/commission/timestamp/source）+ TradeSource enum（wenhua/generic/manual）+ notional(volumeMultiple:) 计算 · 复用 Shared.Direction/OffsetFlag（已加 Codable）
- **CSV 解析器**（`DealCSVParser.swift`，A09 转换层落实）：RawDeal struct（CSV 行 1:1 映射，全 String 字段）+ DealCSVFormat enum（wenhua/generic）+ DealCSVError 4 类（invalidEncoding/missingColumn/invalidValue/unsupportedFormat）+ DealCSVParser.parse(_:format:) → [RawDeal]（兼容 LF/CRLF/CR + 跳空行 + 表头校验）+ RawDeal.toTrade() 显式转换边界 + 中文/英文 direction/offset 双格式支持 + 3 种时间格式解析（ISO8601/yyyy-MM-dd HH:mm:ss/yyyyMMdd HHmmss）
- **TradeJournal 模型**（`TradeJournal.swift`）：JournalEmotion 5 类（confident/hesitant/fearful/greedy/calm）+ JournalDeviation 8 类（asPlanned/breakStopLoss/chaseRebound/chaseHigh/catchFalling/earlyExit/overTrade/other）+ TradeJournal struct（id/tradeIDs 单向引用/title/reason/emotion/deviation/lesson/tags Set/timestamps）
- **JournalStore 持久化协议**（`JournalStore.swift`）：JournalStore 协议 11 方法（trades 5：saveTrades/loadAll/forInstrumentID/from-to/delete · journals 6：save/loadAll/byID/from-to/withAnyTag/delete）+ InMemoryJournalStore actor + 加密策略契约文档化（trades 明文 / journals 走 SQLCipher 留 WP-19）
- **JournalGenerator 半自动初稿**（`JournalGenerator.swift`）：generateDrafts(from:configuration:now:) → [TradeJournal] · 按 (instrumentID, 时间窗口默认 8h) 聚合 · 自动 title/tradeIDs/reason 模板（含开/平/总手数/手续费统计）· 单向：不修改 trades · Configuration 注入便于测试
- **测试**：26 测试 7 suites（Trade Codable + notional + Source 枚举 / 文华 CSV 解析 + toTrade + 缺列/非法值/空行 / 通用 CSV / TradeJournal Codable + 默认值 + 5+8 枚举 / Store Trade CRUD + 合约/时间范围筛选 / Store Journal CRUD + tag 搜索 + 删 journal 不级联删 trade / Generator 空/同合约连续/跨窗口拆分/多合约/统计模板/不修改 trades）
- **代码质量**：code-simplifier 1 轮过审 · 净 0 行（splitCSVLine `\.isNewline` 兼容 LF/CRLF/CR 三种行尾，原 `"\r\n"` Character 比较永远为假是隐藏 bug）

**留给后续 UI WP**：交割单导入面板（文件选择 + 格式识别 + 错误展示）· 日志编辑器 UI（情绪/偏差选择器 + 标签输入）· 月度/季度总结聚合器 · CSV 引号转义解析 v2 · 标签搜索引擎（v1 用 contains，v2 上倒排索引）
**留给 WP-19 数据持久化**：SQLCipherJournalStore（journals 字段加密列存储）· trades 可走 SQLite 明文表
**留给 WP-50 复盘 8 图**：基于 JournalStore 提供的 trades 数据生成 8 张分析图
**禁做**：✅ A09 三大禁做项全落实（RawDeal→Trade 显式转换边界 / tradeIDs 单向引用日志改不污染 trades / SQLCipher 加密边界协议层文档化）· ✅ 数据模型层不 import SwiftUI/AppKit/SQLCipher · ✅ 不引入第三方库

### ⬜ WP-54 · 模拟训练（SimNow）
- **时点**：M5
- **负责**：你
- **依赖**：WP-21 SimNow 账号
- **交付**：SimNow 仿真接入 + 独立虚拟账户 + 训练模式（历史场景+操作评分）+ 纪律检查
- **DoD**：模拟盘下单、成交、持仓、结算链路走通
- **锚点**：D2 §2、产品设计书 §3.1 模块⑧

### ✅ WP-55 · 工作区模板（数据模型层 v1）
- **时点**：M3
- **负责**：你
- **交付**：多窗口布局保存、多套模板快速切换（盘前/盘中/盘后）、快捷键一键切换、CloudKit 同步
- **DoD**：3+ 模板可保存 / 切换无闪烁
- **锚点**：D2 §2、产品设计书 §3.1 模块⑨

**已交付**（Sources/Shared/Workspaces/）：LayoutFrame（跨端 Rect · 避开 CGRect）+ WorkspaceShortcut（keyCode/modifierFlags 数据表示，不绑定平台键码常量）+ WindowLayout（id/instrumentID/period/indicatorIDs/drawingIDs/frame/zIndex · 引用 WP-42 Drawing UUID）+ WorkspaceTemplate.Kind 4 种（preMarket/inMarket/postMarket/custom）+ WorkspaceTemplate（id/name/kind/windows/shortcut/sortIndex/timestamps）+ WorkspaceBook 聚合根（templates/activeTemplateID + addTemplate/renameTemplate/removeTemplate/duplicateTemplate（深拷贝 windows · 不复制快捷键）/moveTemplate/setActive/updateTemplate（保留 id/sortIndex/createdAt 刷新 updatedAt）/setShortcut（全局唯一性强制：抢占清空旧绑定）+ 查询（template(id:)/templates(of:)/template(forShortcut:)）+ 通用 moveElement<T> 私有泛型函数（语义同 SwiftUI onMove，与 WP-43 同模式）· KLinePeriod Codable extension（rawValue: String 自动满足）· CloudKit 字段映射预埋（cloudKitRecordType/CloudKitField/cloudKitFields/init?(cloudKitRecordName:fields:) · windows 用 Codable JSON 嵌入 String 字段避免 CKReference 复杂性 · 不 import CloudKit · Linux 跨端兼容）· 29 测试 9 suites（LayoutFrame/WindowLayout/Template/Book CRUD/激活切换/快捷键唯一/查询/Codable 往返/CloudKit 字段往返）· code-simplifier 1 轮过审

**留给后续 WP**：UI 切换动画 + 键盘绑定（NSEvent → WorkspaceShortcut 解析）+ CGRect 桥接 → 后续 UI WP；实际 CloudKit 同步（A12 M7-M9：CKContainer/CKSubscription/冲突合并）；本地持久化层（WP-19 SQLite/JSON）；多窗口同时渲染由 WP-44 + WP-40 联合实现
**禁做**：✅ 数据模型层不 import SwiftUI/AppKit/CoreGraphics/CloudKit · ✅ 不只存 UI 截图式快照，存结构化 windows + frames · ✅ 不实际绑定键盘事件（数据层只存数据表示）

---

## E7 · 产品 · 多端与麦语言

### ⬜ WP-60 · CloudKit 数据结构预埋 + UI 同步
- **时点**：M1-M6 预埋，M7 UI 启用
- **负责**：你
- **依赖**：WP-84 合规方案落地
- **交付**：M1-M6 所有功能数据结构预留 CloudKit 字段；M7 上线自选 / 模板 / 日志三项同步（日志需按 WP-84 方案确认能否走 CloudKit）
- **DoD**：两台设备双向同步无冲突
- **禁做**：
  - ❌ 不把敏感数据（交易日志内容 / 账户关联 / 资金快照）放 CloudKit（境外合规）
  - ❌ 不做无冲突策略的同步（最简 Last-Write-Wins + 冲突日志）
  - ❌ 不把 CloudKit Schema 和本地 SQLite Schema 强耦合（需抽象转换层）
- **锚点**：D2 §2、D2 §6 M7 milestone、ChatGPT A12/B08

### ⬜ WP-61 · iPad 基础版
- **时点**：M7
- **负责**：你
- **交付**：基础同步看盘、多周期切换、自选、图表（不做完整专业工作流）
- **DoD**：Mac 数据同步到 iPad 后可正常看盘
- **锚点**：D2 §2 M7-M9、D1 §2.5 差异化

### ⬜ WP-62 · 麦语言基础版 30-50 函数
- **时点**：M8
- **负责**：你
- **依赖**：Legacy FormulaEngine（已 ~90% 完成 · v6.0+ 第 1 批扩展 5 函数）
- **交付**：覆盖 MA/EMA/MACD/KDJ/BOLL/RSI/CCI 等主流指标所需函数、用户可运行自定义指标公式
- **DoD**：用户从文华复制 30-50 个常见公式均可运行、结果与文华一致
- **禁做**：
  - ❌ 不宣传"100% 兼容文华"（法律红线，详 D1 §5）
  - ❌ 不逆向文华二进制格式（只解析公开文本语法）
  - ❌ 不把麦语言解析与指标底层函数实现耦合（IndicatorCore 既服务原生指标也服务麦语言）
- **锚点**：D2 §2 M7-M9、Legacy迁移融合方案.md、ChatGPT A12
- **已交付**（v6.0+ · 2026-04-26 · 麦语言扩展第 1 批 · 51 → 56 函数 · 兼容度 85% → ~90%）：
  - **新增 5 函数**（端到端通过 Lexer → Parser → Interpreter 跑公式验证）：
    - `LogicFunctions.swift`：**NOT**（逻辑非）+ **CROSSDOWN**（下穿 · 与 CROSS 对称）
    - `MathFunctions.swift`：**MOD**（取模 · floor 风格 · B=0 安全降级 nil）
    - `StatFunctions.swift`：**PEAKBARS** / **TROUGHBARS**（距最近波峰/波谷的 bar 数 · 状态机式扫描 · 与 BARSLAST 同模式）
    - `BuiltinFunction.swift`：注册 5 函数到 `BuiltinFunctions.all`
  - **设计取舍**：
    - MOD floor 风格（Python/Decimal 数学一致 · -7 MOD 3 = 2 · 注释说明）
    - PEAKBARS/TROUGHBARS 双实现保留（不抽 helper · 闭包反而增层 · Karpathy "避免过度复杂"）
    - 测试 helper（run / testBars）项目惯例不共享 · 接受重复
  - **测试**：+10 测试 +1 suite · `Tests/IndicatorCoreTests/FormulaEngineTests/MaiYuYanExtensionTests.swift` · Linux swift test 617/151 → **627/152 全绿** 1.028s
  - **代码质量**：code-simplifier 1 轮过审（测试 nil 检查改 for-value 风格 + MOD NSDecimalRound 注释对齐 CEILING/FLOOR）
  - **后续批次预留**：BACKSET / VARIANCE / REVERSE / WINNER / COST 等剩 ~10% 函数（按用户实际复制的文华公式遇到时按需扩展）

### ⬜ WP-63 · 文华麦语言公式（.wh）导入（源自 StageA补遗 G4）
- **时点**：M8（与 WP-62 同期）
- **负责**：你
- **依赖**：WP-62 麦语言引擎
- **交付**：`.wh` 文本公式文件批量导入 + 解析 + 编译；失败公式给出明确错误定位
- **DoD**：文华典型公式 20 个测试用例全绿
- **锚点**：StageA补遗 G4、Legacy迁移融合方案.md

### ⬜ WP-64 · 文华自选列表导入（源自 StageA补遗 G4）
- **时点**：M8
- **负责**：你
- **交付**：`.wh5` 格式解析（若逆向复杂则降级为手动粘贴合约代码列表）；导入后自动创建分组
- **DoD**：导入 50+ 合约自选无丢失、合约代码映射正确
- **锚点**：StageA补遗 G4

---

## E8 · 后端与基础设施

### ⬜ WP-80 · Go 后端服务 skeleton
- **时点**：M1-M2
- **负责**：你
- **交付**：用户注册 / 订阅状态查询 / feature flag 下发三接口
- **DoD**：服务跑在本地，接口可 curl 通
- **锚点**：D2 §4 后端层

### ⬜ WP-81 · 生产数据库（PostgreSQL）
- **时点**：M4-M5
- **负责**：你
- **交付**：生产 PG 实例（阿里云单节点）+ Schema + 备份
- **DoD**：后端连通、备份策略跑起来
- **锚点**：D2 §4

### ⬜ WP-82 · 阿里云国内部署
- **时点**：M5 上线前
- **负责**：你
- **交付**：境内单节点 + CDN + SSL + Sentry 接入
- **DoD**：后端域名解析可访问、HTTPS 证书 OK
- **锚点**：D2 §4

### ⬜ WP-83 · 审计日志系统
- **时点**：M4-M6
- **负责**：你
- **交付**：用户操作 / 订阅状态变更 / 关键系统事件全量审计
- **DoD**：任一事件可回查 + 保留 ≥ 1 年
- **锚点**：D3 §5 预埋基础设施

### ⬜ WP-84 · CloudKit 合规方案落地（源自 StageA补遗 G1）
- **时点**：M4-M5（律咨结论后启动）
- **负责**：你
- **依赖**：WP-02 律师咨询结论
- **交付**：按 StageA补遗 G1 三备选任一落地：
  - 方案 A（推荐）：CloudKit 只存非敏感数据（UI 布局 / 自选），敏感数据（交易日志 / 预警）阿里云自建同步
  - 方案 B：完全阿里云自建；方案 C：出境评估（不推荐）
- **DoD**：数据分层实现 + 两端同步验证 + 隐私政策对应更新
- **锚点**：D2 §4、StageA补遗 G1、产品设计书 9.2

### 🟨 WP-19 · 数据持久化 SQLCipher（19a ✅ / 19a-5/6 ✅ / 19b v1 ✅ / 19b v2 ✅ · 留 v3 迁移+keychain）
- **时点**：M3-M5（M5 上线前必备 · 容量 + 加密双需求）
- **负责**：你
- **交付**：4 个 Store 升级到 SQLite + SQLCipher 加密层
  - KLineCacheStore（DataCore）· JournalStore（JournalCore）
  - AlertHistoryStore（AlertCore）· AnalyticsEventStore（Shared/Analytics）
- **DoD**：4 store 全部 SQLite 持久化 + SQLCipher 加密 + Linux/Mac 双端验证
- **锚点**：多 WP 引用"留 WP-19"（WP-43 §持久化 / WP-52 §AlertHistory / WP-53 §JournalStore / WP-55 §持久化 / WP-133 §schema）
- **已交付**（2026-04-25 · WP-19a 客户端 SQLite 全集 ✅ Linux 全验）：
  - **基础设施**（commit a1d792f）：
    - `Sources/CSQLite/` · systemLibrary 包装 sqlite3 C API（Linux libsqlite3-dev / macOS 系统自带）
    - `Sources/Shared/SQLite/` · SQLiteConnection actor（exec/query/executeReturningRowID/Changes）+ SQLiteValue + SQLiteStatement + SQLiteError
  - **4 个 SQLite Store 实现**：
    - `Sources/Shared/Analytics/Stores/SQLiteAnalyticsEventStore.swift`（events 表 + 协议合约 11 测试）
    - `Sources/DataCore/Cache/SQLiteKLineCacheStore.swift`（klines 表 + 复合主键去重 + maxBars 截尾 + 9 测试）
    - `Sources/JournalCore/SQLiteJournalStore.swift`（trades + journals 双表 + JSON 数组字段 + 12 测试）
    - `Sources/AlertCore/SQLiteAlertHistoryStore.swift`（alert_history 表 + AlertCondition JSON + 8 测试）
  - **设计沉淀**：
    - 协议先行 + 多实现（InMemory / JSONFile / SQLite 等价；未来 SQLCipher 接同协议）
    - actor 隔离 · 显式 close（Swift 6 严格并发禁止 nonisolated deinit 访问 actor 状态）
    - Decimal 用 TEXT 存（精度保留）· 时间用 INTEGER ms · UUID 用 TEXT
    - withTransaction { } helper（KLine + Journal）· 列名常量（避免 SELECT 重复）· encodeJSON/decodeJSON 泛型 helper
    - INSERT OR REPLACE 保证 PRIMARY KEY 重复时覆盖（与 InMemory 去重语义一致）
  - **测试**：40 新测试 / 6 新 suite · Linux swift test 482/128 → **524/134 全绿**
- **WP-19a-5/6 已交付**（v5.0+ · WatchlistBook + WorkspaceBook 持久化 · 6 store 闭环）：
  - **新增 6 文件**：
    - `Sources/Shared/Watchlists/WatchlistBookStore.swift`（协议 + InMemoryWatchlistBookStore + WatchlistBookStoreError）
    - `Sources/Shared/Watchlists/Stores/SQLiteWatchlistBookStore.swift`（actor · 单表 watchlist_book id=1 单例 · JSON 整本存储 · UPSERT）
    - `Sources/Shared/Workspaces/WorkspaceBookStore.swift`（协议 + InMemoryWorkspaceBookStore + WorkspaceBookStoreError）
    - `Sources/Shared/Workspaces/Stores/SQLiteWorkspaceBookStore.swift`（actor · 单表 workspace_book · 含 templates/windows/shortcut JSON 嵌入）
    - `Tests/SharedTests/WatchlistsTests/WatchlistBookStoreTests.swift`（11 测试 · InMemory 5 + SQLite 6 含 corrupt-JSON 检测）
    - `Tests/SharedTests/WorkspacesTests/WorkspaceBookStoreTests.swift`（11 测试 · 双实现等价 + 跨进程持久化）
  - **设计取舍**：
    - 整本聚合根（Book）作为持久化单位（粒度匹配业务 · UI 启动 1 次 load）
    - 单表 1 行 JSON（id=1 单例 · CHECK(id = 1) 约束保证）· UPSERT 整体覆盖
    - 协议先 + 多实现并存（InMemory + SQLite · SQLCipher 留 WP-19b 接同协议）
    - **脏 JSON 显式抛 decodeFailed**（不静默吞数据 · UI 层须感知数据损坏）
  - **测试**：22 新测试 + 5 新 suite · Linux swift test 533/135 → **556/139 全绿**
  - **6 store 闭环**：KLine + Journal + Alert + Analytics + **Watchlist + Workspace**（M5 SQLCipher 升级时一并加密）
  - **代码质量**：code-simplifier 1 轮过审 · actor 不能继承 + JSON helper fileprivate 是项目惯例 · 无可消除重复 · 但识别出脏 JSON 静默吞数据 bug 顺手修复
- **WP-19b 加密层 v1 已交付**（v5.0+ · 2026-04-26 · M5 实盘前刚性要求）：
  - **CSQLite 切换 sqlite3 → sqlcipher**：
    - `Sources/CSQLite/module.modulemap` link `sqlcipher`（替换 sqlite3）
    - `Sources/CSQLite/shim.h` 加 `#define SQLITE_HAS_CODEC 1` + `#include <sqlcipher/sqlite3.h>`（必须定义此宏才暴露 sqlite3_key 符号）
    - `Package.swift` CSQLite pkgConfig 改为 sqlcipher · providers 切 `apt(["libsqlcipher-dev"])` + `brew(["sqlcipher"])`
    - drop-in 兼容：所有 SQLite3 API 行为完全一致（sqlcipher 是 sqlite3 fork + 加密扩展）
  - **SQLiteConnection 加密接口**：
    - 原 `init(path:)` 保留 → 内部委托 `init(path:passphrase: nil)`
    - 新 `init(path: String, passphrase: String?) throws` · passphrase 非空时调 sqlite3_key + 验证 sqlite_master
    - passphrase 为 nil 或空字符串 → 跳过加密路径，行为同原生 SQLite（向后兼容 6 store）
    - 错误处理：sqlite3_key 失败 / 密钥不匹配 / 密钥访问 sqlite_master 失败时 → 关闭 handle + self.db = nil + throw
  - **测试**：+6 测试 +1 suite（SQLiteConnection · WP-19b 加密层）：
    - encryptedRoundTrip（加密往返）
    - wrongPassphraseRejected（错误密钥拒绝）
    - plaintextWithKeyRejected（非加密文件用密钥拒绝）
    - encryptedWithoutKeyRejected（加密文件不传密钥拒绝）
    - emptyPassphraseEquivalentToNoEncryption（空密码等价）
    - nilPassphraseBackwardCompatible（nil 等价 · 6 store 不破）
  - **6 store 协议零改动**：KLine + Journal + Alert + Analytics + Watchlist + Workspace 现有测试全部通过（passphrase=nil 路径）· M5 上线时各 store 升级方案：传 path + passphrase 即可，对外 API 零改动
  - **回归**：586/145 → **592/146 全绿**（向后兼容验证通过）
  - **代码质量**：code-simplifier 1 轮过审 · 加密路径 inline 错误处理（actor isolation 限制 nested func 不能改 self · 必须 inline）· 验证用 sqlite3_exec 单步（比 prepare/step/finalize 三步紧凑）
- **WP-19b v2 已交付**（v5.0+ · 2026-04-26 · 6 store 加密直通）：
  - **6 store 各加 init(path:passphrase:) 重载**：每 store 5 行 · 直通 SQLiteConnection 同名 init
    - SQLiteAnalyticsEventStore / SQLiteKLineCacheStore / SQLiteJournalStore
    - SQLiteAlertHistoryStore / SQLiteWatchlistBookStore / SQLiteWorkspaceBookStore
    - 调用模式统一：`SQLiteJournalStore(path: ..., passphrase: keychainKey)`
    - 对外 API 零改动 · UI 层 M5 升级时只需替换 init 调用
  - **EncryptionDemo（第 15 个真数据 demo）**：
    - 位置：`Tools/EncryptionDemo/main.swift` · `swift run EncryptionDemo`（~1s 纯本地）
    - 5 段：加密写入 / 明文写入 / hexdump 字节对比 / 错误密钥拒绝 / 6 store 加密 init 串测
    - **关键证据**：
      - 明文文件前 64 字节包含 `SQLite format 3` 字符串 ✅
      - 加密文件前 64 字节完全乱码 · 不含 `SQLite format 3` ✅
      - 错误密钥打开加密文件 → 抛错拒绝 ✅
      - 6 store 加密 init 全部成功（Analytics 16KB / KLine 16KB / Journal 32KB / Alert 20KB / Watchlist 8KB / Workspace 8KB）✅
    - 🎉 通过
  - **代码质量**：code-simplifier 1 轮过审
    - 抽 `sqliteHeader / hexdumpBytes / storeExts` static let 常量
    - `printBytesBlock(label:bytes:)` + `containsHeader(_:)` helper 消除重复
    - 段 4 用 `(try? Init) == nil` 替代 do/catch + var 标志（Karpathy 偏好）
    - `pathFor(_:)` nested func 消除路径模板漂移
  - **回归**：592/146 全绿（基线维持）
- **WP-19a-7 已交付**（v6.0+ · 2026-04-26 · 6 store 统一管理器 · M5 Mac App 启动入口）：
  - **新增顶层模块 StoreCore**（library · 依赖 Shared + DataCore + JournalCore + AlertCore · 解决 Shared 不能反向依赖问题）：
    - `Sources/StoreCore/StoreManager.swift`（~115 行 · `struct + Sendable` 容器 · 各 store 自隔离 actor）
    - `Tests/StoreCoreTests/StoreManagerTests.swift`（10 测试 · 覆盖路径自动创建 / 加密 vs 明文 / 文件头 hexdump / 同密钥往返 / 错密钥拒绝 / close 后不可用 / 内省 / 文件名常量契约）
    - `Package.swift`：+1 product + 1 target + 1 testTarget
  - **职责集中**：
    - 路径模板（6 个文件名固化为 `public static` 常量 + `allFileNames` 数组 · 迁移/备份脚本可引用 · 避免 UI 各处自拼路径漂移）
    - passphrase 注入（nil/空 → 6 store 全走明文 · 一次注入 · 上层不需逐 store 传）
    - 自动创建 `rootDirectory`（含多级嵌套）
    - 生命周期 `close()`（串行 await 6 store · 顺序无关 · 简单优先）
    - `rootDirectory` / `isEncrypted` 内省 properties
  - **设计取舍**：
    - struct + Sendable + 各 store 自隔离 actor（不嵌套 actor · 容器仅做引用聚合）
    - 6 store init 类型异构无法循环抽 helper（Karpathy "避免过度复杂" · 接受 6 行重复）
    - init 失败时已构造 store 的 SQLite handle 泄漏到进程退出（Swift 6 actor deinit 不能调用 isolated 方法 · UI 启动失败 → OS 回收 · 注释显式标注）
  - **测试**：+10 测试 +1 suite · Linux swift test 607/150 → **617/151 全绿** 1.031s
  - **代码质量**：code-simplifier 1 轮过审 · `isEncrypted` 表达式简化（`!(... ?? true)` → `... == false`）+ 2 处 `(try? ...) == nil` 替代 do/catch+var 标志（项目惯例）
  - **StoreManagerDemo · 第 17 个真数据 demo**（v6.0+ · 2026-04-26 · M5 启动流程端到端预演）：
    - 位置：`Tools/StoreManagerDemo/main.swift` · `swift run StoreManagerDemo`（~1s 纯本地）
    - 8 段：首次启动 init 加密 / 6 store 联动各写 1 笔 / close / 同密钥重开读回 / 错密钥拒绝 / 6 文件头 hexdump 无 magic / 配置内省 / 总结
    - **关键证据**：
      - 6 个文件头 hexdump 全部乱码 · 无 `SQLite format 3` magic ✅
      - 同密钥重开后 Analytics / KLine / Trade / Alert / Watchlist / Workspace 6 项数据全部读回成功 ✅
      - 错密钥 `WRONG-KEY` init 抛错拒绝 ✅
    - 🎉 通过
  - **代码质量**：code-simplifier 1 轮过审（命名一致性微调 · helper 私有重复符合项目惯例）
  - **M5 Mac App 集成预案**：UI 一次性 `try StoreManager(rootDirectory: appSupportURL, passphrase: keychainKey)` → 注入到各功能模块；登出 / 切换数据库时 `await manager.close()`
- **留待 WP-19b v3**（M5 上线前）：
  - 旧明文升级到加密（schema 版本号 + 迁移脚本）
  - keychain 集成（passphrase 安全存储 · Mac 切机时做）
  - 可选：DBPool（多连接读 + 单连接写）

---

## E9 · 商业化与支付

### ⬜ WP-90 · 上线决策会（免费版边界 + 转化机制）
- **时点**：M5 末
- **负责**：你 + 合伙人 + 兼职顾问
- **依赖**：M1-M5 内测数据
- **交付**：《上线决策会纪要》确定哪些功能 Free / Pro 边界、Free→Pro 转化机制
- **DoD**：决策拍板 + feature flag 配置到位
- **锚点**：D1 §7 决策 1、3；D2 §2

### ⬜ WP-91 · Apple IAP 接入 + 多设备绑定
- **时点**：M5-M6
- **负责**：你
- **依赖**：WP-90 决策
- **交付**：
  - Pro ¥399/年 + ¥39/月订阅配置、沙盒测试、收据验证后端对接
  - **多设备绑定**（StageA补遗 G12）：Pro 3 台激活上限、device_id 后端维护、超限踢出最久未用、90 天自助重置
- **DoD**：沙盒环境订阅链路完整 + 后端订阅状态写入正确 + 设备上限生效
- **禁做**：
  - ❌ 不在业务层散落 `if Pro` 判断，统一由门控服务读取
  - ❌ 不做"先免费后收费"的暗扣 / 默认勾选订阅
  - ❌ 不把订阅凭证写入明文 SQLite（必须 Keychain）
- **锚点**：D2 §3 支付通道、StageA补遗 G12、产品设计书 5.6、ChatGPT A11/B08

### ⬜ WP-92 · 退款流程与订阅延期
- **时点**：M5-M6
- **负责**：你 + 合伙人客服
- **交付**：7 天无理由退款规则、事故订阅延期 SOP、客服话术
- **DoD**：首次退款请求可完整处理
- **锚点**：D2 §3、D3 §3 赔付原则

### ⬜ WP-93 · 官网微信/支付宝支付（Stage A 后期）
- **时点**：M8-M9
- **负责**：你
- **交付**：官网大额用户微信/支付宝通道（绕开 Apple 30% 税）
- **DoD**：官网可下单 + 账户打通
- **锚点**：D2 §3

### ⬜ WP-94 · 手动开票 SOP 与财务表模板（源自 StageA补遗 G5）
- **时点**：M6 上线时启用
- **负责**：合伙人（主）+ 你
- **交付**：`invoice@<domain>` 邮箱 + 阿里云电子发票服务开通 + 飞书财务表模板 + 48 小时响应 SOP
- **DoD**：首张电子普票可在 48 小时内开出、流程归档
- **锚点**：StageA补遗 G5、产品设计书 7.5

### ⬜ WP-95 · M6 Pre-launch Checklist 执行（源自 StageA补遗 G9）
- **时点**:M5 末（WP-90 上线决策会同期）
- **负责**：你 + 合伙人
- **交付**：26 项 pre-launch 检查全绿（技术稳定性 8 / 合规法务 6 / 商业运营 6 / 营销 PR 6）+ 灰度发布计划（Day 1/3/7 三段）
- **DoD**：全部 26 项签字 + Day 1 / Day 3 / Day 7 灰度节奏执行
- **锚点**：StageA补遗 G9

### ⬜ WP-96 · CI benchmark 性能门禁（源自 ChatGPT B11）
- **时点**：M3-M4（随 WP-40 Metal 图表进入稳定期启用）
- **负责**：你
- **交付**：
  - Benchmark Suite：图表渲染（10w K 线滚动/缩放）、Tick 处理延迟、冷启动、内存占用
  - CI 集成：任一性能指标回归 > 10% → **自动 block merge**
  - 性能回归报告自动落地（CI artifacts）
  - 发版回滚 SOP（M5 前就绪）
- **DoD**：
  - 4 项核心 benchmark 在 CI 跑通且稳定
  - 回归 PR 可被自动拦截（故意引入性能退化测试一次）
  - 发版回滚 SOP 演练一次
- **禁做**：
  - ❌ 不靠人工感觉判断性能退化
  - ❌ 不把 benchmark 放进 UI 测试流水（单独流水）
  - ❌ 不设置"警告但不阻断"的软门禁（金融类必须硬阻断）
- **锚点**：ChatGPT B11、产品设计书 §3.4 性能基准

---

## E10 · 品牌与对外物料

### ⬜ WP-100 · 名字 + 域名 + Logo + VI
- **时点**：M1 Week 4
- **负责**：你 + 兼职顾问（设计）
- **交付**：中英双名、域名注册、Logo、VI 规范最小集
- **DoD**：名字 + 域名敲定 + Logo 两套备选选一
- **锚点**：D2 §7 Week 4

### ⬜ WP-101 · 官网落地页（静态）
- **时点**：M1-M2
- **负责**：你 + 兼职顾问
- **交付**：首页 / 功能介绍 / 定价 / 隐私 / status 页骨架
- **DoD**：静态页部署上线、移动端响应式 OK
- **锚点**：D2 §5、D3 §5 status 页

### ⬜ WP-102 · App Store 产品页 + ASO
- **时点**：M5
- **负责**：合伙人（主）+ 你
- **交付**：标题 / 副标题 / 关键词 / 截图 / 视频预览
- **DoD**：ASO 关键词覆盖（期货/交易/行情/复盘/Mac）、Apple 审核通过
- **锚点**：D2 §5 副战场

### ⬜ WP-103 · 少数派深度评测（2 篇）
- **时点**：M3 末、M6 末
- **负责**：你（写）+ 合伙人（投稿对接）
- **交付**：2 篇深度评测（M3 内测介绍 + M6 上线）
- **DoD**：稿件采用 + 上线
- **锚点**：D2 §5

### ⬜ WP-104 · 即刻/V2EX 月更帖
- **时点**：M1 起 · 每月 1 篇
- **负责**：你
- **交付**：开发日志帖（非 IP 化、真实产品进展）
- **DoD**：固定节奏发布、无断档
- **锚点**：D2 §5

---

## E11 · GTM · 冷启动

### ⬜ WP-110 · Hunter 1v1 私信流程
- **时点**：M2 起（每天 10-20 条私信）
- **负责**：合伙人
- **交付**：目标用户库（雪球/知识星球/期货群/小红书）、话术模板、日触达数据记录
- **DoD**：首 30 天日均触达 ≥10，否则触发适配度评估（D3 §7 风险）
- **锚点**：D2 §5 主战场

### ⬜ WP-111 · 用户访谈（M1 批量 15-20 个）
- **时点**：M1 Week 2-4
- **负责**：合伙人（主持）+ 你（旁听+总结）
- **交付**：15-20 份访谈纪要、痛点 Top10、付费意愿锚点
- **DoD**：纪要归档 + Top10 输出到 WP-22
- **锚点**：D2 §7 Week 2-4

### ⬜ WP-112 · TestFlight 邀请制闭环
- **时点**：M2 起
- **负责**：合伙人
- **交付**：邀请流程、筛选标准、反馈收集表单
- **DoD**：M2 末首批 30-50 人入组
- **锚点**：D2 §5、§6 M2

### ⬜ WP-113 · VIP 微信群 + 老用户推荐奖励
- **时点**：M5 起（VIP 群）/ M6 起（推荐机制）
- **负责**：合伙人
- **交付**：VIP 群邀请制、推荐 1 人付费 → 推荐人订阅免费延期 3 月
- **DoD**：机制上线 + 首个推荐成交
- **锚点**：D2 §5 用户邀请闭环、D3 §5 预埋

---

## E12 · 运维与事故响应

### ⬜ WP-120 · App 内 Banner 推送系统
- **时点**：M1-M3（1-2 天工程）
- **负责**：你
- **交付**：App 内 banner 推送（事故通知 / 公告 / 版本提醒）
- **DoD**：后端可下发任意 banner 到客户端
- **锚点**：D3 §5 M1-M3 预埋

### ⬜ WP-121 · 事故日志模板 + SOP
- **时点**：M1-M3
- **负责**：你
- **交付**：飞书文档模板、P0-P3 分级、T+0/T+1h/T+24h/T+72h 时间线、赔付原则、通讯原则、对外声明范本
- **DoD**：模板沉淀 + 全员熟悉 SOP
- **锚点**：D3 §3-§4

### ⬜ WP-122 · 客服微信群
- **时点**：M3 起
- **负责**：合伙人
- **交付**：Pro 付费用户邀请制 VIP 群（兼做客服阵地）
- **DoD**：首批用户入群
- **锚点**：D3 §5

### ⬜ WP-123 · 官网 Status 页
- **时点**：M4-M6
- **负责**：你
- **交付**：`status.ourapp.com` 实时/手动状态更新 + 历史事故档案
- **DoD**：上线 + M6 前首个事故可登记
- **锚点**：D3 §5 M4-M6 预埋

### ⬜ WP-124 · CTP 断线重连 SOP 实现（行情通道）
- **时点**：M2-M4（行情通道；Stage B 再扩展到交易通道 · 见 SB1）
- **负责**：你
- **交付**：心跳机制（10s）+ 三级响应（L1/L2/L3）+ 指数退避（2/4/8/16/32/64/128s）+ 状态指示灯
- **DoD**：模拟断网测试通过、用户感知符合设计、断线重连状态机代码化（非仅文字 SOP）
- **禁做**：
  - ❌ 不把断线重连写成"仅提示不阻断"（L3 必须真阻断）
  - ❌ 不用固定重试间隔（必须指数退避）
  - ❌ Stage B 扩展到交易通道时，重连后不对账就不恢复下单
- **锚点**：D3 §3 CTP 断线重连 SOP、ChatGPT A02/B03

---

## E13 · 死亡率自检与风险管理

### ⬜ WP-130 · 两指标监控看板
- **时点**：M1 末启用
- **负责**：你
- **依赖**：WP-133 埋点 schema 已落地（Pro 付费数依赖 subscription_event 事件）
- **交付**：TestFlight 周新增 + 累计 Pro 付费数两指标看板（飞书文档或简易 Dashboard）
- **DoD**：数据每月手动更新、红/黄/绿一目了然
- **锚点**：D3 §1、StageA补遗 G2

### ⬜ WP-131 · 财务月度对账 + 资金底线告警
- **时点**：M1 起每月第一个周一
- **负责**：你
- **交付**：账上余额月度对账、¥12w 黄线/¥9w 应急/¥3w 硬停三级告警
- **DoD**：进入 ¥12w 黄线时改为每周对账，每次对账留档
- **锚点**：D3 §2 监控频率

### ⬜ WP-132 · 风险全景表月度 Review
- **时点**：M1 起每月 standup 时
- **负责**：你 + 合伙人
- **交付**：D3 §7 11 项风险的概率/影响/触发信号月度 review 并更新（含创始人关键人风险 · StageA补遗 G10）
- **DoD**：每月 standup 纪要包含风险表 review 结果
- **锚点**：D3 §7、§8、StageA补遗 G10

### 🟨 WP-133 · 埋点 schema 与上报链路（133a 客户端 ✅ / 133b 后端上报待 WP-80）
- **时点**：M1 末前启用
- **负责**：你
- **交付**：10 个核心事件定义（app_launch / session_start / session_end / chart_open / indicator_add / drawing_create / replay_start / alert_trigger / journal_entry_save / subscription_event）+ SQLite `events` 表 + 批量上报链路（每 5min 或 100 条）+ 后端接收接口 + WAPU SQL 查询模板
- **DoD**：埋点写入 + 上报链路跑通，后端能查出 WAPU
- **锚点**：D1 §4、D3 §1、StageA补遗 G2
- **已交付**（2026-04-25 · WP-133a 客户端层 · 不依赖后端）：
  - `Sources/Shared/Analytics/AnalyticsEvent.swift` · 10 事件 enum + Codable + props JSON 序列化 + nowMs 工具
  - `Sources/Shared/Analytics/AnalyticsEventStore.swift` · 持久化协议（append / appendBatch / queryPending / markUploaded / cleanupUploaded / count）
  - `Sources/Shared/Analytics/Stores/InMemoryAnalyticsEventStore.swift` · actor 内存实现（id 自增）
  - `Sources/Shared/Analytics/Stores/JSONFileAnalyticsEventStore.swift` · actor 文件持久化（atomic 替换 + 自动建目录 + 重启加载）
  - `Sources/Shared/Analytics/AnalyticsService.swift` · 高层 actor · 隐私开关单一入口（StageA补遗 G2 §隐私）+ session 管理 + 时间注入
  - 27 测试 / 6 suite · Linux swift test 455/122 → **482/128 全绿**
- **留待 WP-133b**（依赖 WP-80 后端就绪）：
  - 后端 REST 批量接收接口（PostgreSQL events 表）
  - 客户端 BatchUploadDriver（HTTPClient + 重试 + 防丢失 + uploaded 翻位）
  - WAPU SQL 查询模板（与 D1 §4 严谨定义对齐：过去 7 天 ≥ 3 个不同日期 session_start）
- **留待 WP-19 SQLCipher**：JSONFile → SQLCipher 真实加密存储（接同协议）

---

## 月度时间轴映射（关键路径）

| 月份 | 必完成 WP |
|------|----------|
| **M1** | WP-01/02/03/04 合规 · WP-10/11/12/13 团队 · WP-20/21/22 PoC · WP-30 Legacy 拷贝 · WP-80 后端骨架 · WP-100 品牌命名 · WP-111 访谈 · WP-120/121 基础设施 · WP-130/131/132 自检启用 · **WP-133 埋点 schema** |
| **M2** | WP-23 feature flag · WP-31 Legacy 参考改动 · WP-40 Metal 图表启动 · WP-43/44 自选+布局 · WP-101 官网启动 · WP-110 Hunter 启动 · WP-112 TestFlight 启动 · WP-124 断线重连启动 |
| **M3** | WP-41 指标 56 · WP-42 画线 · WP-55 工作区模板 · WP-103 少数派第一篇 · WP-122 客服群 · **M3 Go/No-Go 自检** |
| **M4** | WP-50 复盘 · WP-51 K 线回放 · WP-52 条件预警 · WP-83 审计日志 · WP-123 status 页启动 · **WP-84 CloudKit 合规方案启动** |
| **M5** | WP-05 隐私协议+审核防御 · WP-53 交易日志 · WP-54 模拟训练 · WP-81/82 生产部署 · WP-90 上线决策会 · **WP-95 pre-launch checklist** · WP-91 IAP 接入 · WP-102 App Store ASO · WP-113 VIP 群 |
| **M6** | WP-91 IAP 上线（含设备绑定）· WP-92 退款流程 · **WP-94 手动开票 SOP** · WP-103 少数派第二篇 · **🔴 生死节点：Pro 订阅收钱** |
| **M7** | WP-60 CloudKit UI 同步 · WP-61 iPad 基础版 · Pro 300 目标 |
| **M8** | WP-62 麦语言 30-50 函数 · **WP-63 .wh 公式导入** · **WP-64 文华自选导入** · WP-93 官网微信/支付宝 · Pro 400 目标 |
| **M9** | Pro 500 + 月流水 ¥1.5-2w · **进入 Stage B 评估** |

---

## 负责人初步分配

**你（CEO · 工程 + 产品 + 架构 + 合规）**
E1 全部 · E2 主责 · E3 全部 · E4 全部 · E5 全部 · E6 全部 · E7 全部 · E8 全部 · E9 全部 · E10-101/103/104 · E12-120/121/123/124 · E13 全部

**合伙人（COO · Hunter + 访谈 + 运营 + 客服）**
E10-102 App Store · E11 全部 · E12-122 客服群

**共担**
WP-12 月度 standup · WP-22 MVP 锁死 · WP-90 上线决策会 · WP-132 风险 review

---

## 维护约定

1. **状态更新**：每个 WP 开工切 🟨 进行中，完成切 ✅，同时更新 Epic 表进度
2. **新增 WP**：M3 / M6 / M9 checkpoint 吸收新 WP 时，编号顺延（WP-140+）
3. **删减 WP**：项目收缩时用 ❌ 标注，不删文字记录（便于追溯决策）
4. **重大修订**：写"修订日志"段落，标日期+修订点+原因
5. **配合记忆系统**：本清单是"在干什么"，Claude 记忆是"项目是什么"，两者互补

---

## 修订日志

| 日期 | 版本 | 修订点 | 原因 |
|------|------|-------|------|
| 2026-04-24 | v1.0 | 初稿 · 55 个 WP · 13 个 Epic | 首次从 D1/D2/D3 提炼而来 |
| 2026-04-24 | v1.1 | 新增 6 WP（WP-63/64/84/94/95/133）· 扩展 4 WP（WP-02/05/91/130/132）· 总数 55→61 | StageA 补遗 12 条 gap 落地：G1 CloudKit / G2 埋点 / G4 文华迁移 / G5 发票 / G9 pre-launch / G10 创始人风险 |
| 2026-04-24 | v1.2 | 新增 2 WP（WP-24 Swift Package 骨架 / WP-96 CI benchmark 门禁）· 7 个核心工程 WP 加"禁做"字段（WP-21/23/40/41/53/60/62/91/124）· 总数 61→63 | 融合 ChatGPT 工作包清单的工程硬核优势：Swift Package 8 Core 模块 + CI 性能门禁 + 禁做项 scope discipline |
