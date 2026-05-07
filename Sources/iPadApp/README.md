# iPadApp · Mac 切机配置与验收（WP-61 v15.25）

## 状态
- ✅ Linux: 整 target `#if canImport(SwiftUI) && os(iOS)` 隔离 · 编译过 · `swift run iPadApp` 输出 fallback 提示
- ⏳ Mac: 切机后按下方步骤配置 + iPad 模拟器联调

## 切机配置步骤

### 1. Xcode 打开项目
```bash
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1
open Package.swift   # 或 xed .
```

Xcode 打开后会看到 iPadApp executable target。

### 2. 选择 iPad 模拟器
- Xcode toolbar → scheme 选 iPadApp
- destination 选 iPad simulator（推荐 iPad Pro 13" / iPad 10th gen）
- Run（⌘R）→ 模拟器启动 iPadApp

### 3. CloudKit 配置（可选 · 不配也能跑）
若要联调跨端同步：

#### a. Container 创建
按 `Sources/SyncCore/CloudKit/README.md` 步骤创建 `iCloud.com.<yourorg>.FuturesTerminal` container。

#### b. iPadApp.entitlements
新增 `Sources/iPadApp/iPadApp.entitlements`（Xcode Target 自动建议）：
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.<yourorg>.FuturesTerminal</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

#### c. 启用真实 CloudKit backend
编辑 `Sources/iPadApp/SyncCoordinator_iOS.swift::makeDefault`：
```swift
#if canImport(CloudKit)
let container = CKContainer(identifier: containerID)
let backend = CloudKitSyncBackend(container: container, scope: .private)
return SyncCoordinator_iOS(backend: backend)
#endif
```

把占位 `MockSyncBackend()` 换成 `CloudKitSyncBackend(container:scope:)`。

### 4. iCloud 账号
模拟器 → Settings → 登录 iCloud 测试账号（或用真账号）

## 验收清单

### A. 应用壳（batch001-002）
- [ ] iPadApp 启动 · 不闪退
- [ ] 横屏：sidebar + detail 双栏（balanced）
- [ ] 竖屏：sidebar 自动隐藏 · 拖拽显示
- [ ] safe area 正确（圆角 / 刘海）

### B. 自选列表（batch003）
- [ ] 启动后 demoSeed 注入 3 分组 9 合约（黑色板块/贵金属/有色）
- [ ] 点击合约 → detail 切换
- [ ] long-press / swipe → 删除合约
- [ ] header ✏️ 按钮 → 重命名 sheet · medium detent
- [ ] sheet TextField 取消/保存 工作
- [ ] 删除 / 重命名后 InMemory 持久化（同会话 reload 不丢）

### C. K 线图表（batch004）
- [ ] 选合约后图表渲染（8 大合约任选）
- [ ] 蜡烛红涨绿跌（中国习惯）· 影线 + 实体
- [ ] 5×5 网格
- [ ] pinch zoom：放大 → visibleBarCount 减 · 缩小 → 增（20-200 范围 clamp）
- [ ] drag pan：左滑往后看 · 右滑往前看（offsetBars 推进 · 越界 clamp）
- [ ] 切合约图表数据更新（task id 触发）

### D. 多周期 + 指标（batch005）
- [ ] 顶部条 8 个周期 chip：1m / 5m / 15m / 30m / 1H / 4H / 日 / 周
- [ ] 选中态 accentColor 高亮 + semibold
- [ ] 横向 ScrollView 不需要 · 8 chip 应能挤进 iPad 横屏
- [ ] 指标 Menu：MA / EMA / BOLL toggle · 选中态 ✓ · 含数量 chip
- [ ] 切周期图表数据重新生成（不同 volatility）

### E. CloudKit 同步入口（batch006）
- [ ] sidebar toolbar gear icon 按钮 → SettingsSheet
- [ ] 默认 backend = MockSyncBackend（本机模拟 · 不联网）
- [ ] 立即同步按钮工作 · status 切换（idle → syncing → succeeded）
- [ ] **若启用真 CloudKit**：
  - [ ] 两台 Mac iPad simulator 同步 watchlist（先清掉对方的 demoSeed）
  - [ ] 删除分组后对端拉到 tombstone
  - [ ] 离线（飞行模式）累积修改后重连同步
  - [ ] 冲突场景日志记录（双方同时改同一分组）

### F. Settings sheet（batch007）
- [ ] gear icon 触发 sheet · presentationDetents medium/large
- [ ] CloudKit 同步 Section 显示 status icon + 文字
- [ ] 主题 Picker：跟随系统 / 浅色 / 深色 · @AppStorage 持久化（重启保留）
- [ ] 主题切换立即应用（preferredColorScheme）
- [ ] 冲突日志 Section（条件渲染）· 显示前 10 条
- [ ] 关于 Section：版本 / WP / Stage

### G. 行情 detail（batch008）
- [ ] 顶部条下方显示行情 panel
- [ ] 最新价 24pt monospaced 红涨绿跌
- [ ] 涨跌额 + 涨跌% 同步染色
- [ ] OHLC 2×2 Grid（高=红 / 低=绿）
- [ ] 成交量 + 持仓量

### H. 视觉细节（trader 触感）
- [ ] 触屏区域 ≥ 44×32（HIG）
- [ ] monospaced 字体所有数字（金额 / OHLC / 涨跌）
- [ ] 红涨绿跌全局一致（中国习惯）
- [ ] dark mode 切换不破布局
- [ ] iPad 12.9" + iPad 10.9" + iPad mini 三种 size class 适配

## 已知未做（Stage A iPad 范围外）

| 功能 | 替代/留给 |
|------|---------|
| 下单 | Stage B B01-B02 |
| 复盘 12 图 / 训练 / 预警 | Mac 端用 · iPad 不查看 |
| 工作区模板 | iPad 不切多窗口 · 单图表足够 |
| Apple Pencil 画线 | Stage B B06 |
| 外接屏 | Stage B B06 |
| Metal 真渲染 | iPad polish · 当前 SwiftUI Canvas 已够 trader 看盘 |
| 实时报价 | batch008+ 接 SinaSource / DataSource（当前 demoBars 假数据） |

## CloudKit container 共享（与 Mac 互通）

iPad 与 Mac 使用**同一个** container ID：
```
iCloud.com.<yourorg>.FuturesTerminal
```

数据天然互通：
- Mac 创建分组 → CloudKit → iPad 拉到
- iPad 改名 → CloudKit → Mac 拉到
- 同一 iCloud 账号下数据完全同步

## 故障排查

| 现象 | 原因 | 解决 |
|------|------|------|
| 启动黑屏 | iCloud 未登录 | Simulator → Settings → 登录 |
| sync 一直 syncing | container 未创建 / entitlements 漏配 | 按 `Sources/SyncCore/CloudKit/README.md` 检查 |
| sync 报 quota | 模拟器额度限制 | 真机或换账号 |
| 切合约图表不动 | task(id:) 未触发 | 检查 instrumentID 是否真的变了 |
| 主题切换不生效 | @AppStorage 拼写错 | 确认 key="ipad.theme" 一致 |

## 后续 polish（不阻塞 Stage A 上线）

- [ ] Metal 真渲染（10w K 60fps · 替代当前 Canvas）
- [ ] 实时 Tick 接入（SinaTickSource → 替换 demoBars）
- [ ] 主图指标真叠加（MA / EMA / BOLL）· 当前 toggle 仅状态记录
- [ ] CKSubscription 推送同步通知
- [ ] BGTaskScheduler 后台同步
- [ ] iPad 多窗口 stage（Stage Manager）
- [ ] Apple Pencil 画线 / 标注（Stage B B06）
