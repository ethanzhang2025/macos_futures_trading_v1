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

## 自选合约面板 ⌘L（WP-43 UI · 4 commit · 1/4 已交付）

### commit 1（⌘L 起步 · NavigationSplitView + Mock 3 组 9 合约）
- [ ] ⌘L 打开独立窗口（与主图/复盘/预警分离 · 单实例）
- [ ] NavigationSplitView 双栏布局正确：
  - [ ] 左栏宽度区间生效（min 200 / ideal 220 / max 280）
  - [ ] 拖拽分栏分隔线可调整宽度
  - [ ] 左侧 sidebar 样式（半透明背景 · macOS 原生）
- [ ] 左栏分组列表 3 项渲染：
  - [ ] "主力合约 · 3 个合约"（folder icon · accentColor 蓝）
  - [ ] "黑色系 · 3 个合约"
  - [ ] "贵金属 · 3 个合约"
  - [ ] List selection 单选 · 切换分组右栏内容立即更新
- [ ] 默认选中第一组（"主力合约"· onAppear 触发）
- [ ] 右栏 header 正确：
  - [ ] 分组名（title3 · semibold）+ "· N 合约"（caption · 灰）
  - [ ] 右上 "commit 1/4 · ⌘L 起步" 胶囊标签（灰底）
- [ ] Table 4 列正确（合约 / 最新价 / 涨跌幅 / 持仓量 · 全 monospaced 等宽字体）
- [ ] 涨跌幅颜色（中国习惯 · 涨红跌绿）：
  - [ ] "+1.21%" / "+0.83%" / "+2.05%" / "+1.78%" / "+1.45%" → 红
  - [ ] "-0.45%" / "-0.32%" → 绿
- [ ] 9 个合约 Mock 数据全显示（RB0/IF0/AU0/CU0/HC0/I0/AG0 · 价/涨跌/持仓）
- [ ] 底部提示行 "Mock 数据 · 待 M5 接真实行情 + commit 4 主图联动"（caption2 灰）
- [ ] 窗口最小 720×480 · 默认 880×600
- [ ] 切换不同分组：
  - [ ] 主力合约 显示 RB0/IF0/AU0
  - [ ] 黑色系 显示 RB0/HC0/I0
  - [ ] 贵金属 显示 AU0/AG0/CU0
- [ ] empty state（如手动构造空分组测试 · 暂无入口）：tray icon + "分组为空" + "(待 commit 2 添加合约入口)"

### commit 2（添加/删除/重命名分组与合约 + 右键菜单 + confirmation）
- [ ] 左 sidebar 顶部"添加分组"按钮（plus icon · ⌘⇧G）
- [ ] 点击 → 弹出 GroupNameSheet（标题"添加分组"· 按钮"保存"· 360×220）
  - [ ] 输入空名时"保存"按钮 disabled
  - [ ] 输入合法名 + ⌘Return → 新分组追加到列表末尾 + 自动选中
  - [ ] 取消按钮 / Esc → 不新增
- [ ] 分组行右键菜单（contextMenu）：
  - [ ] "重命名" → 弹出 GroupNameSheet（标题"重命名分组"· 按钮"更新"· 预填现有名）
  - [ ] 输入新名 + 更新 → 列表标签立即变更
  - [ ] 名字与原名相同时"更新"按钮 disabled（避免 no-op）
  - [ ] "删除分组"（destructive 红色）→ 弹出 confirmationDialog
- [ ] 删除分组 confirmationDialog：
  - [ ] 标题"删除分组？"
  - [ ] 内容"分组「X」内的 N 个合约将一并移除。该操作无法撤销。"
  - [ ] 主按钮"删除「X」"（红色 destructive）
  - [ ] 取消按钮回滚 · 不删
  - [ ] 删除当前选中分组 → 自动切换到第一个 / 若全删空 → empty state
- [ ] 右 detail header "添加合约"按钮（Label "添加合约" plus icon · ⌘⇧I）
- [ ] 点击 → 弹出 InstrumentIDSheet（标题"添加合约到「X」"· 380×280）
  - [ ] 输入 RB0 / IF2509 等 → 自动 uppercased + trim 空白
  - [ ] 提示文案"主力合约支持：RB0/IF0/AU0/CU0"显示
  - [ ] 输入空时"添加"按钮 disabled
  - [ ] 同组重复合约 addInstrument 返回 false（去重）→ 不会出现重复行
- [ ] Table 多选合约（按住 ⌘ / Shift 多选）
- [ ] Table 行右键菜单（contextMenu(forSelectionType:)）：
  - [ ] 单选时菜单文字"从分组移除「X」"
  - [ ] 多选时菜单文字"从分组移除选中的 N 个合约"（destructive 红色）
  - [ ] 选中 0 个时不显示菜单项
  - [ ] 移除后选中状态清空
- [ ] 切换分组（点击 sidebar 不同分组）→ Table 选中状态自动清空
- [ ] footerHint 选中数提示："已选 N 个 · 右键移除"（仅当有选中时显示）
- [ ] ⌘⇧G/⌘⇧I 快捷键在 ⌘L 自选窗口为前台时生效 · 不与全局 ⌘N/⌘L/⌘R/⌘B 冲突

### commit 3（拖拽排序：分组重排 + 同组重排 + 跨组移动）
- [ ] 拖拽视觉反馈：
  - [ ] 长按任一行（分组或合约）拖起 → 半透明 preview 跟随光标（folder/doc.text.fill icon + 名 · regularMaterial 圆角背景）
  - [ ] hover 在分组行上 → 该行整行淡蓝高亮（0.18 accent opacity）
  - [ ] hover 在合约行上 → 行上方 2px 蓝色 insertion line
  - [ ] hover 在合约表末尾空白区（trailing drop zone）→ 末尾 2px 蓝色 insertion line
  - [ ] 松开后高亮消失（hoverTarget 清空）
  - [ ] 列表 .easeInOut(0.22s) 落点动画顺滑（无跳变）
- [ ] 分组重排序（sidebar 拖分组 → 分组之间）：
  - [ ] 拖"贵金属"到"主力合约"上方 → 贵金属移到第一位
  - [ ] 拖到自己原位 / 紧邻自己之后 → no-op（数据无变化）
- [ ] 合约同组重排序（detail 拖合约 → 同组其他位置）：
  - [ ] 主力合约组内拖 AU0 到 RB0 上方 → AU0 移到 RB0 之前
  - [ ] 拖到 trailing drop zone（合约表末尾 60px 空白区）→ 移到本组末尾
  - [ ] 落在自己原位 / 紧邻自己之后 → no-op
- [ ] 合约跨组移动（detail 拖合约 → sidebar 另一组）：
  - [ ] 在主力合约组内拖 IF0 → drop 到 sidebar "贵金属"分组 → IF0 从主力合约移除 + 加到贵金属末尾
  - [ ] 若目标组已有同 ID（如 AU0 已在贵金属，再拖 AU0 入贵金属）→ 仅从源组删除（WatchlistBook 内置去重 · 不会出现重复行）
  - [ ] 拖到 sidebar 当前源组自己 → no-op
- [ ] 选中态联动：
  - [ ] 跨组移动单个合约后，selectedInstruments 自动 subtract 该 ID
  - [ ] 切换分组 onChange → selectedInstruments.removeAll
- [ ] 拖拽 ↔ commit 2 功能共存：
  - [ ] 拖拽过程中右键菜单不弹出
  - [ ] 拖拽落定后右键菜单仍可触发（重命名 / 删除 / 移除）
  - [ ] 拖拽过程中 ⌘⇧G / ⌘⇧I sheet 不弹出
- [ ] 边界 & 容错：
  - [ ] 仅 1 个分组时拖该分组 → 落点无变化
  - [ ] 空组（commit 2 创建无合约）拖入合约 → 该合约成为该组首个
  - [ ] Transferable 类型识别正确：拖分组只能落在 sidebar 组行上 / 拖合约可落在 sidebar 组行 + detail 行 + trailing zone

### commit 4（主图联动 · 双击合约 → ChartScene 切合约）
- [ ] 在自选窗口任一组双击主力合约（RB0 / IF0 / AU0）：
  - [ ] 主图窗口（⌘N）打开（若未开 · openWindow(id: "chart") 创建）/ 激活前台（若已开）
  - [ ] 主图工具条"合约："Picker 立即切到双击的合约（如 RB0 → IF0）
  - [ ] 主图自动重新加载新合约真行情（看到 ProgressView "加载 IF0 真行情…"）
  - [ ] 加载完成后 K 线 + MA20/MA60 + 副图（MACD/KDJ）全部刷新到新合约数据
- [ ] 在自选窗口双击不支持合约（HC0 / I0 / AG0）：
  - [ ] 弹本地 .alert "暂不支持的合约"
  - [ ] 提示文案"X 暂不支持主图查看 · 当前主图仅支持 RB0 / IF0 / AU0 / CU0"
  - [ ] 点"好"关闭 · 主图窗口不打开 · 不发通知（即不会意外切已开主图）
- [ ] 多窗口场景（按 ⌘N 开 2 个主图）：
  - [ ] 双击合约 → 两个主图窗口都切到该合约（NotificationCenter 全局 broadcast · 是预期行为）
- [ ] 主图工具条 Picker 手动切合约（commit 4 之前已能用）：
  - [ ] 仍正常切换 · 不被 NotificationCenter 干扰
  - [ ] 双击 currentInstrumentID 已等于的合约 → no-op（不重启 pipeline · id != currentInstrumentID 守卫）
- [ ] 双击 + commit 1-3 功能不冲突：
  - [ ] 单击行 → List 选中（commit 2 selectedInstruments 正常）
  - [ ] 双击行 → 打开主图（不触发拖拽 · 不触发右键）
  - [ ] 长按 + 拖动 → 拖拽（commit 3 · 不触发双击）
- [ ] footerHint 提示语显示"双击合约打开主图 · 仅 RB0/IF0/AU0/CU0 支持 · Mock 数据待 M5 接真实行情"
- [ ] 关闭主图窗口（⌘W）后再双击合约 → openWindow 重新打开主图 + 切到该合约
- [ ] 跨 mode 联动：
  - [ ] 主图在 .replay 模式时双击自选合约 → currentInstrumentID 变更 · pipeline 仍走 .replay 路径（用新合约拉历史回放）
  - [ ] 主图在 .live 模式时双击 → 实盘路径用新合约

---

## 交易日志面板 ⌘J（WP-53 UI · 4 commit · 1/4 已交付）

### commit 1（⌘J 起步 · 双 Tab + Mock 13 trades + 5 journals）
- [ ] ⌘J 打开独立窗口（与主图 ⌘N / 自选 ⌘L / 复盘 ⌘R / 预警 ⌘B / 设置 ⌘, 分离 · 单实例）
- [ ] 顶部 stats 正确显示：
  - [ ] "📔 交易日志"标题（title2 + bold）+ 分隔符
  - [ ] "总成交：13 笔"（caption + monospaced）
  - [ ] "总日志：5 篇"
  - [ ] 右上"commit 1/4 · ⌘J 起步"胶囊标签（灰底）
- [ ] TabView segmented 双 Tab 切换：
  - [ ] "成交记录" Tab（默认选中）
  - [ ] "交易日志" Tab
  - [ ] 切换无延迟 · 数据立即渲染
- [ ] 成交记录 Tab：
  - [ ] Table 8 列：合约 / 方向 / 开/平 / 成交价（右对齐）/ 数量 / 手续费 / 时间 / 来源
  - [ ] 外层 monospaced 字体继承（全表统一 · 来源列 caption2 显式覆盖）
  - [ ] Direction 颜色：买（红 · 中国习惯）/ 卖（绿）· 用 displayName 中文
  - [ ] OffsetFlag displayName 中文：开仓 / 平仓 / 平今 / 平昨
  - [ ] 来源 Capsule 标签：文华 / 通用 / 手填（灰底）
  - [ ] 成交价 1 位小数 · 手续费 2 位小数（NumberFormatter static 缓存）
  - [ ] 时间格式 MM-dd HH:mm:ss · Asia/Shanghai · POSIX locale
  - [ ] 13 笔数据全显示（RB2510 × 7 / IF2509 × 3 / AU2512 × 2 / CU2511 × 1）· 时间倒序
- [ ] 交易日志 Tab：
  - [ ] Table 6 列：标题 / 成交（N 笔）/ 情绪 / 偏差 / 标签 / 更新时间
  - [ ] 标题 fontWeight medium · 关联成交数 monospaced + 灰
  - [ ] 情绪 Capsule 5 色 + 背景 opacity 0.18：自信绿 / 犹豫橙 / 恐惧红 / 贪婪紫 / 平静蓝
  - [ ] 偏差颜色：asPlanned 绿 / 其他偏差橙
  - [ ] 标签 " · " 分隔（如 "RB · 日内 · 趋势跟随"）· lineLimit(1)
  - [ ] 5 篇 journal 全显示（涵盖 5 类情绪 + 5 类偏差中的 4 种 asPlanned/earlyExit/chaseHigh/other）
- [ ] 底部提示行 "Mock 数据 · 待 commit 2 CSV 导入 · commit 3 日志编辑器 · commit 4 月度统计 · M5 接 SQLiteJournalStore"
- [ ] 窗口最小 880×520 · 默认 1100×720
- [ ] ⌘J 在前台时生效 · 不与全局 ⌘N/⌘L/⌘R/⌘B/⌘, 冲突

### commit 2（CSV 导入面板 · NSOpenPanel + DealCSVParser + 格式 Picker + 错误展示）
- [ ] 顶部 header 加"导入"按钮（Label "导入" + square.and.arrow.down · ⌘⇧M iMport）
  - [ ] .help() tooltip "导入交割单 CSV（⌘⇧M · 文华 / 通用格式）"
  - [ ] 按钮位于 stats 与进度标签之间
  - [ ] 进度标签更新为"commit 2/4 · CSV 导入"
- [ ] 点击"导入"→ NSOpenPanel 弹出：
  - [ ] 标题"选择交割单 CSV 文件"· 提示按钮"导入"
  - [ ] allowedContentTypes = .commaSeparatedText（仅 .csv 可选）
  - [ ] allowsMultipleSelection = false · canChooseDirectories = false
  - [ ] 取消 → 不弹 ImportSheet · 状态不变
- [ ] 选 CSV 后 ImportSheet 弹出（580×540）：
  - [ ] 标题"导入交割单"（title2 + bold）
  - [ ] Form .grouped 三 Section：文件 / CSV 格式 / 解析结果
  - [ ] 文件 Section 显示 fileName（monospaced · lineLimit 1 · truncationMode middle）
  - [ ] CSV 格式 segmented Picker：文华财经 / 通用 CSV
  - [ ] 切换格式 → onChange 触发 parseImport 重解析（无延迟 · 解析结果立即更新）
- [ ] 解析成功（.success）：
  - [ ] checkmark.circle.fill 绿色 + "解析到 N 笔成交"
  - [ ] 行级错误：exclamationmark.triangle.fill 橙色 + "K 行解析失败 · 已跳过"
  - [ ] 行级错误列表 ScrollView（前 10 项 · 80px 高 · "· 第 N 行：错误描述" caption2 灰）
  - [ ] 超 10 项显示"... 余 X 项"
  - [ ] 预览前 5 笔（合约 monospaced + 方向涨红跌绿 + 开平 + "数量 @ 价格" monospaced）
- [ ] 解析失败（.fileError）：
  - [ ] xmark.octagon.fill 红色 + "解析失败：错误描述"
  - [ ] invalidEncoding → "CSV 编码错误（非 UTF-8）"
  - [ ] missingColumn → "第 N 行缺少字段 X"
- [ ] 底部按钮：
  - [ ] 取消（Esc / .cancelAction）→ 关闭 sheet · 不修改 trades
  - [ ] "添加 N 笔"（Return / .defaultAction）→ trades 合并 + 时间倒序 + 切到"成交记录"Tab
  - [ ] N == 0 时"添加"按钮 disabled
- [ ] 测试用真样本 CSV：
  - [ ] Tools/WenhuaCSVImportDemo 样本（如有 sample.csv）能成功解析
  - [ ] 文华表头（合约/买卖/开平/成交价/成交量/手续费/成交时间/成交编号）成功
  - [ ] 通用表头（instrument/direction/offset/price/volume/commission/timestamp/trade_id）成功
- [ ] footer 文案更新为"Mock + 导入数据 · 待 commit 3 日志编辑器 · commit 4 月度统计 · M5 接 SQLiteJournalStore"

### commit 3（日志编辑器 + JournalGenerator 自动生成 · contextMenu + confirmationDialog）
- [ ] 进度标签更新为"commit 3/4 · 日志编辑器"
- [ ] 交易日志 Tab 切换后顶部新增 toolbar 行：
  - [ ] "+ 新建日志"按钮（plus.bubble icon · ⌘⇧J）
  - [ ] "✨ 自动生成"按钮（wand.and.stars icon · ⌘⇧A · trades 空时 disabled）
  - [ ] 选中 N 行时右侧显示"已选 N 篇"
- [ ] 点"+ 新建日志"→ JournalEditorSheet 弹出（620×720 · 标题"新建日志"）：
  - [ ] Form .grouped 6 Section：基本 / 交易理由 / 情绪+偏差 / 教训 / 标签 / 关联成交
  - [ ] 标题 TextField roundedBorder（必填）→ 空时"保存"按钮 disabled
  - [ ] 交易理由 TextEditor（最小 60px）
  - [ ] 情绪 Picker × 5：自信 / 犹豫 / 恐惧 / 贪婪 / 平静（默认 平静）
  - [ ] 偏差 Picker × 8：按计划 / 破止损 / 抢反弹 / 追高 / 抄底 / 过早离场 / 超额交易 / 其他（默认 按计划）
  - [ ] 教训 TextEditor（最小 60px）
  - [ ] 标签 TextField（"如：日内 趋势跟随 RB"占位 · 空格分隔解析为 Set）
  - [ ] 关联成交 DisclosureGroup（"已选 K 笔 / 共 N 可选"）：
    - [ ] new 模式默认收起 / edit 模式（已关联）→ 默认展开
    - [ ] 每行 Toggle：合约 monospaced + 方向涨红跌绿 + 开平 + "K 手 @ 价" + 时间
- [ ] 行右键菜单（contextMenu(forSelectionType: TradeJournal.ID.self)）：
  - [ ] 单选 → "编辑" + Divider + "删除"（destructive 红）
  - [ ] 多选 ≥2 → 菜单不显示（避免批量误操作）
  - [ ] 编辑 → JournalEditorSheet（标题"编辑日志"· 主按钮"更新"· 字段全预填）
  - [ ] 编辑保留 journal.id + createdAt 不变 · updatedAt 自动刷新
- [ ] 删除日志 confirmationDialog：
  - [ ] 标题"删除日志？"· 主按钮"删除「标题」"红色
  - [ ] message："日志将永久移除（关联的 N 笔成交不受影响 · A09 单向引用）。"
  - [ ] 删除后 selectedJournalIDs.remove(journal.id)
- [ ] 点"✨ 自动生成"→ JournalGenerator.generateDrafts(from: trades)：
  - [ ] 弹 GeneratorPreviewSheet（580×540 · 标题"自动生成日志草稿"）
  - [ ] 顶部统计"共 N 篇 · 已选 K"
  - [ ] "全选"按钮 / "反选"按钮（subtracting 模式 · 简化反选语义）
  - [ ] 提示"聚合规则：同合约 + 8h 时间窗口"
  - [ ] 每篇草稿 Toggle + 标题（monospaced）+ "K 笔 · reason 前 60 字…"（lineLimit 2）
  - [ ] 默认全选所有草稿
  - [ ] "添加 K 篇"按钮 → batchAddJournals · 合并按 updatedAt 倒序 · sheet 关闭
  - [ ] 选中 0 篇 → "添加"按钮 disabled
- [ ] footer 文案更新为"⌘⇧M 导入 · ⌘⇧J 新建 · ⌘⇧A 自动生成 · 待 commit 4 月度统计 · M5 接 SQLiteJournalStore"
- [ ] ⌘⇧J / ⌘⇧A 在 ⌘J 窗口为前台时生效 · 不与全局 ⌘N/⌘L/⌘R/⌘B/⌘J/⌘, 冲突

### commit 4（标签搜索 + 月度统计 · WP-53 收官 🎉）
- [ ] 进度标签更新为"commit 4/4 · WP-53 收官"（绿色背景 + 绿色文字 · 区别于 commit 1-3 灰色）
- [ ] 交易日志 Tab toolbar 加搜索框：
  - [ ] magnifyingglass icon + TextField roundedBorder（占位"搜索 标题 / 原因 / 教训 / 标签（空格 AND）"）
  - [ ] 280 px 宽
  - [ ] 输入"日内"→ 实时 filter journals · 显示 tags/title/reason/lesson 含"日内"的
  - [ ] 输入"日内 RB"（多 query）→ AND 匹配（必须同时含"日内"和"RB"）
  - [ ] 大小写不敏感（localizedCaseInsensitiveContains）
  - [ ] 清空搜索 → 显示全部 journals
  - [ ] 搜索作用于 list 和 monthly 两个视图（filteredJournals 上游 computed）
- [ ] toolbar 加视图模式 segmented Picker：
  - [ ] "列表" / "月度" 两选项（130 px）· 默认"列表"
  - [ ] 切换"月度"→ journalsContent 切换到 monthlyView
  - [ ] "已选 N 篇"提示仅在"列表"模式显示
- [ ] 月度视图（journalViewMode == .monthly）：
  - [ ] aggregateMonthly 按 createdAt yyyy-MM 分桶（Asia/Shanghai POSIX）
  - [ ] 月份倒序展示（最近月在前）
  - [ ] 每月一张卡片（灰底 0.06 + 8px 圆角）：
    - [ ] 卡片标题"yyyy-MM"+ "· N 篇"（title3 + caption 灰）
    - [ ] 情绪分布列：仅显示有计数的（圆点彩色 + displayName + 数字 monospaced 灰）
    - [ ] 偏差分布列：仅显示有计数的（asPlanned 绿 / 其他橙）
    - [ ] 热门标签行："热门标签：A · B · C · D · E"（top 5 by count）
  - [ ] 数据空（aggregates.isEmpty）时：
    - [ ] calendar.badge.exclamationmark icon + "无可聚合的日志"
    - [ ] 搜索条件下 → 提示"搜索条件下没有匹配项"
    - [ ] 无搜索 + journals 空 → 提示"添加日志后这里会按月汇总"
- [ ] simplifier 优化体现：
  - [ ] MonthlyCard 用 distributionColumn<Case: Hashable> 泛型 helper（情绪 / 偏差 调用同函数 · label 闭包注入差异化渲染）
- [ ] footer 文案"⌘⇧M 导入 · ⌘⇧J 新建 · ⌘⇧A 自动生成 · 搜索 + 月度聚合 · M5 接 SQLiteJournalStore"
- [ ] WP-53 4 commit 全部完成 · ⌘J 完整工作流：
  - [ ] commit 1 双 Tab + Mock 13 trades + 5 journals
  - [ ] commit 2 CSV 导入 + 错误展示
  - [ ] commit 3 编辑器 + 自动生成 + contextMenu
  - [ ] commit 4 搜索 + 月度统计

---

## IndicatorCore 增量 API（WP-41 v2 · 4 commit · 已交付 · ChartScene 接入）

### 回放性能验收（Mac · ChartScene 接入增量后）
- [ ] 进入 .replay 模式 · 拉 1000 根历史 K · 按 ▶ 启动
- [ ] 回放速度 1× / 2× / 4× / 8× / 16× 切换：
  - [ ] 8× 速度下 K 线推进流畅（无明显卡顿 / 帧率掉到 < 30fps）
  - [ ] 16× 极速下也不卡（增量 step 应 < 100µs · 远低于全量 50ms）
  - [ ] MA5 / MA20 / MA60 / BOLL 折线随回放增量延伸 · 无重绘抖动
- [ ] 回放 ⏸ 暂停 / ⏪ 倒退（seek 走全量 rebuild）：
  - [ ] 倒退后再播放 · 增量 runner 在 rebuildBarsToCursor 中正确重置（无残留旧 state）
  - [ ] 倒退后 indicators 与正向播放至同位置一致（无差异）
- [ ] 实盘 .live 模式 completedBar 也走增量：
  - [ ] 5s 轮询新 K 加入时 indicators append 1 个新值 · 不全量重算
  - [ ] 切合约 / 切周期 / 切模式 → indicatorRunner = nil · 重新 prime
- [ ] Mock fallback（Sina 不可达）：
  - [ ] 5000 根 random walk 加载后 · indicatorRunner 也 prime
  - [ ] 后续如有新 K 加入（无）· 不报错

### 与全量算法等价性（用全量 calculate 对比）
- [ ] MA5 / MA20 / MA60 / BOLL-UPPER / BOLL-LOWER 末值与 MockKLineData.computeIndicators(bars: 全部) 完全一致（增量与全量算法等价 · IncrementalIndicatorTests 已断言）

---

## IndicatorCore 增量 API v3 扩展（WP-41 v3 · KDJ/CCI/ATR · 4 commit 全部交付 🎉）

### commit 1（9cebc3a · KDJ 增量 · O(n) per step）
- [ ] KDJ.makeIncrementalState + stepIncremental 与 KDJ.calculate 算法等价（IncrementalIndicatorTests 已断言）
- [ ] history 满 + 增量推进 50 根 K/D/J 与全量精确一致（period=9）
- [ ] history 空 · 前 8 步 nil · 第 9 步起匹配全量
- [ ] 全平 close → rsv=0 → K = K * 2/3 收敛 · 22 步后 < 0.1
- [ ] processStep 共享 init+step 核心（与 RSI 同模式 · ring 写入 O(1) · 扫描 O(n)）

### commit 2（64a1f21 · CCI 增量 · TP ring + sum + O(n) MD）
- [ ] CCI 与全量精确一致（period=20）
- [ ] history 空 · 前 9 步 nil · 第 10 步起匹配全量
- [ ] 全平 close → md=0 → 始终 nil（与 calculate 一致）
- [ ] TP=(H+L+C)/3 滑窗 sum 增量更新 · MD = Σ|tp - ma| ring 扫描 O(n)

### commit 3（30bacd9 · ATR 增量 · Wilder 平滑 O(1)）
- [ ] ATR 与全量精确一致（period=14）
- [ ] 第 1 根 K · TR = high - low（无 prevClose · 边界）
- [ ] period=1 边界 · 每步 ATR == 当前根 TR
- [ ] state.atr 流式未 round（与 Kernels.wilder 内部 prev 一致 · 输出 round8）
- [ ] processStep 共享 init+step（与 RSI 同模式）

### commit 4（性能基准扩展 · 8 指标全测 · WP-41 v3 收官 🎉）
- [ ] swift run -c release IncrementalIndicatorBenchmark 输出 8 指标全测：
  - [ ] MA(20) / EMA(12) / RSI(14) / MACD(12,26,9) / BOLL(20,2)（v2 五指标）
  - [ ] KDJ(9,3,3) / CCI(20) / ATR(14)（v3 三指标）
- [ ] 满批同等工作量加速比 1.0-2.2×（增量 makeState 一次性成本均摊 · 实际回放每帧 step 1 次 ≈ 1000×）
- [ ] 实际回放性能验证：8 指标接入 ChartScene（M5）后 16× 速度无卡顿

### Mac 切机替换（M5）
- [ ] ChartScene.ChartIndicatorRunner 扩展支持新 3 指标（同 MA/BOLL pattern · 加 KDJ/CCI/ATR state 字段）
- [ ] 8 指标增量同时推进时回放 16× 帧率 ≥ 60fps（无掉帧）

---

## IndicatorCore 增量 API v3 第 2 批扩展（OBV/WR/ADX/DMI · 4 commit 全部交付 🎉）

### commit 1（c3259de · OBV 增量 · 累积式 O(1)）
- [ ] OBV.makeIncrementalState + stepIncremental 与 OBV.calculate 算法等价
- [ ] history 满 + 增量推进 50 根与全量精确一致（80 根 K · history 30）
- [ ] history 空 · 第 1 根 OBV = volume（无 warm-up · 无周期参数）
- [ ] close 全平 → OBV 始终 = 首根 volume

### commit 2（4ba5501 · WilliamsR 增量 · KDJ ring 简化版）
- [ ] WR 与全量精确一致（period=14）
- [ ] history 空 · 前 9 步 nil · 第 10 步起匹配全量（period=10）
- [ ] 全平 high/low → 始终 nil（h > l 守卫）
- [ ] state 4 字段（KDJ 13 字段的 1/3 · 简化模式）

### commit 3（f029aa3 · ADX + DMI 增量 · 4 路 Wilder + 复用）
- [ ] ADX 三列（ADX/+DI/-DI）与全量精确一致（period=14）
- [ ] history 空 · 60 根 K 全程匹配全量
- [ ] 关键精度对齐：用 round8(state.atr) snapshot 算 +DI/-DI（同 RSI commit 2/4 修正）
- [ ] DMI 复用 ADX state（typealias · 零开销）· +DI/-DI 与全量一致

### commit 4（性能基准 12 指标 · WP-41 v3 第 2 批收官 🎉）
- [ ] swift run -c release IncrementalIndicatorBenchmark 输出 12 指标全测：
  - [ ] v2 五指标：MA / EMA / RSI / MACD / BOLL
  - [ ] v3 第 1 批三指标：KDJ / CCI / ATR
  - [ ] v3 第 2 批四指标：OBV / WR / ADX / DMI
- [ ] 满批同等工作量加速比 0.8-2.1×（多数 1.0× · MA/BOLL 因 ring sum 优化加速明显）
- [ ] DMI 与 ADX 性能几乎一致（验证零开销复用）

### Mac 切机替换（M5）
- [ ] ChartScene.ChartIndicatorRunner 扩展支持 12 指标
- [ ] 12 指标增量同时推进 · 16× 回放速度无掉帧

---

## IndicatorCore 增量 API v3 第 3 批（Stochastic · 13 指标全覆盖）

### Stochastic 增量（双 ring HHV/LLV + %K_raw 滑动 sum 给 %D）
- [ ] Stochastic 与全量精确一致（period=14 · smooth=3 · 80 K · history 30）
- [ ] history 空 · 60 根 K 全程匹配全量（双 ring · %K 在 period 起 · %D 在 smooth 起）
- [ ] 全平 high/low → %K 始终 nil · %D 始终 0（与文华标准 Kernels.ma(kRaw, s) 一致）
- [ ] 参数缺失 / period<1 / smooth<1 抛错
- [ ] benchmark Stochastic(14,3) 满批增量 1.3× 加速（双 ring 同步推进 · 比 KDJ 单指标输出更紧）

### 13 指标增量基础（Stochastic 加入后）
- [ ] benchmark 完整输出 13 行（v2 五 + v3 第 1 批三 + 第 2 批四 + 第 3 批一）
- [ ] 增量 API 协议生态：13/56 = 23.2% 覆盖率（K 线主图常用全部就位）

---

## IndicatorCore 增量 API v3 第 4 批（TRIX · 内嵌 3 EMA · 14 指标全覆盖）

### TRIX 增量（同 MACD 复合 EMA 模式 · prevE3 round8 差分）
- [ ] TRIX 与全量精确一致（period=12 · 100 K · history 50）
- [ ] history 空 · 60 根 K 全程匹配全量（3 层 EMA 同步推进）
- [ ] 参数缺失 / period<1 抛错
- [ ] 内嵌 EMA.IncrementalState × 3（与 MACD 复用 advance 接口）
- [ ] e2/e3 每步无条件 advance（用 e1 ?? 0 / e2 ?? 0 替换 nil · 与 Kernels.nextEMA 一致）
- [ ] benchmark TRIX(12) 满批 ~1.0× 加速（3 层 EMA 同步推进 · 与 MACD 同等工作量级）

### 14 指标增量基础
- [ ] benchmark 完整输出 14 行
- [ ] 增量 API 覆盖率：14/56 = 25%（IndicatorCore 1/4 已增量化 · 涵盖 K 线主图所有常用）

---

## IndicatorCore 增量 API v3 第 5 批（DEMA + TEMA · 16 指标）

### DEMA 增量（内嵌 2 EMA · 输出 2*e1 - e2）
- [ ] DEMA 与全量精确一致（period=20 · 100 K · history 50）
- [ ] history 空 · 60 根 K 全程匹配全量（period=10）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark DEMA(20) 满批 ~1.0× 加速（2 层 EMA 同步推进 · 比 EMA 单层略多开销）

### TEMA 增量（内嵌 3 EMA · 输出 3*e1 - 3*e2 + e3）
- [ ] TEMA 与全量精确一致（period=20 · 100 K · history 60）
- [ ] history 空 · 60 根 K 全程匹配全量（period=10）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark TEMA(20) 满批 ~0.9× 加速（3 层 EMA 同步 · 与 TRIX 同等工作量级）

### 16 指标增量基础
- [ ] benchmark 完整输出 16 行（v2 五 + v3 五批共十一）
- [ ] 增量 API 覆盖率：16/56 = 28.6%（IndicatorCore 接近 1/3 已增量化）

---

## IndicatorCore 增量 API v3 第 6 批（VWAP + PSY + CMO · 19 指标）

### VWAP 增量（累积式 · 同 OBV 模式 · 无周期 · 无 warm-up）
- [ ] VWAP 与全量精确一致（80 K · history 30）
- [ ] history 空 · 第 1 根即有值（无 warm-up · cumV>0 时）· 全程匹配全量
- [ ] benchmark VWAP 满批 ~1.0× 加速（累积式简单 · 全量本身极快）

### PSY 增量（单 ring sliding sum · 上涨标志 0/1）
- [ ] PSY 与全量精确一致（period=12 · 80 K · history 30）
- [ ] history 空 · 前 9 步 nil · 第 10 步起匹配全量（period=10）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark PSY(12) 满批 1.6× 加速（消除 calculate slidingSum 数组分配开销）

### CMO 增量（双 ring up/dn sliding sum · 同 RSI 思路无 Wilder）
- [ ] CMO 与全量精确一致（period=14 · 80 K · history 30）
- [ ] history 空 · 前 period 步 nil（10 步）· 第 period+1 步起匹配全量（边界：跳过 i=n-1）
- [ ] close 全平 → up=dn=0 → total=0 → 始终 nil
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark CMO(14) 满批 1.8× 加速（最高加速 · 双 ring sliding sum 替代两个数组分配）

### 19 指标增量基础
- [ ] benchmark 完整输出 19 行
- [ ] 增量 API 覆盖率：19/56 = 33.9%（IndicatorCore 1/3 已增量化）

---

## IndicatorCore 增量 API v3 第 7 批（ROC + BIAS · 21 指标）

### ROC 增量（最简 ring 取 n 步前 close · 无 sliding sum）
- [ ] ROC 与全量精确一致（period=12 · 80 K · history 30）
- [ ] history 空 · 前 period 步 nil（10 步）· 第 period+1 步起匹配全量
- [ ] 关键：先取 ring[head] 再覆盖（=即将被覆盖的最旧值 = close[i-n]）
- [ ] benchmark ROC(12) 满批 ~1.0×（极简单 · 无 sliding sum 优化空间）

### BIAS 增量（ring SMA · 与当前 close 比 · 同 MA 增量模式）
- [ ] BIAS 与全量精确一致（period=6 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步 nil · 第 period 步起匹配全量
- [ ] 关键精度对齐：用 round8(ma) snapshot 作下游计算（与 calculate 用 Kernels.ma 数组中 round8 值一致）
- [ ] benchmark BIAS(6) 满批 1.1×（ring sliding sum 节省 calculate ma 数组分配）

### 21 指标增量基础
- [ ] benchmark 完整输出 21 行
- [ ] 增量 API 覆盖率：21/56 = 37.5%（IndicatorCore 接近 2/5 已增量化）

---

## IndicatorCore 增量 API v3 第 8 批（WMA + HMA · 23 指标）

### WMA 增量（O(1) Pascal triangle sliding · 第 8 批最高加速）
- [ ] WMA 与全量精确一致（period=10 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步 nil · 第 period 步起匹配全量（验证 seed numerator/runningSum 正确）
- [ ] period=1 边界 · 每步 WMA == round8(close)（权重和为 1）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark WMA(10) 满批 2.3× 加速（O(1) Pascal sliding 替代每步 O(n) 重新加权累加）
- [ ] WMA.IncrementalState.advance(close:) public mutating method（与 EMA.advance 同模式 · 给 HMA 等内嵌用）

### HMA 增量（内嵌 3 WMA · halfN/n/sqrtN · 同 TRIX 复合模式）
- [ ] HMA 与全量精确一致（period=16 · halfN=8 · sqrtN=4 · 100 K · history 50）
- [ ] history 空 · 60 根 K 全程匹配全量（3 WMA 同步推进）
- [ ] 参数缺失 / period<4 抛错（HMA 数据层 minValue=4）
- [ ] benchmark HMA(16) 满批 1.7× 加速（受益于 3 路 WMA O(1) Pascal sliding）

### 23 指标增量基础
- [ ] benchmark 完整输出 23 行
- [ ] 增量 API 覆盖率：23/56 = 41.1%（IndicatorCore 超过 2/5 已增量化）

---

## IndicatorCore 增量 API v3 第 9 批（PVT + Donchian · 25 指标 · 跨 Volume / Volatility 类）

### PVT 增量（量价累积 · 同 OBV 模式 · 无周期 · 第 1 根 PVT=0）
- [ ] PVT 与全量精确一致（80 K · history 30）
- [ ] history 空 · 第 1 根 PVT=0（无 warm-up · 与 calculate out[0]=0 一致）
- [ ] 全程匹配全量
- [ ] benchmark PVT 满批 ~1.0× 加速（极简累积式 · 全量本身已极快）

### Donchian 增量（双 ring HHV/LLV · 同 KDJ ring 模式 · 输出 [upper, mid, lower]）
- [ ] Donchian 三列与全量精确一致（period=20 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量
- [ ] upper/lower 是 raw HHV/LLV（不 round8 · 与 Kernels.hhv/llv 一致）
- [ ] mid = round8((upper+lower)/2)（与 calculate mid[i] 一致）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark DONCHIAN(20) 满批 ~1.0× 加速（双 ring O(n) 同等工作量）

### 25 指标增量基础（首次跨 Volume + Volatility 双类）
- [ ] benchmark 完整输出 25 行
- [ ] 增量 API 覆盖率：25/56 = 44.6%（IndicatorCore 接近 1/2 已增量化）
- [ ] 量价类增量：OBV + PVT（2）
- [ ] 波动率类增量：BOLL + ATR + Donchian（3）

---

## IndicatorCore 增量 API v3 第 10 批（KC + StdDev + Envelopes · 28 指标 · 波动率三连扩张）

### KC 增量（内嵌 EMA + ATR · 同 MACD 内嵌 EMA 模式 · 输出 [mid, upper, lower]）
- [ ] KC 三列与全量精确一致（emaN=12 atrN=14 mult=2 · 80 K · history 40）
- [ ] history 空 · ema warm-up < atr warm-up：MID 第 12 根（i=11）先输出 · UPPER/LOWER 第 14 根（i=13）才有值
- [ ] mid 直接复用 EMA round8 输出 · upper/lower = round8(mid ± mult * atr)（与 calculate 一致）
- [ ] 参数缺失 / mult≤0 / 仅 2 参 抛错
- [ ] benchmark KC(20,10,2) 满批 ~1.0× 加速（EMA + ATR 都 O(1) · 全量也 O(N) · 加速比有限）

### StdDev 增量（BOLL 简化 · ring + sliding sum + ring.reduce variance · 单列 sd）
- [ ] StdDev 与全量精确一致（period=20 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量
- [ ] 算法与 Kernels.stddev 一致：raw mean + ring reduce variance + sqrt + round8
- [ ] period<2 / 缺参 抛错
- [ ] benchmark STDDEV(20) 满批 ~1.2× 加速（每步 ring.reduce O(N) · 与全量 O(N²) 同等量级）

### Envelopes 增量（MA 复合 · ring + sliding sum · mid ± 百分比偏移 · 输出 [mid, upper, lower]）
- [ ] Envelopes 三列与全量精确一致（period=20 percent=2.5 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量
- [ ] mid = round8(sum/n) · upper/lower 用 round8(mid) snapshot · 与 calculate 中 m * (1±k) 链一致
- [ ] kFactor = pct/100 预计算（state 内不变量 · 不每步重算）
- [ ] 参数缺失 / percent≤0 / 仅 1 参 抛错
- [ ] benchmark ENV(20,2.5) 满批 **~1.8× 加速**（第 10 批最高 · 全量 Kernels.ma O(N²) vs 增量 ring sliding sum）

### 28 指标增量基础（波动率三连扩张 · 6 个波动率类全增量化）
- [ ] benchmark 完整输出 28 行
- [ ] 增量 API 覆盖率：**28/56 = 50.0%**（IndicatorCore 半数已增量化 🎉）
- [ ] 波动率类增量全覆盖：BOLL + ATR + Donchian + KC + StdDev + Envelopes（6 · 与 calculate 全部对齐）
- [ ] 趋势类增量 9：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS
- [ ] 量价类增量 2：OBV / PVT

---

## IndicatorCore 增量 API v3 第 11 批（PriceChannel + HV · 30 指标 · Volatility.swift 6/6 100% 收官 🎉）

### PriceChannel 增量（基于 close 的 Donchian 变体 · 单 ring · 同 Donchian ring 模式简化）
- [ ] PriceChannel 两列与全量精确一致（period=20 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量
- [ ] upper/lower 是 raw HHV/LLV（不 round8 · 与 Kernels.hhv/llv 一致 · 与 Donchian 同模式）
- [ ] 输出 [upper, lower] 仅 2 列（无 mid · 比 Donchian 简化）
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark PC(20) 满批 ~1.0× 加速（单 ring 简化 · 与 Donchian 同 O(n) 扫描 · 全量 Kernels.hhv/llv 已极快）

### HV 增量（log 收益 + ring StdDev + annual scaling · 同 BOLL/StdDev ring 模式 + log 转换层）
- [ ] HV 与全量精确一致（period=20 annual=252 · 80 K · history 30）
- [ ] history 空 · 第 1 根 logRet=0（与 calculate logRet[0]=0 一致 · 入 ring 参与 stddev）
- [ ] 第 2 根起 prevClose>0 时 logRet = log(close/prev) · 否则 0
- [ ] sd 先 round8 snapshot（与 Kernels.stddev 输出一致）· 再乘 annualScale 再 round8（与 calculate out[i] 链一致）
- [ ] annualScale = sqrt(annualDays) * 100 预计算（state 内不变量 · 不每步重算）
- [ ] 参数缺失 / period<2 / annualDays<1 抛错
- [ ] benchmark HV(20,252) 满批 ~1.3× 加速（log 收益 + ring reduce O(N) 与全量 O(N²) 同量级）

### 30 指标增量基础（Volatility.swift 6/6 100% 收官 🎉）
- [ ] benchmark 完整输出 30 行
- [ ] 增量 API 覆盖率：**30/56 = 53.6%**（IndicatorCore 过半 + 5%）
- [ ] **Volatility.swift 单文件 100% 增量化**（KC + Donchian + StdDev + HV + PriceChannel + Envelopes · 加 BOLL.swift / ATR.swift = 8 个波动率类全增量）
- [ ] 趋势类增量 9：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS
- [ ] 量价类增量 2：OBV / PVT
- [ ] 波动率类增量 8（含 BOLL + ATR · 文件外）：BOLL / ATR / Donchian / KC / StdDev / Envelopes / **PriceChannel / HV**

---

## IndicatorCore 增量 API v3 第 12 批（MFI + ADL + VOSC · 33 指标 · Volume.swift 5/5 100% 收官 🎉）

### MFI 增量（TP + 双 ring up/dn money flow · 同 CMO 双 ring 思路 + TP/volume 转换层）
- [ ] MFI 与全量精确一致（period=14 · 80 K · history 30）
- [ ] history 空 · 第 1 根 prevTP=nil → posMF=negMF=0（与 calculate posMF[0]=0 一致 · 入 ring 参与 sum）
- [ ] count 单调递增（不封顶 · 与 BOLL/StdDev 不同）· count > period 守卫跳首窗口（calculate i in n..<count）
- [ ] negSum == 0 时输出 100（与 calculate sn==0 一致）· 否则 round8(100 - 100/(1+mr))
- [ ] ring 已满时减旧值（覆盖前）· 未满时旧位置初值 0 · 不需扣
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark MFI(14) 满批 ~1.3× 加速（双 ring sliding sum O(1) · 与全量 slidingSum O(N²) 同等量级）

### ADL 增量（累积式 · 同 OBV/PVT 模式 · 无周期 · 无 warm-up）
- [ ] ADL 与全量精确一致（无参数 · 80 K · history 30）
- [ ] history 空 · 第 1 根直接输出（hl > 0 时累加 · 与 calculate `for i in 0..<count` 从 i=0 开始一致）
- [ ] hl == 0（H==L · 一字板）→ acc 不变（与 calculate if hl > 0 守卫一致）
- [ ] mfm = ((C-L)-(H-C))/hl · acc += mfm * volume · 输出 round8(acc)
- [ ] benchmark ADL 满批 ~0.9× 加速（极简累积式 · 全量本身已极快 · 同 OBV/PVT）

### VOSC 增量（内嵌 2 EMA · 处理 volume · 同 DEMA/TEMA 复合 EMA 模式）
- [ ] VOSC 与全量精确一致（short=12 long=26 · 80 K · history 40）
- [ ] history 空 · short EMA warm-up < long EMA warm-up · long warm-up 满后才输出
- [ ] EMA.advance(close: Decimal(volume)) 接口处理 volume（不通过 EMA.makeIncrementalState · 避开 EMA 用 closes 字段）
- [ ] EMA.advance 已 round8 · 直接用作 (s-l)/l * 100 · 输出 round8（与 calculate Kernels.ema 输出一致）
- [ ] 参数错误 / long ≤ short / 缺参 抛错
- [ ] benchmark VOSC(12,26) 满批 ~1.2× 加速（2 EMA O(1) · 与全量 O(N) 等级 · 加速比有限同 KC/DEMA）

### 33 指标增量基础（Volume.swift 4/6 进度 · 量价类扩到 5 个）
- [ ] benchmark 完整输出 33 行
- [ ] 增量 API 覆盖率：**33/56 = 58.9%**（IndicatorCore 过半 + 8.9%）
- [ ] **Volume.swift 4/6 增量化**（MFI / ADL / VOSC / PVT 已增量 · CMF / VR 留第 13 批 · Volume 数据 trivial 不需）
- [ ] 量价类增量 5（含 OBV · 文件外）：OBV / PVT / **MFI / ADL / VOSC**（CMF / VR 留第 13 批）

---

## IndicatorCore 增量 API v3 第 13 批（CMF + VR + Volume · 36 指标 · Volume.swift 7/7 100% 收官 🎉 · 量价类全增量化 · CMF 创 3.7× v3 系列加速新纪录）

### CMF 增量（双 sliding sum mfv/vol · 同 BOLL/StdDev ring 模式 · 不跳首窗口）
- [ ] CMF 与全量精确一致（period=20 · 80 K · history 30）
- [ ] history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量（不跳首 · 同 BOLL/StdDev）
- [ ] hl == 0（一字板）→ mfv = 0（与 calculate if hl > 0 守卫一致）· vol 仍入 ring 参与 volSum
- [ ] count == period 守卫输出（封顶 period · 同 BOLL/StdDev · 与 MFI/VR 单调递增不同）
- [ ] volSum > 0 守卫（与 calculate sumV > 0 一致）
- [ ] benchmark CMF(20) 满批 **~3.7× 加速 · v3 系列新纪录**（双 sliding sum O(1) vs 全量双 [Decimal] 数组分配 + 双 Kernels.slidingSum O(N²)）

### VR 增量（三桶 sliding sum up/down/flat · 同 MFI count 单调递增 + 三桶分组）
- [ ] VR 与全量精确一致（period=26 · 80 K · history 30）
- [ ] history 空 · 第 1 根 prevClose=nil → 三桶都 0（与 calculate index 0 一致）
- [ ] count 单调递增（不封顶 · 同 MFI 模式）· count > period 守卫等价 calculate `for i in n..<count` 跳首窗口
- [ ] 第 2 根起：close > prev → upVol；close < prev → downVol；close == prev → flatVol
- [ ] halfFlat = flatSum/2 · denom = downSum + halfFlat · denom > 0 时输出 (upSum + halfFlat) / denom * 100
- [ ] 参数缺失 / period<1 抛错
- [ ] benchmark VR(26) 满批 **~3.0× 加速**（三桶 sliding sum · 全量分配三个 [Decimal] 数组 + 三次 slidingSum）

### Volume 增量（直通 · 极简 · 无周期 · 无 warm-up · 空 IncrementalState）
- [ ] Volume 与全量精确一致（无参数 · 50 K · history 20）
- [ ] history 空 · 第 1 根直接输出 Decimal(volume)
- [ ] 空 IncrementalState struct（Volume 是 Int → Decimal 直通 · 无累积/无窗口/无 prev）
- [ ] benchmark VOL 满批 ~0.1× 加速（合理"减速"· 全量是单一 .map 极快 · 增量 makeIncrementalState 反而有少量开销）

### 36 指标增量基础（Volume.swift 7/7 100% 收官 🎉 · 量价类全增量化）
- [ ] benchmark 完整输出 36 行
- [ ] 增量 API 覆盖率：**36/56 = 64.3%**（IndicatorCore 过半 + 14.3%）
- [ ] **Volume.swift 单文件 7/7 100% 增量化**（Volume + MFI + CMF + VR + PVT + ADL + VOSC 全 7 个）
- [ ] 量价类增量 7（含 OBV · 文件外）：OBV / PVT / MFI / ADL / VOSC / **CMF / VR / Volume** （量价类全部增量化）
- [ ] 趋势类增量 9：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS
- [ ] 波动率类增量 8：BOLL / ATR / Donchian / KC / StdDev / Envelopes / PriceChannel / HV
- [ ] **CMF 3.7× 加速创 v3 系列新纪录**（之前最高 MA 2.5× / WMA 2.3×）

---

## IndicatorCore 增量 API v3 第 14 批（OpenInterest + OIDelta + PivotPoints · 39 指标 · 期货持仓 + 结构 2 类首发增量化）

### OpenInterest 增量（直通 · 同 Volume 模式 · 极简 · 无周期 · 无 warm-up · 空 IncrementalState）
- [ ] OpenInterest 与全量精确一致（无参数 · 50 K · history 20）
- [ ] history 空 · 第 1 根直接输出 KLine.openInterest
- [ ] 空 IncrementalState struct（OI 是 Decimal 直通 · 无累积/无窗口/无 prev）
- [ ] 注意类型不一致：KLine.openInterest 是 Decimal · KLineSeries.openInterests 是 [Int]（项目历史不一致 · 增量直接用 Decimal）
- [ ] benchmark OI 满批 ~0.1× 加速（合理"减速" · 同 Volume · 全量是单一 .map 极快）

### OIDelta 增量（diff 模式 · 同 PVT 第 1 根=0 · 无周期 · 无 warm-up）
- [ ] OIDelta 与全量精确一致（无参数 · 50 K · history 20）
- [ ] history 空 · 第 1 根 prevOI=nil → 输出 0（与 calculate out[0]=0 一致）
- [ ] state.prevOI 用 Decimal? 而非 Int?（KLine.openInterest 是 Decimal · 增量内部统一 · makeIncrementalState 把 Int 转 Decimal 传入）
- [ ] OI 持平场景验证 → 输出 0（diff 为 0）
- [ ] OI 上涨场景验证 → 输出正值（diff 为正）
- [ ] benchmark DOI 满批 ~0.1× 加速（合理"减速" · 全量极简 diff · 增量有空 state 开销）

### PivotPoints 增量（基于前一根 H/L/C · 7 列输出 · 同 PVT prevClose 模式扩展到 3 字段）
- [ ] PivotPoints 7 列与全量精确一致（无参数 · 50 K · history 20）
- [ ] history 空 · 第 1 根 prev=nil → 全 7 列 nil（与 calculate `for i in 1..<count` 跳第 1 根一致）· 第 2 根起匹配全量
- [ ] state = prevH / prevL / prevC（3 个 Optional Decimal · 第 1 根 nil）· defer 写法保证 prev 在 return 后才更新
- [ ] 公式验证：pivot = (h+l+c)/3 · R1 = 2P-l · S1 = 2P-h · R2 = P+(h-l) · S2 = P-(h-l) · R3 = h+2(P-l) · S3 = l-2(h-P)
- [ ] 7 列输出顺序与 calculate 一致：[P, R1, S1, R2, S2, R3, S3]
- [ ] benchmark PIVOT 满批 ~1.0× 加速（无 sliding 优化 · 全量也是 O(N) 单趟）

### 39 指标增量基础（期货持仓 + 结构 2 类首发增量化）
- [ ] benchmark 完整输出 39 行
- [ ] 增量 API 覆盖率：**39/56 = 69.6%**（IndicatorCore 过半 + 19.6% · 接近 7/10）
- [ ] **持仓类增量首发 2**：OpenInterest（直通）+ OIDelta（diff）（独立类别 futures 首发）
- [ ] **结构类增量首发 1**：PivotPoints（7 列输出 · 复合状态）（剩 ZigZag/Ichimoku/Fractal 留第 15 批）
- [ ] 趋势类增量 9：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP（剩 SAR / Supertrend）
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS（已 100%）
- [ ] 量价类增量 8：OBV / PVT / MFI / ADL / VOSC / CMF / VR / Volume（已 100%）
- [ ] 波动率类增量 8：BOLL / ATR / Donchian / KC / StdDev / Envelopes / PriceChannel / HV（已 100%）
- [ ] 持仓类增量 2：OpenInterest / OIDelta（首发）
- [ ] 结构类增量 1：PivotPoints（首发 · 剩 3 个）

---

## IndicatorCore 增量 API v3 第 15 批（Supertrend · 40 指标 · 趋势状态机首发增量化）

### Supertrend 增量（内嵌 ATR + 状态机 upperBand/lowerBand/isUp/prevClose）
- [ ] Supertrend 与全量精确一致（period=10 multiplier=3 · 100 K · history 40）
- [ ] history 空 · ATR warm-up 期前 period-1 步全 nil（i=0..8）· 第 period 步起匹配全量（i=9）
- [ ] 含趋势翻转场景验证（isUp && close < newLower → 转空 · !isUp && close > newUpper → 转多）
- [ ] state 6 字段必要：multiplier / atrState / upperBand? / lowerBand? / isUp / prevClose?
- [ ] warm-up 期 atr nil → 不更新 band/isUp · 仅由 defer 推进 prevClose（替代 calculate 中 closes[i-1] 的隐式索引）
- [ ] 带状收紧公式：prev != nil 时 (rawUp < prev || prevClose > prev) ? rawUp : prev · prev nil 时直接 rawUp
- [ ] makeIncrementalState 内手动构造 KLine 中转 · 共享 history 循环推进 atrState + 状态机（设计取舍 · stepIncremental 路径透传零成本）
- [ ] 参数错误 / multiplier≤0 / period<1 / 缺参 抛错
- [ ] benchmark Supertrend(10,3) 满批 ~1.1× 加速（内嵌 ATR + 状态机 O(1) per step · 全量也 O(N) · 加速比有限同 KC）

### 40 指标增量基础（趋势状态机首发增量化）
- [ ] benchmark 完整输出 40 行
- [ ] 增量 API 覆盖率：**40/56 = 71.4%**（IndicatorCore 接近 5/7）
- [ ] **趋势状态机增量首发**：Supertrend（剩 SAR · 用未来信息 closes[1] 决定方向 · 不能严格增量化）
- [ ] 趋势类增量 10：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP / **Supertrend**（剩 SAR）
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS（已 100%）
- [ ] 量价类增量 8：OBV / PVT / MFI / ADL / VOSC / CMF / VR / Volume（已 100%）
- [ ] 波动率类增量 8：BOLL / ATR / Donchian / KC / StdDev / Envelopes / PriceChannel / HV（已 100%）
- [ ] 持仓类增量 2：OpenInterest / OIDelta（已 100%）
- [ ] 结构类增量 1：PivotPoints（剩 ZigZag/Fractal/Ichimoku · 涉及未来信息 / 非线性 / 延迟列）

---

## IndicatorCore 增量 API v3 第 16 批（Ichimoku 部分增量 · 41 指标 · v3 系列收官 🎉 · 41/44 = 93.2%）

### Ichimoku 部分增量（4/5 列 · 内嵌 3 Donchian midBand + 2 延迟 ring · CHIKOU 永远 nil）
- [ ] Ichimoku 4/5 列与全量精确一致（tenkan=9 kijun=26 senkou=52 · 120 K · history 60）
- [ ] state = kN + 3 Donchian.IncrementalState + 2 Decimal? 延迟 ring + 各 head（9 字段 · 都必要）
- [ ] TENKAN/KIJUN：复用 Donchian.stepIncremental row[1] mid（已 round8 · 与 calculate midBand 等价）
- [ ] SENKOU-A：先读 senkouADelayRing[head]（旧值 = senkouARaw[i-kN]）· 再写入新 round8((tenkan+kijun)/2) · head++
- [ ] SENKOU-B：复用同款延迟 ring 模式 · 写 senkouBState mid · 读 kN 步前的 mid
- [ ] CHIKOU：增量永远输出 nil（calculate 中 chikou[i] = closes[i+kN] 用未来 close · 增量协议不支持）
- [ ] history 空 · 各 midBand warm-up + senkouA/B 延迟 kN 根 · 全程 4 列匹配全量
- [ ] makeIncrementalState 内手动构造 KLine 中转 · 共享 history 循环（同 Supertrend 模式）
- [ ] 参数错误 / 缺参 / 周期≤0 抛错
- [ ] benchmark Ichimoku(9,26,52) 满批 ~1.0× 加速（内嵌 3 Donchian + 延迟 ring · 全量也 O(N) 多趟 · 加速比有限）

### 41 指标增量基础（v3 系列收官 🎉 · 协议允许范围内全部增量化）
- [ ] benchmark 完整输出 41 行
- [ ] 增量 API 覆盖率：**41/44 = 93.2%**（IndicatorCore 协议允许范围全覆盖）
- [ ] **v3 系列收官里程碑**：剩 3 个不可严格增量化的指标已明确文档
  - SAR：calculate out[0] 依赖 close[1] 决定方向 · 用未来信息 · 不可严格增量
  - Fractal：需要 i+2 才能判定 i 中心点 · 用未来信息 · 不可严格增量
  - ZigZag：非线性 · 标记 pivot 时回写历史 · 不可增量
- [ ] 趋势类增量 10：MA / EMA / WMA / DEMA / TEMA / HMA / ADX / DMI / VWAP / Supertrend
- [ ] 震荡类增量 11：RSI / KDJ / CCI / MACD / WR / Stochastic / TRIX / PSY / CMO / ROC / BIAS
- [ ] 量价类增量 8：OBV / PVT / MFI / ADL / VOSC / CMF / VR / Volume
- [ ] 波动率类增量 8：BOLL / ATR / Donchian / KC / StdDev / Envelopes / PriceChannel / HV
- [ ] 持仓类增量 2：OpenInterest / OIDelta
- [ ] 结构类增量 2：PivotPoints / **Ichimoku（4/5 列）**

### v3 系列模式沉淀总结（16 批积累的可复用模式）
- 滑动 sum 类（O(1)）：MA / BIAS / CMF（双 sliding sum）/ VR（三桶 sliding sum）
- HHV/LLV ring 类：Donchian / KDJ / WR / Stochastic / PriceChannel
- prev EMA Wilder 类：EMA / RSI / ATR / ADX / TRIX
- 复合 EMA 类：MACD / TRIX / DEMA / TEMA / HMA（内嵌 WMA）/ KC / VOSC / Supertrend
- 累积式无周期：OBV / PVT / VWAP / ADL
- 双 ring up/dn / TP+volume：CMO / MFI
- O(1) Pascal sliding：WMA · v3 第 8 批新引入最高效模式
- 直通极简：Volume / OpenInterest
- diff 模式：OIDelta · 同 PVT 第 1 根=0
- 状态机：Supertrend · 趋势翻转
- 复合内嵌（同模型 · 不同 period）：HMA 3 WMA / Ichimoku 3 Donchian
- 延迟 ring（前移 N 根）：Ichimoku senkouA/B
- 关键模式：count 单调递增 vs 封顶（calculate 是否跳首窗口）· round8 snapshot 精度对齐 · advance(close:) 内嵌接口 · processStep helper 共享 makeIncrementalState/stepIncremental

---

## M5 持久化集中接入 SQLite · 第 1 批（Watchlist + Workspace · 切机后端到端验证）

### 启动 + 路径
- [ ] Mac 启动 App → `~/Library/Application Support/FuturesTerminal/db/` 自动创建
- [ ] 6 个 .sqlite 文件存在：analytics / kline_cache / journal / alert_history / watchlist / workspace
- [ ] StoreManager init 失败时 storeManager=nil · App 仍能启动 · Window 自动 fallback Mock（容错）

### Watchlist 持久化（⌘L）
- [ ] 首次启动 · watchlist.sqlite 空 · WatchlistWindow 显示 Mock 默认 3 组 9 合约
- [ ] 添加分组 · contextMenu 重命名 · 添加合约 · 拖拽排序 · 全部即时 save 到 SQLite
- [ ] 关闭 App · 重启 → 上次的修改持久化保留（不再回到 Mock）
- [ ] 删除分组 · 重启后真删除（不再出现）

### Workspace 持久化（⌘K）
- [ ] 首次启动 · workspace.sqlite 空 · WorkspaceWindow 显示 Mock 默认 4 模板
- [ ] CRUD 模板 · 切换激活 · 网格预设 · 编辑 windows · 快捷键编辑器 · JSON 导入/导出 · 拖拽排序 · 全部即时 save
- [ ] 关闭 App · 重启 → 上次的所有修改持久化保留
- [ ] activeTemplateID 持久化（重启后激活态保留）
- [ ] 快捷键持久化（⌘⇧1 / ⌘⇧2 等绑定保留）

### isLoaded 守卫验证
- [ ] 启动瞬间 Mock book 显示 · .task load 完成后切到真数据（首启 .task load 返回 nil → 保留 Mock）
- [ ] isLoaded=true 之后才 onChange 触发 save · 避免 Mock 误写覆盖磁盘真数据
- [ ] 首启情况：Mock 显示 → 用户首次修改 → save 到磁盘（覆盖空库）

### 性能 + 兼容性
- [ ] Watchlist mutation 后 save 异步执行（不阻塞 UI · Task 内 await）
- [ ] Workspace mutation 后 save 异步执行
- [ ] swift test 790/197 全绿（StoreManagerTests / SQLiteWatchlistBookStoreTests / SQLiteWorkspaceBookStoreTests 都绿）

### M5 持久化第 2 批 · Alert load history（占位接入 · evaluator 未接 · 半小时）
- [ ] AlertWindow 启动 .task 优先从 SQLiteAlertHistoryStore.allHistory() 加载真实历史
- [ ] 库空 / load 失败时 fallback MockAlertHistory.generate()
- [ ] alerts 数组仍 Mock（StoreManager 暂无 AlertConfigStore · 后续补）
- [ ] evaluator 接入前 history 库一直空 · 显示和 Mock 一致
- [ ] evaluator 接入后真实触发的 entry 写入 store · 重启后保留

### M5 持久化第 3 批 · Journal 集成（trades + journals UPSERT + 显式 delete · 1 小时实际工时）
- [ ] JournalWindow 启动 .task 优先 load store.loadAllTrades + loadAllJournals
- [ ] 库内任一类非空（trades 或 journals）即用真实数据 · 都空才 fallback MockJournalData
- [ ] onChange(of: trades) → store.saveTrades(trades) 全量批量 UPSERT（INSERT OR REPLACE）
- [ ] onChange(of: journals) → for j in newValue: store.saveJournal(j) 逐个 UPSERT（协议无批量）
- [ ] deleteJournal 显式调 store.deleteJournal(id:)（onChange 只能 UPSERT 不能 DELETE）
- [ ] trades 当前无显式 delete 路径（无删除 UI · import 是 append 累加）· 后续若加删除需补 store.deleteTrade
- [ ] isLoaded 守卫保护 · 防 Mock 误写覆盖磁盘真数据
- [ ] 重启 App → 上次的 trades + journals 持久化保留（不再回到 Mock）
- [ ] 删除日志重启后真删（不再出现）
- [ ] CSV 导入 → trades 累加 → 自动 save 持久化

### M5 持久化第 4 批 · ChartScene 接 SQLiteKLineCacheStore（K 线缓存 fast-path · 半小时实际工时）
- [ ] ChartScene loadAndStream 网络 fetch 前先 load 磁盘缓存 → 立即显示老数据（dataSourceLabel="本地缓存（N 根）"）
- [ ] 网络 snapshot 来后异步 store.save(snapBars, instrumentID, period) 全量替换
- [ ] completedBar 来后异步 store.append([k], ..., maxBars: 5000) 单根追加（防无限增长）
- [ ] 网络拉空 snapshot 但磁盘有缓存时保持缓存（dataSourceLabel="本地缓存（离线）"·不再退回 Mock · 离线友好）
- [ ] 启动重启后立即看到上次的 K 线数据（不等网络 · 提升首屏速度）
- [ ] loadReplay（回放路径）不接 store（历史数据已在云端 · 不需缓存）
- [ ] maxBars=5000 硬编码上限（约 21 天分钟线 / 5000 天日线）
- [ ] 多窗口（⌘N）同时拉同合约/周期时 SQLite actor 串行 OK · 无竞态

### 留待第 5-N 批（持续推进）
- [ ] AnalyticsEventStore 埋点落库（0.5 天 · 项目可能尚无埋点代码 · 优先级最低）
- [ ] AlertEvaluator 接入 + alerts 数组持久化（需补 AlertConfigStore · 设计未定）

---

## 工作区模板 ⌘K（WP-55 UI · 4 commit · 全部已交付 🎉）

### commit 1（d1ff2f5 · ⌘K 起步 · NavigationSplitView + 4 Kind + Mock 4 模板）
- [ ] ⌘K 打开"工作区模板"窗口（主菜单 File 内"工作区模板"入口）
- [ ] sidebar 220-300px 宽 · 顶部 "工作区模板" + "4 个" 计数
- [ ] 4 模板按 Kind 分 4 Section：盘前 1 / 盘中 1 / 盘后 1 / 自定义 1
- [ ] 当前激活模板（默认"盘中主交易"）★ 标记 + .semibold 字体加粗
- [ ] 模板行下方 caption2："N 窗口" + 已绑快捷键的显示 ⌘ icon（commit 4 Mock 已默认绑）
- [ ] 选模板后 detail 显示：
  - [ ] 标题 + Kind capsule（4 色：橙=盘前/红=盘中/蓝=盘后/灰=自定义）
  - [ ] 激活态显示 "当前激活" capsule（accentColor.opacity(0.15)）
  - [ ] 窗口布局卡片：N 窗口 · 每行（窗口 N / 合约 / 周期 / 指标列表）
  - [ ] 一键切换快捷键卡片
- [ ] 未选模板 → 空 state（rectangle.stack icon）
- [ ] footer 显示当前激活模板名 + 收官 capsule
- [ ] Mock 4 模板 windows 数量正确：盘前 1 / 盘中 4 (grid2x2) / 盘后 2 (vertical2) / 自定义 0

### commit 2（a09d8b8 · CRUD + 切换激活）
- [ ] sidebar 顶部 "+" 按钮 ⌘⇧K → TemplateEditorSheet（add mode）
- [ ] TemplateEditorSheet：
  - [ ] 模板名 TextField（trim 后非空才能保存）
  - [ ] Kind segmented Picker 4 类（盘前/盘中/盘后/自定义）
  - [ ] add 模式默认 .custom · edit 模式预填原值
  - [ ] edit 模式下任一字段未变 → "更新"按钮 disabled（canSubmit 守卫 no-op）
- [ ] 添加后自动选中新模板（selectedTemplateID = 新 id）
- [ ] 行 contextMenu 4 项依序展示：
  - [ ] 重命名 / 修改类型（→ edit sheet · 改名 + 改 kind 都生效 · updateTemplate 整体覆盖保留 id/sortIndex/createdAt）
  - [ ] 复制为副本（→ duplicateTemplate · 深拷贝 windows · 自动选中副本 · 副本不复制快捷键避免冲突）
  - [ ] 设为当前激活（仅非激活时显示）
  - [ ] 删除模板（destructive）
- [ ] 删除前 confirmationDialog："模板「XXX」内的 N 个窗口布局将一并清空 · 该操作无法撤销"
- [ ] 删除当前激活模板 → selectedTemplateID 自动切到 activeTemplateID 或 templates.first
- [ ] 双击 sidebar 行 → 立即 activate（同 contextMenu "设为当前激活"效果）
- [ ] detail header 非激活态显示 .borderedProminent "设为当前激活" 按钮
- [ ] 切换激活 → sidebar ★ icon 立即移到新激活行 + footer 同步更新

### commit 3（1a3e22b · 网格预设 + windows 编辑）
- [ ] detail 窗口布局卡片顶部 toolbar：
  - [ ] "+ 添加窗口" 按钮（任意时刻可点）
  - [ ] "应用网格预设" 按钮（windows 为空时 disabled · 含 help 提示）
- [ ] WindowEditorSheet（add / edit 共用）：
  - [ ] 合约 ID TextField（trim + uppercase 提交）
  - [ ] 周期 Picker（.menu 风格 · 9 周期 1分/5分/15分/30分/60分/4小时/日线/周线/月线）
  - [ ] 指标 IDs TextField（"MA5, MA20, BOLL" 风格 · 提交时 split + trim + uppercase + 顺序去重）
  - [ ] add 默认 5分 · edit 模式预填 instrumentID/period/indicatorIDs
  - [ ] add → append 到 windows 末尾 / edit → 保留原 id + frame + zIndex
- [ ] windowRow 双击 → editWindow / contextMenu 编辑窗口 / 删除窗口
- [ ] 删除窗口立即生效（windowsCard 标题"N 窗口"实时更新 · sidebar 行也实时）
- [ ] ApplyGridSheet：
  - [ ] LazyVGrid 3 列 · 6 张预设卡片：
    - [ ] 单窗口 (1×1)
    - [ ] 1×2 横排
    - [ ] 2×1 竖排
    - [ ] 2×2 四宫
    - [ ] 2×3 六宫
    - [ ] 3×2 六宫
  - [ ] 每卡 mini preview（accentColor.opacity(0.3) 填充 + accentColor 描边 · 用 dimensions 直出格子 · 间距 2px）
  - [ ] 卡片下方"最多 N 窗口" caption2
  - [ ] 选中卡片高亮（accentColor.opacity 0.15 背景 + 2px accentColor 描边）
  - [ ] maxWindows < 当前 windows.count → 底部橙色 exclamationmark.triangle "应用后将截断 N 个窗口"
  - [ ] 未选中时"应用"按钮 disabled
- [ ] 应用网格 → 保留 instrumentID / period / indicatorIDs · 仅替换 frame（不破坏窗口语义）
- [ ] 截断验证：盘中（4 windows）应用 single → 留 1 个 / 应用 grid2x3 → 不截断（max 6）

### commit 4（e6d79c9 · 快捷键编辑器 + 主图联动 + 收官 🎉）
- [ ] shortcutCard 双态：
  - [ ] 已绑态：capsule 显示完整快捷键（⌘⇧K / ⌘1 / ⌘⇧⌥X 等格式 · monospaced）+ "修改"按钮 + "清除" destructive 按钮
  - [ ] 未绑态：显示"未绑定" + "设置快捷键"按钮
  - [ ] 全局唯一性提示 caption2："抢占其他模板的相同快捷键时会自动清空对方绑定"
- [ ] ShortcutEditorSheet：
  - [ ] 标题 "设置快捷键 · 「模板名」"
  - [ ] 修饰键 4 个 Toggle.button 横排（⌘ ⇧ ⌥ ⌃ · 可多选）
  - [ ] 按键 Picker.menu（A-Z + 0-9 = 36 项）
  - [ ] 预览 capsule 实时更新（修饰符号 ⌃⌥⇧⌘ 顺序 + 字符 · 与 formatShortcut 一致）
  - [ ] 至少 1 个修饰键开启时才能"应用"（裸字符快捷键劫持普通输入 → "应用"按钮 disabled）
  - [ ] 占用警告（选中已被其他模板用的快捷键时显示）：橙色 exclamationmark.triangle + "该快捷键当前由「XXX」占用 · 应用后将自动从对方清除"
  - [ ] 占用警告 不显示自己（template.id 命中跳过）
  - [ ] 编辑模式预填当前快捷键 / 新建模式默认 ⌘K
- [ ] 应用快捷键后立即效果：
  - [ ] sidebar 行下方 ⌘ icon 出现
  - [ ] detail capsule 立即更新（蓝色 accentColor 背景 · monospaced）
  - [ ] 抢占其他模板的相同快捷键 → 对方 ⌘ icon 立即消失（数据层 setShortcut 强制全局唯一）
- [ ] "清除"按钮立即清空 capsule + sidebar ⌘ icon 消失（status: 未绑定）
- [ ] Mock 默认 2 模板已绑快捷键（启 App 立即可见）：
  - [ ] 盘中主交易 ⌘⇧1
  - [ ] 盘后复盘 ⌘⇧2
- [ ] formatShortcut 完整格式：
  - [ ] ⌘K（仅 ⌘）
  - [ ] ⌘⇧K（⌘ + ⇧）
  - [ ] ⌘⌥1（⌘ + ⌥）
  - [ ] ⌘⇧⌥⌃Z（4 modifier 全开）
  - [ ] keyCode 不在表中 → 回落 hex（如 0x33 · 测试边界）
- [ ] 双击 sidebar 行 / contextMenu 设为激活 / detail "设为当前激活"按钮 → 都触发 activate
- [ ] activate 时 NotificationCenter post .workspaceTemplateActivated（M5 stub · ChartScene 暂不接 · 不报错）
- [ ] footer 右侧绿色 capsule "WP-55 收官 🎉"（与 WP-53 收官风格一致）
- [ ] 整体回归：commit 1-3 所有功能仍正常（CRUD / 网格 / windows 编辑 / 切换激活）

### v1.5（拖拽排序模板 · 同 WP-43 commit 3 模式）
- [ ] sidebar 模板长按拖动 → 拖拽预览（rectangle.stack icon + 模板名 · regularMaterial 背景 · 圆角 6）
- [ ] 同 Kind 内拖到目标行前：
  - [ ] 落点上方 2px 蓝色 accentColor 横线（hover 命中提示）
  - [ ] 松手 → book.moveTemplate(from:to:) · sortIndex normalizeSortIndices 重整为 0..<N
  - [ ] 落到自己 / 自己之后相邻位置 → no-op（resolveDropIndex 返回 nil）
- [ ] 跨 Kind 拒绝：
  - [ ] 例：拖盘前模板到盘中 Section · dropDestination 返回 false
  - [ ] hoverTemplateID 不更新（无蓝条提示）
  - [ ] 想改 kind → 走 contextMenu「重命名 / 修改类型」（commit 2 已有）
- [ ] 拖拽过程不影响其他交互（双击激活 / contextMenu 仍可用）
- [ ] 拖拽完成后 hoverTemplateID 自动清空（defer 守卫）

### v2（模板预览图 · sidebar 行右侧 mini layout · 同 ApplyGridSheet 思路）
- [ ] 每个 sidebar 行右侧显示 32×20px mini preview
- [ ] 已应用网格预设的模板（盘前 1 全屏 / 盘中 2×2 grid / 盘后 vertical2）→ 准确反映 windows.frame 布局
- [ ] 自定义模板（windows 空 / frame zero）→ mini preview 灰底无内容（视觉提示"未配置"）
- [ ] 添加新窗口（commit 3 默认 frame=.zero）→ mini preview 仍灰 · 应用网格预设后立即更新
- [ ] 行高度合适（不显得太挤 · 不挤压模板名 + N 窗口/⌘ 描述）
- [ ] 拖拽排序时 mini preview 跟随移动（不影响 .draggable 模式）
- [ ] accentColor.opacity(0.35) 填充 + 0.6 描边（hue 与活态 ★ 一致）
- [ ] 圆角 2px clipShape（与卡片视觉系统一致）

### v1.7（JSON 导入 / 导出 · 与 WP-53 CSV 风格对称）
- [ ] sidebar 顶部 3 按钮顺序：导入（square.and.arrow.down）/ 导出（square.and.arrow.up · 模板空时 disabled）/ 添加（+）
- [ ] 导出：
  - [ ] NSSavePanel · 标题"导出工作区模板" · 默认文件名 "工作区模板-yyyy-MM-dd.json"（Asia/Shanghai POSIX）
  - [ ] 内容：JSONEncoder iso8601 + sortedKeys + prettyPrinted（diff 友好 + 人读）
  - [ ] 包含完整 WorkspaceBook（templates + activeTemplateID · 含 windows / shortcut / sortIndex / timestamps）
  - [ ] 写入失败 → "操作失败"alert（含 error.localizedDescription）
- [ ] 导入：
  - [ ] NSOpenPanel · 标题"选择工作区模板 JSON 文件" · allowedContentTypes [.json]
  - [ ] 解析失败（非 JSON / Schema 不匹配）→ "操作失败"alert "导入失败：JSON 格式不识别 · ..."
  - [ ] 解析成功 → confirmationDialog "替换当前 N 个模板还是取消"（含两边数量对比）
  - [ ] 确认替换 → book = imported · 选中切到 imported.activeTemplateID 或 first
- [ ] 边界：导入空 book（templates 数 0）confirmationDialog 仍显示 · 替换后变成空状态（detail 显示"未选择模板"）
- [ ] 往返一致性：导出 → 导入同文件 → 数据完全一致（包括 shortcut / windows.frame / indicator IDs / sortIndex 顺序）

### Mac 切机替换（M5 · 多窗口实际渲染）
- [ ] StoreManager 注入 SQLiteWorkspaceBookStore · 替换 MockWorkspaceBook（持久化）
- [ ] 多窗口同时渲染（WP-44 + WP-40 联合 · CGRect 桥接 LayoutFrame）
- [ ] ChartScene / 多窗口管理器接收 .workspaceTemplateActivated → 关闭旧窗口 + 按 template.windows 重新打开 + frame 应用到 NSWindow.frame
- [ ] 全局键盘 NSEvent monitor → 解析 WorkspaceShortcut keyCode + modifierFlags → 切换激活模板（PeriodSwitcher 同样模式）

---

## v11.0 → v12.19 累积验收（2026-04-28 ~ 04-30 · 共 119 commit · L1-1/2/3/4 已通过）

### M5 持久化 7/7 全闭环（v11.0 5/7 → v12.0 7/7）

- [x] L1-1 启动写入 `~/Library/Application Support/FuturesTerminal/db/` 7 个 sqlite 文件（journal / alert_history / **alert_config** / watchlist / workspace / kline_cache / **analytics**）
- [ ] alerts 增删改 → 重启保留（SQLiteAlertConfigStore 聚合根模式 · v12.0 第 5 批 a-b）
- [ ] alerts 清空 [] → 重启保留为空（非 fallback Mock · 空数组合法语义）
- [ ] AnalyticsService 6/10 事件埋点（v12.0 第 5 批 c-e）：
  - [ ] app_launch（每次启动 +1 行）
  - [ ] chart_open（mode/instrument/period 切换 +1 行）
  - [ ] indicator_add（副图指标切换 +1 行）
  - [ ] replay_start（切回放模式 +1 行）
  - [ ] journal_entry_save（CSV 导入 +1 行）
  - [ ] alert_trigger（testTrigger 或 K 线假 Tick 触发 +1 行）

### WP-63 文华 .wh 公式批量导入 ✅ DoD（v12.0）

- [ ] `swift run MaiYuYanWhDemo` 第 20 个真数据 demo（Sina 真行情 RB0 60min 1023 根 · 20 公式编译 100% + 执行 100% · 12 经典指标 KDJ/MACD/RSI/CCI/WR/ROC/BIAS/PSY/ATR/OBV/DMA/SLOPE）
- [ ] WhImportError 错误整文件相对行号定位（标头行偏移 + 公式内行号）

### WP-64 文华自选文本导入 ✅ DoD（v12.0）

- [ ] WatchlistImporter parse 5 组（黑色 / 化工 / 农产品 / 有色 / 贵金属）50+ 合约无丢失（Linux 已验 · Mac UI 入口待 commit 5）
- [ ] merge 同名追加合约级去重 + 新名创建（addGroup）

### AlertEvaluator 真 e2e wiring（v12.0）

- [ ] 创建价格预警（rb2510 close > 3300）→ 实盘 K 线收尾时 close 假 Tick 自动触发 → history 自动 insert + UI observe 显示
- [ ] testTrigger 独立路径（不通过 evaluator）→ history insert + alert_trigger 埋点（test=true 标识）
- [ ] 重启后 history 保留（SQLiteAlertHistoryStore · P0-1 修后 testTrigger 也写库）

### 视觉迭代 13 项（v12.0 · Mac 实盘截图已确认全到位）

- [x] 第 1 项 主图 5×5 半透明白 0.08 横竖网格（KLineGridView · 与 KLineAxisView 5 等距标签对齐）
- [x] 第 2-4 项 十字光标 + OHLC 浮窗 + HUD MA/BOLL 彩色圆点染色 + HUD 调试信息淡化
- [x] 第 5-7 项 十字光标右价格 + 底时间黄色浮标 + 顶部当前价大字 22pt + 涨跌差 + 百分比 + 价格右轴最新 close 黄色高亮
- [x] 第 8-10 项 工具条 segmented（模式 / 副图）+ 主图副图分割线 1.5pt 增强 + 6 WindowGroup .preferredColorScheme(.dark)
- [x] 第 11-13 项 toolbar 深色 #15171C + SubChartView HUD 去 kind 名 + 6 WindowGroup .defaultSize（chart 1280×800 / watchlist 880×600 / review 1280×900 / alert 920×640 / journal 1100×720 / workspace 1100×720）

### 视觉 bug 修复（v12.0 · 已 Mac 启动验证 L1-1 / L1-4）

- [x] 回放未启动主图大绿块（MetalKLineRenderer.makeViewMatrix x 右边界 visible → viewport.visibleCount · 单根 bar 时 visible=1 占 70% 屏宽 → 修后 0.5%）
- [x] 默认拖拽无效（visibleCount 200→120 + cacheMaxBars 200→500 · pan 空间 0→380 · 文华惯例 500-1000）

### Mac 编译批量修复（v12.0 · Linux 跳 SwiftUI 未暴露的 9 类问题 · L1-1 启动验证编译正确）

- [x] AlertWindow Alert 命名歧义（typealias Alert = AlertCore.Alert · 必须 internal 否则违反"private 类型用于更宽访问级别声明"）
- [x] AlertHistoryEntry 3 处参数顺序修正（id / alertID / alertName / instrumentID / conditionSnapshot / triggeredAt / triggerPrice / message）
- [x] ChartScene compactMap 显式 -> KLine? 防 Swift 6 推断 ambiguous
- [x] 5 处 try? await service.record 加 _ = 消未用返回值 warning
- [x] KLine.openInterest Decimal 转换（Int → Decimal）
- [x] JournalWindow Decimal LocalizedStringKey deprecated 警告 → `.description` 显式 String
- [x] .gitignore 整目录忽略 .claude/（含 lock 文件）+ git rm --cached scheduled_tasks.lock
- [x] ReviewWindow 8 图自适应布局（adaptive(minimum: 260) + minHeight 替代固定 height · 修默认 1024 宽 4 列裁切）
- [x] swift run **MainApp**（不是 FuturesTerminalApp · executable 名 Package.swift line 105）

### 评估发现 P0 全修 + P1 部分（v12.0）

- [ ] P0-1 AlertHistory testTrigger 重启保留（appendHistoryEntry 调 store.append 修后 · v11.0 仅内存 insert）
- [ ] P0-2 K 线 append 多 Task 串行（klineSaveTask 链式 await · onDisappear 等最后一根落库 · 修高频 completedBar + maxBars 截断时丢中间根）
- [ ] P0-3 trades 空数组持久化（onChange 去 isEmpty guard · 用户清空 trades 重启保留空）
- [ ] P1-4 history 加载语义对齐 alerts（去 isEmpty guard · 空数组合法）

### v12.1 增量（2026-04-29 · 4669e32 / aa34fe5）

- [ ] **L1-5 Watchlist Mock bug 修**（4669e32）：⌘L 自选合约面板 → 双击任意合约（黑色 RB0 / 股指 IF0 / 贵金属 AU0 / 有色 CU0 · 4 组按板块分类）→ 主图自动切到该合约 + 加载真行情（不再被 alert 拦截 / 主图保持 RB0）
- [ ] **真 preSettle 接入**（aa34fe5）：顶部当前价大字号涨跌色按 Sina 实时昨结算（preSettle 而非 visible 周期首根）· 与文华行情显示口径一致 · Sina API 失败 fallback first.close
- [ ] 切回放模式 → preSettle 也清 nil（priceTopBar baseline 退回 first.close · 回放无前结算概念）

### v12.2 增量（2026-04-29 · e386a53 / 2dc8d6d · 月份合约盯盘解锁）

- [ ] **第 21 个真数据 demo SinaMonthlyContractDemo**（e386a53）：`swift run SinaMonthlyContractDemo` 验证 30 真网络请求结果（Mac 同 Linux · K 线端点全支持月份合约 · 实时报价仅大写 + 非 I 字母支持）
- [ ] **扩 supportedContracts 4→8**（2dc8d6d）：MarketDataPipeline.supportedContracts 加 4 active 月份合约（rb2609 / i2609 / au2606 / IF2605）
  - [ ] ChartScene 工具条合约 Picker 显示 8 选项（4 主连续 + 4 月份合约）
  - [ ] 主图切 rb2609（小写）→ K 线正常加载（Sina K 线端点支持小写）· 末根 date = 当日实时
  - [ ] 主图切 i2609（I 字母小写）→ K 线正常 · preSettle 拉失败 → priceTopBar 涨跌色 baseline fallback first.close（v12.1 实现）
  - [ ] 主图切 au2606（小写）→ K 线正常 · preSettle 失败 fallback OK
  - [ ] 主图切 IF2605（大写股指）→ K 线 + preSettle 全 OK · 涨跌色按真昨结算
- [ ] **WatchlistWindow Mock 改 2 组 8 合约**（2dc8d6d）：⌘L 自选合约面板
  - [ ] 显示 2 组：「主力月份」（rb2609/i2609/au2606/IF2605）+「主连续」（RB0/IF0/AU0/CU0）
  - [ ] 双击任意月份合约 → 主图自动切（K 线加载 · 不被 alert 拦截）
  - [ ] 双击 i2609 → 行情列表"最新价/涨跌幅"显示"—"（实时报价失败 fallback 文案 · 主图 K 线正常）
- [ ] **footerHint 文案更新**：底栏显示"双击合约打开主图 · 含主连续 + 活跃月份合约 · 实时报价对小写/I 字母合约部分降级（K 线正常）"
- [ ] **Mac 验收用例**：用户切 rb2609 → 主图加载今日 60min K 线 + 真实成交量 + 持仓量（K 线端点）→ priceTopBar fallback first.close（preSettle 失败）→ 视觉无明显异常

### v12.3 增量（2026-04-29 · 3b2cb7e / 待修复 commit · v12.2 月份合约实时报价完整解锁）

- [ ] **第 22 个真数据 demo SinaQuoteWorkaroundDemo**（3b2cb7e）：`swift run SinaQuoteWorkaroundDemo` 验证 W1 大小写转换 + W4 K 线伪实时 workaround
- [ ] **关键修正**：v12.2 demo 段 4 总结的"i 字母不支持"结论实为"小写需 uppercase"（demo 输出文字未改 · 通过 v12.3 修正叙事）
- [ ] **SinaMarketData.fetchQuotes URL 自动 uppercase**（W1 单行修复）：fetchQuote("rb2609") 内部 URL 用 "nf_RB2609" · 返回 SinaQuote.symbol="rb2609" 保留原大小写（调用方无感）
- [ ] **ChartScene fetchPreSettle 自动受益**：
  - [ ] 主图切 rb2609 → preSettle 拉到真昨结算 ~3162（v12.2 拉失败 fallback first.close · v12.3 真值）
  - [ ] 主图切 i2609 → preSettle 真值 ~783.50
  - [ ] 主图切 au2606 → preSettle 真值 ~1012.10
  - [ ] 主图切 IF2605 → preSettle 真值（金融期货昨收近似）
  - [ ] 顶部当前价大字号涨跌色按真昨结算（不再 fallback 周期首根）
- [ ] **Watchlist 行情列表对小写合约也拿到真行情**：⌘L 自选合约面板 → 主力月份组（rb2609/i2609/au2606/IF2605）
  - [ ] 行情列表"最新价"显示真 last（v12.2 显示"—" · v12.3 显示真值）
  - [ ] "涨跌幅"显示真涨跌幅（preSettle 真值的话 changePercent 准确）
- [ ] **已交割合约 I2509 仍 fallback first.close**（Sina 实时报价端点已下架 · K 线历史保留 · W4 兜底待 v12.4 实施）

### v12.4 增量（2026-04-29 · 待 commit · Watchlist 接真行情）

- [ ] **Watchlist 行情列表接 SinaMarketData 真行情**：⌘L 自选合约面板
  - [ ] 启动后 ~5s 内行情列表从 MockQuote 静态值切换到真值（最新价 / 涨跌幅 / 持仓量）
  - [ ] 主力月份组（rb2609/i2609/au2606/IF2605）显示当日真涨跌（W1 修复后小写合约也拉得到）
  - [ ] 主连续组（RB0/IF0/AU0/CU0）显示真涨跌
  - [ ] 涨跌幅红涨绿跌（前缀 "+" 红 / "-" 绿 · 兼容原文本判断）
  - [ ] 持仓量自动格式化：≥1M 显示 "1.83M" / ≥1K 显示 "5K" / 否则原数字
- [ ] **5s 周期刷新**：观察行情列表数字滚动 · 确认每 5s 更新一次（实盘交易时段）
- [ ] **离线 fallback**：断网 / Sina 不可达 → 行情列表保留上次真值 · 首次启动失败 fallback MockQuote 占位
- [ ] **窗口关闭清理**：关闭自选合约窗口 → quoteFetchTask cancel · 不泄漏（多次开关无累积 task）
- [ ] **新增合约自动接入**：用户「+ 添加合约」加 cu2606 → 5s 内 Watchlist 显示真行情（无需重启窗口）
- [ ] **WP-64 文华自选导入真闭环**：导入文华自选 .txt（含月份合约）→ Watchlist 显示真涨跌（不再 Mock）

### v12.5 增量（2026-04-29 · 待 commit · W4 兜底实施 · 已交割合约 + sina 抖动容错）

- [ ] **W4 兜底实施 SinaMarketData.fetchQuotesWithFallback**：实时端点失败合约自动走 K 线 5min 末根伪实时
- [ ] **WatchlistWindow startQuoteFetch 改用 fetchQuotesWithFallback**：⌘L 自选合约面板渐进 degradation
  - [ ] 加合约 I2509（已交割）→ Watchlist 显示真 last 816 + 真持仓量（v12.4 fallback Mock · v12.5 K 线兜底）
  - [ ] 涨跌幅仍显示 Mock 占位（W4 partial quote 缺 preSettle · changePctText guard 仍兜 Mock）
  - [ ] 加合约 abc（无效）→ K 线也失败 → quotes 字典无该 key → UI 走 Mock 全 fallback（合理）
- [ ] **Sina 实时端点抖动容错**：人为模拟 sina 不可达（断网 / 阻断 hq.sinajs.cn）→ 5s 周期 fetch 失败 → 走 K 线兜底（端点不同 stock.finance.sina.com.cn）→ active 合约 last + oi 仍真值
- [ ] **WatchlistImporter 真闭环增强**：导入文华自选含已交割合约（如某些合约表 .txt 含 I2505）→ Watchlist 显示真历史末值（不再纯 Mock）

### v12.6 增量（2026-04-30 · 待 commit · 多周期数据/UI 一致性修复）

- [ ] **第 23 个真数据 demo SinaKLineGranularityDemo**：`swift run SinaKLineGranularityDemo` 验证 RB0 + rb2609 × 5 type（1/5/15/30/60）全 ✅
- [ ] **修复隐性 bug**：ChartScene fetchHistoricalKLines 之前 minute1/15/30 默默 fallback 15min · v12.6 后走真 type
  - [ ] 主图切到 1min 周期 → K 线显示真 1min（约 1023 根 · 末 date 含分钟 32/33/34）· 之前是 15min 数据
  - [ ] 主图切到 15min 周期 → 真 15min（之前已经是 15min · 行为不变）
  - [ ] 主图切到 30min 周期 → 真 30min（约 1023 根 · 末 date :30/00 整点）· 之前是 15min 数据
- [ ] **Sina 端点全粒度 type 支持** SinaMarketData 加 fetchMinute1KLines + fetchMinute30KLines · Provider historicalMinute 扩 case 1/30
- [ ] 数据/UI 一致性：工具条显示"15min" → 实际拉的是 15min · 显示"1min" → 实际是 1min · 不再隐性 fallback

### v12.7~v12.19 增量（2026-04-30 · 13 commit · 用户一次性 Mac 批验回合）

#### v12.7~v12.13 hotfix 阶段（用户中途反馈触发）
- [ ] **多周期数据/UI 一致**（v12.7+v12.8）：切 1分/5分/15分/30分/60分/日 → K 线时间间隔与选中周期匹配
  - [ ] 切日 K → 真日 K（每根 1 天 · v12.8 修 UDS 加 historicalDaily 路径 · 之前 fallback 5000 根 1min Mock）
  - [ ] 切 1min/30min → 真间隔（v12.7 修 UDS 实盘路径 · v12.6 只修了回放路径）
- [ ] **cacheMaxBars 按周期动态**（v12.9）：1min 10000 / 5min 5000 / 15min 3000 / 30min 2000 / hour1 1500 / daily 1500
- [ ] **光标时间格式按周期动态**（v12.10+v12.11）：
  - [ ] 1分/5分/15分：`MM-dd HH:mm`（如 04-30 10:32）
  - [ ] 30分/60分：`yy-MM-dd HH:mm`（如 26-04-30 10:30）
  - [ ] 日：`yyyy-MM-dd`（如 2026-04-30）
- [ ] **回放控制条按钮蓝底白字反馈**（v12.12+v12.13）：
  - [ ] 4 按钮（停止/后退/播放暂停/前进）按下瞬间蓝底白字
  - [ ] 播放按钮 playing 状态持续蓝底白字 · 暂停后变灰
  - [ ] 速度档分段控件选中档蓝色高亮

#### v12.14~v12.19 功能补全阶段（一气呵成 · 用户最后一次性 Mac 验）
- [ ] **副图扩 4 选项**（v12.14）：工具条副图分段控件
  - [ ] 显示 4 个选项：MACD / KDJ / **RSI** / **成交量**
  - [ ] 切 RSI → 0~100 视野 + 70/50/30 参考线 · 单线 + HUD 染色（>70 红 / <30 绿 / 中区黄）
  - [ ] 切 成交量 → 涨红跌绿柱 + 底基线 + HUD 自动 K/M 格式
- [ ] **真 preClose 商品 vs 金融语义化**（v12.15）：行为等价 · 仅命名清晰（无可见验证项 · 看代码即可）
- [ ] **主力月动态计算**（v12.16）：合约 Picker 显示 8 选项
  - [ ] 4 主连续：RB0 / IF0 / AU0 / CU0
  - [ ] 4 active 月份合约：rb2609 / i2609 / au2606 / IF2605（DominantMonthCalculator 推算 · 半年自动续期）
  - [ ] 半年后（如 2026-10）应自动变 rb2701 等（验证日期推算正确）
- [ ] **WatchlistImporter UI 入口**（v12.17）：⌘L 自选合约面板 sidebar 顶部
  - [ ] 出现「下载箭头」导入按钮（hover 提示"导入文华自选 .txt"）
  - [ ] 点击 → NSOpenPanel 选 .txt 文件 → 弹 alert 预览（多少组多少合约）→ 确认导入
  - [ ] 导入后 book 自动持久化（重启保留）
- [ ] **WhImporter UI 入口**（v12.18）：主菜单「工具」→「导入文华公式（.wh）」⌘⇧I
  - [ ] 点击 → NSOpenPanel 选 .wh 文件 → NSAlert 显示编译报告（成功 N / 失败 N + 失败明细）
- [ ] **WP-44 周期快捷键 ⌘1-6**（v12.19）：K 线窗口聚焦时
  - [ ] ⌘1 → 切 1分 · ⌘2 → 5分 · ⌘3 → 15分 · ⌘4 → 30分 · ⌘5 → 60分 · ⌘6 → 日
  - [ ] 视图菜单显示快捷键说明文案

### Mac 验收 L1 进度表（v12.19 末）

- [x] L1-1 启 App + 默认窗口 1280×800 + 深色（含回放未启动大绿块 bug 修验证）
- [x] L1-2 鼠标 hover 主图 → 虚线十字 + OHLC 浮窗 + 右价格 + 底时间浮标
- [x] L1-3 工具条 4 Picker 切换响应（模式 segmented / 合约 menu / 周期 menu / 副图 segmented）
- [x] L1-4 拖拽 + 缩放主图 + 惯性滑行（含默认拖拽 bug 修验证）
- [ ] L1-5 自选合约 ⌘L · 双击合约联动主图（4669e32 修后待验）
- [ ] L1-6 复盘 ⌘R · 8 图自适应（v12.0 已修 adaptive · 默认 1024 宽下不裁切）
- [ ] L1-7 预警 ⌘B · 测试触发 → 历史 + 重启保留（P0-1 已修）+ 真 e2e（K 线假 Tick）
- [ ] L1-8 交易日志 ⌘J · CSV 导入 + 重启保留（P0-3 空数组持久化）
- [ ] L1-9 工作区模板 ⌘K · 模板编辑
- [ ] L1-10 埋点 SQLite 文件增长（AnalyticsService 6/10 事件 · analytics.sqlite 行数）
- [ ] L1-11 持久化重启场景（alerts 清空 / trades 清空 / history 清空 / K 线缓存连续无丢根）
- [ ] L1-12 Alert e2e（创建价格预警 → K 线 close 假 Tick 触发 → history 自动 insert + 重启保留）

---

## 待补（后续 commit 累积）

后续每个 commit 完成功能后追加到对应章节 · 切机前在此清单逐项验收。
