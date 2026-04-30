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

---

## 后续 backlog（v13.10+ 未做）

- ❌ 锁定画线（lock 后不可拖 / 不可删 · 适合关键支撑/阻力位）
- ❌ 文字字体大小 / 透明度自定义
- ❌ 画线模板（保存常用 → 一键插入）

---

## 切机批验启动命令

```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
git pull
swift build
swift run MainApp
```

发现问题贴回 · 按本清单从上到下验完。
