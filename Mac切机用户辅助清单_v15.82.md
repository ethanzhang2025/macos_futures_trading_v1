# Mac 切机用户辅助验收清单 · v15.82

**已经被 mac_acceptance.sh 自动覆盖（不用手动）**：
- ✅ 编译能过（swift build）
- ✅ 数据契约层（swift test 2338/380 + 73 XCTest 全绿）
- ✅ 22 窗口能打开 + 视觉无错乱（自动截图回 Linux 由 Claude 分析）
- ✅ 系统集成基本无问题（app 启动 + 快捷键响应）

**本清单只列必须用户实际操作才能验的项**。每项右侧标注预估时间。

走完后只需告诉 Linux 端：「Mac 验收完成 · 走完了第 X / Y 项」即可。

---

## 🔴 P0 · 高优先（必走 · 共 ~10 分钟）

### 1. 主图基础（v12.14 - v15.17 · 2 分钟）
- [ ] ⌘N 打开主图 · 默认 RB0 / 15 分 K 线渲染正确
- [ ] ⌘1-6 切 1m/5m/15m/30m/1h/日 · 各正常
- [ ] 副图切 MACD / KDJ / RSI / 成交量 · 渲染正确
- [ ] **副图多选**（v13.19）：Menu 勾 2-4 类 · vertical stack 显示
- [ ] **trackpad 双指缩放**（v15.16）+ 拖拽平移
- [ ] **⌘= / ⌘- / ⌘0**（v13.23）放大 / 缩小 / 重置

### 2. 画线工具（v13.0 - v13.35 · 3 分钟）
- [ ] 工具栏画线工具组 9+ 按钮（趋势线 / 水平线 / 矩形 / 通道 / 斐波 / 椭圆 / 测量 / 文字 / Pitchfork / 多边形 / 清空）
- [ ] **趋势线**：选工具 → 主图点 2 次 → 黄线显示
- [ ] **水平线**：1 次点击 → 横线 + 价格标签
- [ ] **斐波那契**：双点 → 7 档比例
- [ ] 选中画线 → Delete 删 / ⌘D 复制 / 右键菜单
- [ ] **拖动 anchor**（v13.10）：选中后按住 anchor 拖
- [ ] 关 app 重开 → 画线还在（持久化）
- [ ] 切合约（RB0 ↔ IF0）→ 画线独立隔离

### 3. 主题切换（v15.8/9/10 · 1 分钟）
- [ ] ⌘⇧D 切深色 ↔ 浅色 · 整窗瞬间重绘 · 无残留
- [ ] 切完后所有窗口（主图 / 副图 / HUD / Axis / Crosshair / 6 辅助窗）跟主题
- [ ] 关 app 重开 · 主题保留

### 4. SimNow 模拟交易（v15.4 - v15.6 · 3 分钟）
- [ ] ⌘T 打开交易面板 · 4 Tab（账户 / 下单 / 委托/成交 / 持仓）
- [ ] 下单 RB0 多 1 手 · 提交 → 委托即时入列
- [ ] 切到持仓 Tab → 看持仓
- [ ] 切到账户 Tab → 资金曲线渲染
- [ ] **导出 CSV** → NSSavePanel → 保存 → Excel 打开看中文
- [ ] 关 app 重开 → 持仓 + 历史成交保留

### 5. 异常监控 ⌘⌥A（v15.54 - v15.82 · 1 分钟）
- [ ] ⌘⌥A 6 视图 picker 切换：列表 / 类型 / 板块 / 30d 频次 / 周对比 / **组合异常**
- [ ] 组合异常视图：5/4/3 类计数 + minKinds Stepper + 排序 Picker · 行末 30d sparkline
- [ ] 搜索框（v15.79）：输 "RB" / "螺纹" → 实时过滤
- [ ] 导出 CSV（list 或 combo 视图）

### 6. 价差套利 ⌘⌥W + 自定义对（v15.55 - v15.75 · 1 分钟）
- [ ] ⌘⌥W 26 对扫描 · z 阈值 / 方向过滤
- [ ] 行尾 sparkline + ±2σ 上下轨
- [ ] **+ 自定义对** sheet：选 leg1=RB0 / leg2=CU0 / 比率 1/-3 → 保存
- [ ] 看到自定义对加入扫描列表
- [ ] 已加列表 Menu → 移除

---

## 🟡 P1 · 中优先（推荐走 · 共 ~5 分钟）

### 7. 跨窗口 combo 视觉统一（v15.76 - v15.82）
- [ ] ⌘⌥H 热力图：combo 品种角标 + 边框（5/4/3 类色）
- [ ] ⌘⌥B 板块 / ⌘⌥N 资金 / ⌘L 自选 / ⌘⌥P 持仓：行末 ✨N/5 徽章

### 8. HUD 自定义字段（v15.14 + v15.62 + v15.73）
- [ ] 工具栏 rectangle.dashed → HUDFieldsSheet
- [ ] 11 字段 Toggle（v15.73 加 .comboAnomaly）+ icon + sample preview
- [ ] 开 .sectorInfo → 主图角落显"板块 黑色系 · 均 +0.45% · 偏多 36%"
- [ ] 开 .comboAnomaly → 命中合约显"异常 N/5 · 价·持·资·背 · combo 72" + "Top 1 / 全市场 N combo"

### 9. 预警 ⌘B（v15.1 - v15.69）
- [ ] ⌘B list / history 双 Tab
- [ ] 加预警：condition picker 8 类（含 v15.12 持仓量异常）
- [ ] 条件类型过滤 segmented（v15.69）：全部 / 价格类 / 价差类 / 指标类 / 异动
- [ ] spread alert 行渲染（v15.63）：显图标 + 价差对名（"螺纹热卷"）
- [ ] history 含 spread row（v15.66）

### 10. 文华导入（v12.17 + v12.18）
- [ ] ⌘L 自选面板 → sidebar 顶部下载箭头 → 选 .txt → 弹预览 → 导入
- [ ] 主菜单 工具 → 导入文华公式（⌘⇧I）→ 选 .wh → NSAlert 报告

### 11. 多窗口 / 工作区
- [ ] ⌘N 起多个主图（4-8 个）· 各跑不同合约不互扰
- [ ] ⌘K 工作区模板：保存当前布局 → 重启后还原
- [ ] 复盘 ⌘R 8 图卡片渲染

---

## 🟢 P2 · 低优先（M6 上架前再做也行 · 各 ~10 分钟）

### 12. CloudKit 容器配置（v15.24）
**当前 Mac 验收会跳过**（需 Apple Developer 账号 + Container 创建）
- [ ] Apple Developer Portal 新建 `iCloud.com.<yourorg>.FuturesTerminal`
- [ ] MainApp.entitlements 加 iCloud + CloudKit + container ID
- [ ] CloudKit Dashboard schema deploy → Production
- [ ] 两台 Mac 同步 watchlist 测试
- [ ] 离线 + 重连 push

### 13. iPad simulator 验收（v15.25）
**当前 Mac 验收会跳过**（需 Xcode + iPad simulator）
- [ ] Xcode 起 iPad simulator → Run iPadApp scheme
- [ ] 横屏 / 竖屏 NavigationSplitView 切换
- [ ] 自选列表 / K 线图表 / 周期 chip / 指标 Menu
- [ ] Settings sheet（主题 + Sync 状态）

---

## ⚠️ 已知风险点（看到这些不用恐慌）

- **CalendarSpread 测试 flaky**（hash seed 跨进程随机 · 重跑通过）
- **mockBars 时间不对齐导致 customPair scanAll 偶尔不触发**（已用 evaluate 直接测验证 · 不影响真行情）
- **Sina API 抖动时 K 线降级 mock**（v12.4 已加 fallback · 看不到行情时检查网络）

---

## 🚨 如果遇到问题

走清单时如果看到以下情况立即记录 + 回报：
1. **闪退**：app crash → 找 ~/Library/Logs/DiagnosticReports/MainApp_* · 截图回 Linux
2. **快捷键无响应**：可能 macOS 系统占用 · 不算 bug · 跳过
3. **截图缺失某窗口**：脚本里某快捷键没触发 · 用户记录窗口名 · 我会查
4. **画线/SimNow/导入崩溃**：必报 · 这些是 P0 闭环

---

## 完成后告诉 Linux 端

只需一句：「Mac 验收完成 · P0 N/6 · P1 M/5 · 闪退 X 次 · 看图分析」

我就会从 ~/debug_img/mac_acceptance_v15.82/ 读取并分析。
