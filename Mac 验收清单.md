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

## 待补（后续 commit 累积）

后续每个 commit 完成功能后追加到对应章节 · 切机前在此清单逐项验收。
