# Mac 验收清单

Linux 端编译能过 · 视觉/手感/系统集成需 Mac 切机一次性集中验收。
切机命令：`cd /Users/admin/.../macos_futures_trading_v1 && swift run FuturesTerminalApp`

**累积时点**：v7.0 之后 9 commit · 2026-04-28

---

## 副图视觉（67c7945 + 396e3a6）

- [ ] MACD 副图：零轴虚线 / 直方涨红跌绿 / DIF 黄 / DEA 紫 / HUD 三值
- [ ] KDJ 副图：80/50/20 参考线 / K 黄 / D 紫 / J 蓝 / HUD 三值
- [ ] 副图 Picker 切换 MACD ↔ KDJ 流畅 · 无闪屏
- [ ] KDJ 视野 -20~120 · J 极端值不裁断
- [ ] 副图与主图拖拽缩放共享 viewport · 同步

## 工具条 4 Picker（a659a68）

- [ ] 模式 / 合约 / 周期 / 副图 4 Picker 视觉（适配明暗模式）
- [ ] 切合约：主区 ProgressView · pipeline 重启 · HUD 更新
- [ ] 切周期 6 种（1分/5分/15分/30分/1时/日）：pipeline 重启
- [ ] HUD `15分` 中文显示（不是 `15m`）

## 回放模式（cfb12e7）

- [ ] 模式切实盘 ↔ 回放：旧 pipeline / player / driver 正确清理
- [ ] 回放拉历史：4 周期支持（5/15/60分/日）· 1分/30分 fallback 15分
- [ ] 控制条渲染：⏹/⏪/⏯/⏩ + 速度 5 档（0.5×/1×/2×/4×/8×）+ 进度 N/M·%
- [ ] ▶ 播放节奏：1× = 1 根/秒（baseInterval=1.0）
- [ ] 速度切换：setSpeed 不重启 driver · 下一步自动应用新间隔
- [ ] 单步前进/后退 / 停止 重置到第 1 根
- [ ] 空格快捷键 ▶ ↔ ⏸
- [ ] 倒退后播放：rebuildBarsToCursor 全量路径正确
- [ ] 关窗时 player/driver 正确 stop（onDisappear）

## 复盘工作台 ⌘R（6c5cc2e + 7ede339 + bb82e90 + 53ed76d）

- [ ] ⌘R 打开独立窗口 · 与主图分离
- [ ] 顶部 stats（成交/闭合/总 PnL/胜率）+ HUD 中文
- [ ] 4 列 LazyVGrid × 8 卡片（最小 1024 宽 · 自适应）
- [ ] 8 图视觉：
  - [ ] 月度盈亏 BarMark 涨红跌绿 · YY/MM 标签
  - [ ] 分布直方 BarMark 桶下界 · 涨红跌绿
  - [ ] 胜率曲线 LineMark 绿 · 50% 虚线参考
  - [ ] 品种矩阵表格 4 列 · PnL 涨红跌绿 · prefix 8 行
  - [ ] 持仓时间 BarMark 中性蓝 · 6 桶 label
  - [ ] 最大回撤双线（蓝实+绿虚）+ 红阴影区间
  - [ ] 盈亏比双柱 + ratio 28pt 大字（≥1 红 / <1 绿语义反向）
  - [ ] 时段分析 BarMark 5 段 · 涨红跌绿
- [ ] y 轴万元简写（"1.25w"）· x 轴月份缩写
- [ ] 加载/错误状态视图

## 多窗口 / 系统集成

- [ ] ⌘N 新建图表窗口 · 每窗口独立 renderer / pipeline / replay state
- [ ] ⌘L 自选合约（占位）
- [ ] ⌘, 偏好设置 TabView（占位）
- [ ] 主图窗口关闭：pipeline + replay player/driver 正确 stop
- [ ] 多窗口同时跑不同合约/周期/模式互不干扰

## Sina 数据源

- [ ] RB0/IF0/AU0/CU0 实时行情拉取（5s 轮询）
- [ ] 实时增量 .completedBar 渐增到主图
- [ ] Sina 不可达 → 5000 根 random walk Mock 兜底
- [ ] 系统中文 locale 下历史 K 线解析正确（en_US_POSIX 已修）

## 性能 profile（用 Instruments）

- [ ] 8× 回放速度 indicators 全量重算瓶颈 → 决定 IndicatorCore 增量 API 优先级
- [ ] 主图 60Hz 拖拽时副图 Canvas 同步重渲染开销
- [ ] LazyVGrid 8 SwiftUI Charts 卡片首屏渲染时长
- [ ] 多窗口 4 个 ChartScene 并行内存占用

## 待补（后续 commit 累积）

后续每个 commit 完成功能后追加到对应章节 · 切机前在此清单逐项验收。
