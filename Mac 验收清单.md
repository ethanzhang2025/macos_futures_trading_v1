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

## 预警面板 ⌘B（WP-52 UI · 4 commit · 1/4 已交付）

### commit 1（开窗 + Mock alerts + 列表占位）
- [ ] ⌘B 打开独立窗口（与主图/复盘分离）
- [ ] 顶部 stats（总数/活跃/已触发/已暂停 · 颜色：绿/红/橙/灰）
- [ ] 列表表头：名称 / 合约 / 条件 / 状态 / 通道 / 冷却（6 列 · monospaced）
- [ ] 8 个 Mock alerts 渲染：
  - [ ] 6 类 condition displayDescription 中文显示（价格 > / < / 上穿 / 下穿 / 触线 / 成交量 / 急动）
  - [ ] 4 类 status badge（活跃绿 / 已触发红 / 暂停橙 / 已取消灰）
  - [ ] 通道简写中文（内/通/声/控/文）
  - [ ] 冷却秒数（默认 60s · IF0 跌破设 300s · cancelled 设 0s）
- [ ] 底部"待 commit 2-4" 提示行（Label + SF Symbol）
- [ ] 窗口最小 720×480 · 默认 880×640
- [ ] LazyVStack + Divider 分隔 · 滚动顺畅

### commit 2（添加预警 Sheet）
- [ ] 列表上方"+ 添加"按钮（⌘⇧N 快捷键）
- [ ] AddAlertSheet 弹出（520×620 · macOS 标准 sheet 动画）
- [ ] Form .grouped 布局：基本 / 条件 / 通知通道 三 Section
- [ ] ConditionKind Picker 切换 6 类（价格 4 + 成交量 + 急动）
- [ ] conditionParams 动态切换：价格类 1 字段 · 成交量 2 字段 · 急动 2 字段
- [ ] 5 个 channel Toggle（内/通/声/控/文）+ 冷却秒数 TextField
- [ ] 保存按钮 disabled 当 name 空 · ⌘Return 触发
- [ ] 取消按钮 ⌘. 触发
- [ ] 保存后 alerts 增 1 项 · 列表立即更新
- [ ] horizontalLineTouched 类型未在 Picker 显示（留 v2 · 需 drawingID 选择）

### commit 3（编辑/删除/启停 + 触发历史 Tab）
- [ ] TabView segmented 切换：预警列表 / 触发历史
- [ ] 列表行末"操作"列 3 button：
  - [ ] ⏯ 启停（active ↔ paused · 已 cancelled 的 disabled）· tooltip "暂停/恢复"
  - [ ] ✏️ 编辑（蓝色 · sheet 弹出 "编辑预警"模式 · 字段加载现有 alert）
  - [ ] 🗑 删除（红色 · 直接 remove · 无 confirm v1）
- [ ] 编辑模式 Sheet 标题"编辑预警" · 主按钮"更新"
- [ ] 编辑加载：6 类 condition 反向映射（horizontalLineTouched 显示为 priceAbove 占位 · 留 v2）
- [ ] 编辑保留：alert.id / createdAt / lastTriggeredAt（不重置）
- [ ] 触发历史列表表头 5 列（时间/预警/合约/触发价/条件 · 时间格式 MM-dd HH:mm:ss · Asia/Shanghai）
- [ ] 12 条 Mock 历史按时间倒序（-300s ~ -86400s）· 触发价红色高亮
- [ ] 历史空态视图（clock.arrow.circlepath icon + "暂无触发历史"）

### commit 4（通知通道 + 测试触发 + 通知日志 Tab）
- [ ] AlertWindow 启动时 register 5 个 LoggingNotificationChannel（5 kinds）
- [ ] 行操作加 4th button 📤 测试触发（紫色 · 紫 paperplane.circle）
- [ ] 测试触发：dispatch 走 alert.channels · 写入 consoleLog · 加历史 · status → triggered
- [ ] AlertTab 加 .console "通知日志"第 3 个 segmented
- [ ] consoleLog 显示最近 100 条（time · channel kind · alertName · message）
- [ ] 顶部"清空"按钮（log 空时 disabled）
- [ ] 空态视图（terminal icon + "点击行 📤 测试触发"提示）
- [ ] 测试触发后切到"通知日志" Tab 看到对应的 5 条 log（一行 per channel）
- [ ] 测试触发后切到"触发历史" Tab 看到新增 entry（最上方）

### Mac 切机替换（保留 LoggingChannel · 单独添加真实 channel）
- [ ] UserNotifications channel：替换 .systemNotice 的 LoggingChannel · 真实系统通知中心提示
- [ ] NSSound channel：替换 .sound 的 LoggingChannel · 系统提示音
- [ ] 首次系统通知触发权限请求（用户允许后才能 dispatch）

---

## 待补（后续 commit 累积）

后续每个 commit 完成功能后追加到对应章节 · 切机前在此清单逐项验收。
