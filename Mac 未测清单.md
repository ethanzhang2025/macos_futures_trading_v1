# Mac 未测清单

## 来源

用户在 v12.13 之后决定**不再 Mac 切机测试 · 一气呵成做完再批量验**。本文记录此后所有未在 Mac 端实际验证的功能 / 改动 · 切机时按此清单一次性验完。

## 总览

| 版本 | commit | 功能 | 状态 |
|------|--------|------|------|
| v12.7 | `170fe2b` | UDS 实盘 1/30min hotfix | ✅ 已 Mac 通过（用户复测"好了"） |
| v12.8 | `03267fc` | UDS daily 路径 hotfix | ✅ 已通过 |
| v12.9 | `cb47a10` | cacheMaxBars 按 period 动态 | ✅ 已通过 |
| v12.10 | `2aaebef` | 光标时间格式按 period | ✅ 已通过 |
| v12.11 | `7460974` | 时间格式折衷（30/60分加 yy） | ✅ 已通过 |
| v12.12 | `f19bbf3` | 播放暂停按钮 state 高亮 | ✅ 已通过（用户"好了"） |
| v12.13 | `a676f8c` | 回放控制条 4 按钮统一蓝底白字 | ✅ 已通过 |
| **v12.14** | `0e2c300` | 副图扩 RSI / 成交量 | ⚠️ **未测** |
| **v12.15** | `1afab6e` | priceBaseline 语义化 | ⚠️ **未测**（行为等价 · 仅命名） |
| **v12.16** | `ecbc6aa` | 主力月动态计算 | ⚠️ **未测**（Linux unit test 7 个全过 · Mac 未跑） |
| **v12.17** | `ef0e52f` | WatchlistImporter UI 入口 | ⚠️ **未测** |
| **v12.18** | `f9dd011` | WhImporter UI 入口 | ⚠️ **未测** |
| **v12.19** | `23b8ff4` | ⌘1-6 周期键盘快捷键 | ⚠️ **未测** |
| **v13.0** | `a8cc75c` | WP-42 画线工具完整激活 | ⚠️ **未测**（5-7 天大动作） |
| **v13.1** | `ed8a1c7` | 画线 polish（hit-test anchor/Delete/文字 NSAlert） | ⚠️ **未测** |
| **v13.2** | `5d7bb1a` | SQLiteDrawingStore（M5 持久化 7→8） | ⚠️ **未测**（Linux 单测 12 个全过 · Mac 未跑） |
| **v13.3** | `5ebea3b` | 双点画线 hover 实时预览 | ⚠️ **未测** |
| **v13.4** | `553c834` | hit-test 线段任意点击（不只 anchor） | ⚠️ **未测** |
| **v13.5** | `b9b6bc3` | 右键上下文菜单（删除/编辑/取消） | ⚠️ **未测** |
| **v13.6** | `5a8fd24` | 复制画线（⌘D）+ Inspector 浮窗 | ⚠️ **未测** |
| **v13.7** | `6538ea1` | 画线导出/导入 JSON（NSSavePanel + NSOpenPanel） | ⚠️ **未测** |
| **v13.8** | _本批_ | 画线颜色/线宽自定义（ColorPicker + Stepper + 右键批量改） | ⚠️ **未测** |
| **v13.9** | _本批_ | 多选画线（selectedIDs Set + ⇧ 加选 + 批量删/复制/改色/改宽） | ⚠️ **未测** |
| **v13.10** | _本批_ | 拖动 anchor（DragGesture · 改 startPoint/endPoint · 手势冲突已修） | ⚠️ **未测** |
| **v13.11** | _本批_ | 锁定画线（isLocked 字段 · 锁图标 anchor · 拖动/Delete 守卫 · 右键锁/解锁） | ⚠️ **未测** |
| **v13.12** | _本批_ | 文字字体大小（fontSize 字段 8~32pt · 工具栏条件 Stepper · 右键改字号 NSAlert） | ⚠️ **未测** |
| **v13.13** | _本批_ | 椭圆画线（DrawingType 第 7 类 · 工具栏 + 半透明填充 + 椭圆周 hit-test） | ⚠️ **未测** |
| **v13.14** | _本批_ | 测量工具（DrawingType 第 8 类 · 虚线 + 中点显示价格差/百分比/bar 数标签） | ⚠️ **未测** |
| **v13.15** | _本批_ | 透明度自定义（strokeOpacity 字段 · ColorPicker supportsOpacity true · alpha 通道） | ⚠️ **未测** |
| **v13.16** | _本批_ | 画线模板（DrawingTemplate · UserDefaults 持久化 · 工具栏 Menu · 跨合约复用） | ⚠️ **未测** |
| **v13.17** | _本批_ | Andrew's Pitchfork（DrawingType 第 9 类 · 3 点输入 · 中线 + 上下平行轨） | ⚠️ **未测** |
| **v13.18** | _本批_ | 画线 → 预警联动（水平线右键"创建预警…" → AlertCore + AlertWindow 自动同步） | ⚠️ **未测** |
| **v13.19** | _本批_ | 副图多选叠加（Set<SubIndicatorKind> · Menu Toggle · vertical stack 1~4 个） | ⚠️ **未测** |
| **v13.20** | _本批_ | 主图/副图分割条拖动调整副图高度（4pt + DragGesture · NSCursor.resizeUpDown.set） | ⚠️ **未测** |
| **v13.21** | _本批_ | 副图选择 + 高度持久化（UserDefaults 跨合约/周期共享 + 重启保留） | ⚠️ **未测** |
| **v13.22** | _本批_ | viewport 缩放级别按合约+周期记忆（1s 节流 · UserDefaults JSON · clamp 防越界） | ⚠️ **未测** |
| **v13.23** | _本批_ | viewport 键盘快捷键（⌘=放大 / ⌘-缩小 / ⌘0 重置 / ←/→ pan 5/25 根） | ⚠️ **未测** |
| **v13.24** | _本批_ | K 线主图右键扩展（无选中时显示重置/放大/缩小/复制可见区 CSV） | ⚠️ **未测** |
| **v13.25** | _本批_ | 主图截图导出 PNG（ImageRenderer 1280x720 Retina 2x · NSSavePanel） | ⚠️ **未测** |
| **v13.26** | _本批_ | 文字标注加粗/斜体（isBold/isItalic 字段 + 右键 toggle · 兼容老 JSON） | ⚠️ **未测** |

---

## v12.14 副图扩 RSI / 成交量

- [ ] 工具栏副图分段控件显示 4 选项：MACD / KDJ / **RSI** / **成交量**
- [ ] 切 **RSI** → 0~100 视野 + 70/50/30 参考线 + 单线（黄色）
  - [ ] HUD 染色：值 ≥70 红 / ≤30 绿 / 中区黄
- [ ] 切 **成交量** → 涨红跌绿柱 + 底基线 + 顶 visible max
  - [ ] HUD 自动 K/M 格式（≥1M 用 M / ≥1K 用 K）
  - [ ] HUD 颜色按当前 K 线 close >= open 涨红 / 跌绿

## v12.15 priceBaseline 语义化（无可见 UI 验收 · 仅代码层）

- [ ] 切金融期货 IF2605 → 顶部当前价 baseline 用 quote.priceBaseline（实际 = preSettlement = 昨收近似）
- [ ] 行为应与 v12.14 等价 · 不破坏顶部价格涨跌色

## v12.16 主力月动态计算

- [ ] 合约下拉显示 8 选项（4 主连续 + 4 active 月份合约）
- [ ] 当前 2026-04-30 推算 active 月份：rb2609 / i2609 / au2606 / IF2605
- [ ] 半年后（2026-10）应自动变 rb2701 等（验证日期推算正确）
- [ ] 切到 rb2609 / i2609 / au2606 / IF2605 → K 线正常加载（v12.6 K 线端点 / v12.3 W1 实时报价修复后真值）

## v12.17 WatchlistImporter UI 入口

- [ ] ⌘L 自选合约面板 sidebar 顶部出现「下载箭头」按钮（square.and.arrow.down 图标）
- [ ] hover 显示「导入文华自选（.txt）」tooltip
- [ ] 点击 → NSOpenPanel 选 .txt → alert 弹预览（多少组多少合约 + 各组明细）→ 确认导入
- [ ] 导入后 book 自动持久化（重启保留）
- [ ] merge 行为：同名分组追加去重 / 新名分组创建

## v12.18 WhImporter UI 入口

- [ ] 主菜单「工具」→「导入文华公式（.wh）」⌘⇧I
- [ ] 点击 → NSOpenPanel 选 .wh 文件 → NSAlert 显示编译报告
  - [ ] 标题"导入文华公式"
  - [ ] 内容：从 X 导入 N 个公式 · 成功 N · 失败 N · 失败明细前 10 条
  - [ ] alertStyle：全成功 informational / 部分失败 warning / 异常 critical

## v12.19 ⌘1-6 周期键盘快捷键

- [ ] K 线窗口聚焦时：
  - [ ] ⌘1 → 切 1分
  - [ ] ⌘2 → 切 5分
  - [ ] ⌘3 → 切 15分
  - [ ] ⌘4 → 切 30分
  - [ ] ⌘5 → 切 60分
  - [ ] ⌘6 → 切 日
- [ ] 视图菜单显示快捷键说明

## v13.0 WP-42 画线工具完整 UI 激活（最大未测项）

### 工具栏画线工具组（8 按钮）
- [ ] 副图分段控件之后出现一字排列 8 按钮：浏览（cursorarrow）/ 趋势线 / 水平线 / 矩形 / 平行通道 / 斐波那契 / 文字 / trash 清空
- [ ] hover 各按钮显示中文 Help tooltip
- [ ] 选某工具 → 该按钮蓝色背景高亮（accentColor 0.3 opacity）
- [ ] 完成画线后自动回浏览模式（按钮高亮消失）

### 6 种画线类型
- [ ] **趋势线**（黄）：选工具 → 主图点击 2 次（第 1 点 hold 不显示 · 第 2 点完成显示线段）
- [ ] **水平线**（蓝）：1 次点击 → 立即显示横跨水平线 + 右侧蓝色价格标签
- [ ] **矩形**（紫）：2 次点击对角 → 显示边框 + 半透明紫色填充
- [ ] **平行通道**（红）：2 次点击主轴 → 显示主+副双线（默认偏移 = 价格区间 5%）
- [ ] **斐波那契回调**（橙）：2 次点击 → 显示 7 档水平线 + 比例标签（0.0% ... 100.0%）
- [ ] **文字标注**（白）：1 次点击 → v13.1 弹 NSAlert 输入文字 · 确定后显示

### 清空所有
- [ ] trash 按钮 → 当前 (instrumentID, period) 所有画线删 · 持久化同步删

### 持久化（按 instrumentID + period 隔离）
- [ ] 在 RB0 15分上画一条趋势线 → ⌘Q 关 App → 重启 → 主图仍显示该趋势线
- [ ] 切 RB0 60分 → 看不到 RB0 15分的画线（独立）
- [ ] 切 IF0 15分 → 看不到 RB0 15分的画线（独立）
- [ ] 切回 RB0 15分 → 趋势线还在

### 画线锚定数据空间
- [ ] 拖拽平移主图 → 画线跟随平移（数据走 · 不固定屏幕位置）
- [ ] 缩放主图 → 画线随之缩放
- [ ] 切周期 → 画线被独立隔离（不会错乱）

## v13.1 画线 polish

### hit-test 选中
- [ ] 浏览模式（无激活工具）+ drawings 非空 → 点击主图触发 hit-test
- [ ] 点击 startPoint / endPoint anchor ±15 像素阈值内 → 该画线 selected
- [ ] 选中后 anchor 显示小圆圈高亮 · 线宽 2.5pt（默认 1.5pt）

### Delete 键删除
- [ ] 选中画线后按 Delete 键 → 该画线删除 + 持久化同步

### 文字 NSAlert 输入
- [ ] 选文字工具 → 单击主图 → 弹 NSAlert
  - [ ] 标题"文字标注"
  - [ ] 描述"输入要在主图标注的文字："
  - [ ] 默认值"标注"
  - [ ] 确定 → 添加文字画线 · 取消 → 不画

---

## v13.0~v13.6 累积验收章节（已写入 Mac 验收清单.md）

### v13.1 hit-test anchor + Delete + 文字 NSAlert
- 浏览模式点击 anchor ±15 像素 selected · Delete 键删除 · 文字工具单击弹 NSAlert 输入

### v13.2 SQLiteDrawingStore 持久化升级
- M5 持久化 7→8 store · `drawings.sqlite` · 复合主键 instrument_id+period · UPSERT JSON
- Linux 单测 12 个全过

### v13.3 双点画线 hover 实时预览
- onContinuousHover 跟踪 + 虚线半透明跟随第二点 · 4 双点类型支持

### v13.4 hit-test 线段任意点击
- 阈值 8 像素 · 6 类公式（线段距离 / 水平线 / 矩形 4 边 / 通道双轴 / fib 各档 / text 位置）
- pointToSegmentDistance 经典投影夹钳

### v13.5 右键上下文菜单
- 选中画线右键 → 删除（destructive 红）/ 编辑文字（仅 .text）/ 取消选中
- editTextDrawing 弹 NSAlert 改文字

### v13.6 复制画线 + Inspector 浮窗
- ⌘D + 右键"复制画线" · 偏移 +20 bar / 价格区间 5% · 自动选中新
- bottomTrailing Inspector 浮窗：类型中文 / 起终点 / 文字 / 通道偏移 / 操作提示 / 关闭按钮

### v13.7 画线导出/导入 JSON
- 工具栏 square.and.arrow.up / down 两按钮 · NSSavePanel 默认文件名 drawings_合约_周期_yyyy-MM-dd.json · prettyPrinted
- NSOpenPanel 导入 · alert 3 项（覆盖/追加/取消）· 解析失败 critical alert

### v13.8 画线颜色 / 线宽自定义
- [ ] 工具栏画线工具组之间显示 **ColorPicker**（28 pt 宽 · 系统色板 · 默认黄）+ **Stepper 0.5~5.0 步进 0.5**（默认 1.5）
- [ ] 选好色 + 线宽 → 新建画线（任一 6 类）渲染时应用自定义色 + 线宽
- [ ] 持久化：drawings.sqlite JSON 含 strokeColorHex（6 位 RGB hex）+ strokeWidth（Double）· 重启保留
- [ ] 选中画线 → 右键 → "应用当前颜色（n 个）" / "应用当前线宽 X.X pt（n 个）" / "恢复默认颜色/线宽（n 个）"
- [ ] Inspector 浮窗（单选时）显示色（hex 或"默认"）+ 宽（X.X）
- [ ] 老 JSON（v13.7-）导入 → 字段缺失时正常解码（strokeColorHex/Width = nil 用默认）

### v13.9 多选画线（⇧ 加选）
- [ ] 单击画线 = 单选（selectedDrawingIDs = [id]）
- [ ] **⇧ + 单击**：toggle 加选（已选 → 取消选 · 未选 → 加入选）
- [ ] 多选时全部 anchor 高亮 + Inspector 浮窗显示"已选 N 个画线"
- [ ] **Delete** 键 → 批量删除全部 selected
- [ ] **⌘D** → 批量复制全部 selected · 自动选中新副本
- [ ] 右键菜单"删除选中画线（N 个）" / "复制画线（⌘D · N 个）" / "应用当前颜色（N 个）" / "应用当前线宽（N 个）" / "恢复默认（N 个）"
- [ ] 编辑文字仅在 N=1 且类型 .text 时显示

### v13.10 拖动 anchor
- [ ] 选中画线后（anchor 显示高亮圆点）· 鼠标按住 anchor ±15 像素 + 拖动 ≥4 像素 → 进入拖动模式
- [ ] 拖动期间 startPoint / endPoint 实时更新（rect/channel/fib 形状跟着变）
- [ ] 拖动期间**主图 panGesture 不应跟着平移**（anchorDragTarget 命中时 panGesture onChanged 立即 return + 取消主图惯性滑行）
- [ ] 释放鼠标 → drawings 自动 save 到 SQLite
- [ ] 拖动距离 < 4 像素 → 视为单击（不触发拖动 · 走选中 / 多选逻辑）

### v13.11 锁定画线
- [ ] 选中画线 → 右键 → "锁定画线（n 个）" / 全锁时显示 "解锁画线（n 个）" / 混合时显示两选项
- [ ] 锁定后 anchor **以 SF Symbol lock.fill 图标代替圆点**显示（视觉一眼区分锁定）
- [ ] 锁定后**拖 anchor 不响应**（findAnchorAt 跳过 locked 画线）
- [ ] 锁定后**Delete 键不删**（filter !$0.locked · 多选时只删未锁的）
- [ ] 锁定后右键菜单"删除/编辑文字/编辑字号/应用色/应用线宽/恢复默认"全部 .disabled
- [ ] **⌘D 复制锁定画线副本不继承锁**（让用户能立即调整副本）
- [ ] Inspector 浮窗（单选时）显示 lock.fill 图标 + "已锁定" + 操作提示改"右键解锁后可拖动/删除"
- [ ] 老 JSON（无 isLocked 字段）正常解码 → locked = false

### v13.12 文字字体大小
- [ ] 工具栏选 .text 工具时 · 工具栏 Stepper "字号 12pt" 显示（默认 12 · 范围 8~32 步进 1）
- [ ] 选其他工具时 Stepper 隐藏（节省工具栏空间）
- [ ] 新建文字 → 应用工具栏当前字号（Drawing.fontSize 写入）
- [ ] 选中 .text 类型 + n=1 + 未锁 → 右键 → "修改字号…"项可见 → 弹 NSAlert 输入 8~32 数字（越界 clamp）
- [ ] DrawingsOverlayView drawText 用 d.fontSize ?? 12 渲染
- [ ] 老 JSON（无 fontSize 字段）正常解码 → 用 12 默认

### v13.13 椭圆画线（DrawingType 第 7 类）
- [ ] 工具栏画线工具组多 1 按钮（SF Symbol "circle"）介于 fibonacci 和 ruler 之间
- [ ] 选椭圆 → 双点对角 → 渲染**青色椭圆** + 半透明填充
- [ ] hover 第二点实时虚线椭圆预览
- [ ] hit-test 点椭圆周 ±8 像素能选中（公式：归一化半径距离 × min(a, b)）
- [ ] Inspector 显示"椭圆"中文标签
- [ ] 持久化 SQLite + JSON 导出/导入兼容

### v13.14 测量工具（DrawingType 第 8 类）
- [ ] 工具栏多 1 按钮（SF Symbol "ruler"）介于 ellipse 和 text 之间
- [ ] 选测量 → 双点 → 渲染**金色虚线** + 中点标签 "+/-X.XX (+/-X.XX%) · N bar"
  - 价格差（end.price - start.price）含正负号
  - 百分比差（priceDiff / startPrice * 100）
  - bar 数（end.barIndex - start.barIndex）
- [ ] hover 第二点实时虚线 + 标签预览
- [ ] hit-test 同 trendLine（点到线段 ±8 像素）
- [ ] Inspector 显示"测量工具"
- [ ] 持久化兼容

### v13.15 透明度自定义
- [ ] 工具栏 ColorPicker 改 supportsOpacity: true · 弹色板时**显示 alpha 滑块**
- [ ] 选半透明色 → 新建画线渲染**透明度生效**（描边 + 半透明填充共同应用）
- [ ] 右键菜单"应用当前颜色"同时应用 alpha 通道（不只 RGB）
- [ ] 右键菜单"恢复默认颜色/线宽"同时重置 strokeOpacity 为 nil
- [ ] Inspector 显示"透：XX%"（仅当 strokeOpacity < 1.0 时显示）
- [ ] 老 JSON（无 strokeOpacity 字段）正常解码 → 用 1.0 默认

### v13.16 画线模板（保存常用 / 跨合约复用）
- [ ] 工具栏多 1 按钮（SF Symbol "star"）位于颜色/线宽之后 · 导出/导入之前
- [ ] 点星号弹下拉 Menu：
  - 已存模板列表（每项格式"名称 · 类型"）· 点击立即插入到当前合约
  - 分隔线
  - "保存选中画线为模板…"项（仅 selected 1 个 + 未锁时显示）
  - "删除全部模板（N 个）"项（destructive 红色 · 含 alert 确认）
- [ ] 保存模板 NSAlert 输入名称（默认值"类型 + 当前时间"）
- [ ] 应用模板：锚点重定位到最近 30 根 bar 区间（baseBar = bars.count - 30）· 价格保留模板原值 · 用户后续可拖到合适位置
- [ ] 应用模板：drawing 用新 UUID + 不继承 isLocked
- [ ] 持久化 UserDefaults JSON（key drawingTemplates.v1 · 全局共享 · 不按合约/周期隔离）
- [ ] 重启 App 模板列表保留

### v13.19 副图多选叠加（vertical stack 1~4 副图）
- [ ] 工具栏副图选择器从 Picker(.segmented) 改为 Menu 弹下拉（默认显示当前选中数量"副图 N"或单选时显示 shortName）
- [ ] Menu 内 4 个 Toggle（MACD/KDJ/RSI/成交量）· checkmark.circle.fill / circle 切换
- [ ] 至少保留 1 个不允许全部取消（防 UI 空白 · 点最后 1 个不响应）
- [ ] 选 2 个 → 副图区显示 2 个 vertical stack · 之间 1pt 分割线
- [ ] 选 4 个 → 副图区显示 4 个 vertical stack · 总高度 = subChartTotalHeight
- [ ] 每个副图 = subChartTotalHeight / count（v13.20 用户可拖调）
- [ ] 切合约 / 重启 → selectedSubIndicators 默认 [.macd]（不持久化 · v1 设计）

### v13.20 主图/副图分割条拖动
- [ ] 主图 ↔ 副图之间 4pt 高度分割条（Color.white.opacity(0.18) · 比 v13.19 1pt 更醒目）
- [ ] 鼠标 hover 分割条 → cursor 变 resizeUpDown 双向箭头
- [ ] 鼠标按住 + 拖动：向上拖 = 副图变高 / 向下拖 = 副图变矮
- [ ] 高度范围 80~480 pt（min/maxHeight clamp）
- [ ] 释放鼠标 → 高度保持
- [ ] 不持久化 · 切合约/重启回默认 160（v1 设计 · backlog 可加 UserDefaults）
- [ ] 多副图（v13.19）时 perSubHeight 自动 = total / count

### v13.18 画线 → 预警联动（WP-42 + WP-52 集成）
- [ ] 选中水平线画线 → 右键 → "为此画线创建预警…"项可见（仅 .horizontalLine + n=1 + 未锁时）
- [ ] 弹 NSAlert 输入预警名称（默认"合约 触及 价格"）
- [ ] 创建后弹"预警已创建"提示
- [ ] 打开「预警」窗口（CommandMenu / ⌘2 等）→ 列表里出现新预警
- [ ] 预警 condition = horizontalLineTouched(drawingID, price) 自动关联画线 ID
- [ ] AlertWindow.onChange(of: alerts) 自动 save 到 SQLiteAlertConfigStore + sync evaluator
- [ ] NotificationCenter 模式：ChartScene post .alertAddedFromChart · AlertWindow .onReceive append
- [ ] 防重复：alerts.contains 检查 ID 跳过重复添加
- [ ] 关闭/重启 App → 预警仍存在（持久化生效）

### v13.17 Andrew's Pitchfork（DrawingType 第 9 类 · 3 点输入）
- [ ] 工具栏多 1 按钮（SF Symbol "tuningfork"）介于 ruler 和 text 之间
- [ ] 选 Pitchfork → 点击 3 次（A 中线起点 → B 上轨锚 → C 下轨锚）→ 完成
- [ ] phase 1（A 已落 · B 未落）hover 不预览（只看到 A 的 anchor 点）
- [ ] phase 2（A + B 已落 · C 未落）hover 实时预览**完整 3 线**（虚线半透明跟随）
- [ ] 完成后渲染**草绿色** 3 线：中线粗 + 上下轨次粗 + BC 连接虚线提示
- [ ] 中线方向 = A → midpoint(B, C)
- [ ] 上轨/下轨延伸到屏幕边界（dx/dy 双方向取 min t · 至少 1×长度不内缩）
- [ ] hit-test 与渲染范围对齐（同一个 t · 用户能点中可见延伸部分）
- [ ] anchor 显示：startPoint / endPoint / extraPoints[0] 三个 anchor 都画
- [ ] 拖动 anchor v1 仅支持 startPoint / endPoint（C 暂不支持拖 · backlog v13.17+）
- [ ] 持久化 SQLite + 导出/导入 JSON 兼容
- [ ] 切工具 / 清空 / 完成 / 重载合约 → 全部正确清理 pendingExtraPoints
- [ ] code-simplifier 修了 3 真 bug：trash 漏清 pendingExtraPoints / 渲染 t 只看 dx 单向 / hit-test 与渲染范围不对齐

---

## 后续 backlog（v13.17+ 未做）

- ❌ Pitchfork extraPoints anchor 拖动支持（findAnchorAt 扩展）
- ❌ 多边形画线（任意 N 点闭合 · 需 Enter/双击/Esc 完成机制）
- ❌ 画线分组（group 多条画线一起拖动）

---

## 切机批验启动命令

```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
git pull
swift build
swift run MainApp
```

发现问题贴回 · 按本清单从上到下验完。
