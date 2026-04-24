# macOS 运行指南

> 按照以下步骤，在Mac上编译运行期货交易终端，看到实时行情界面。

## 前提条件

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0 或更高版本（从App Store免费安装）
- 网络连接（获取新浪行情数据）

## 步骤

### 第1步：安装Xcode

如果还没装Xcode：

```bash
# 方法一：App Store搜索"Xcode"，点击安装（约7GB，耐心等待）

# 方法二：命令行安装Xcode Command Line Tools（仅编译用，没有IDE界面）
xcode-select --install
```

> 推荐用App Store装完整Xcode，因为后续开发需要用Xcode的IDE

### 第2步：验证Xcode安装

打开终端（Terminal.app），执行：

```bash
# 确认Xcode版本
xcodebuild -version
# 期望输出类似：Xcode 15.x 或 16.x

# 确认Swift版本
swift --version
# 期望输出类似：Swift version 5.10 或 6.0+
```

### 第3步：克隆代码

```bash
# 选择一个你想放代码的目录，比如桌面或者home目录
cd ~/Desktop

# 克隆仓库
git clone https://github.com/ethanzhang2025/macos_futures_trading.git

# 进入项目目录
cd macos_futures_trading
```

### 第4步：验证核心模块编译

```bash
# 编译核心模块（不含UI，验证代码完整性）
swift build

# 期望输出最后一行：
# Build complete!

# 运行测试（可选，验证全部逻辑正确）
swift test

# 期望输出最后一行：
# Test run with 94 tests passed
```

> 如果这一步失败，检查Xcode是否正确安装。

### 第5步：用Xcode打开App

```bash
# 进入App目录
cd App

# 用Xcode打开Package.swift
open Package.swift
```

执行 `open Package.swift` 后，Xcode会自动启动并打开项目。

### 第6步：Xcode中的操作

Xcode打开后，需要等待它完成包解析（第一次可能需要1-2分钟）：

```
1. 等待左下角进度条完成（显示"Resolving Package Graph"或"Fetching..."）

2. 左上角的Scheme选择器（播放按钮右边的下拉框），确认选择的是：
   FuturesTraderApp

3. Scheme右边的设备选择器，确认选择的是：
   My Mac

4. 点击左上角的 ▶（播放按钮），或者按快捷键 Cmd + R

5. 等待编译完成（第一次约30秒-1分钟）

6. 编译成功后，App窗口会自动弹出
```

### 第7步：看到界面

App启动后，你会看到一个三栏布局的窗口：

```
┌──────────────┬────────────────────────────────┬──────────────┐
│  合约列表      │         工具栏（周期切换）        │              │
│              │                                │              │
│ 螺纹钢  3521  │    ┌─────────────────────┐     │   盘口信息    │
│ 热卷   3620  │    │                     │     │              │
│ 铁矿石  825  │    │     K 线 图          │     │  最新价       │
│ 焦炭   2180  │    │   （红涨绿跌）        │     │  3521        │
│ 黄金   585   │    │                     │     │  +15 +0.43%  │
│ 白银   7350  │    └─────────────────────┘     │              │
│ ...         │    ┌─────────────────────┐     │  卖一 3522    │
│              │    │    成交量柱状图       │     │  买一 3521    │
│              │    └─────────────────────┘     │              │
│              │                                │  开 3510     │
│              │                                │  高 3535     │
│              │                                │  低 3505     │
│              │                                │  量 12.5万   │
└──────────────┴────────────────────────────────┴──────────────┘
```

### 第8步：基本操作

```
- 点击左侧合约    → K线图和盘口切换到该合约
- 顶部切换周期    → 日线 / 60分 / 15分 / 5分
- 搜索框输入      → 支持合约代码（RB）、拼音（LWG）、中文（螺纹钢）
- 行情自动刷新    → 每3秒更新一次报价
```

## 常见问题

### Q: 编译报错 "missing package product"
```bash
# 回到项目根目录，确认核心模块能编译
cd ~/Desktop/macos_futures_trading
swift build
# 如果通过，再进App目录打开
cd App
open Package.swift
```

### Q: Xcode提示 "Package resolution failed"
```
Xcode菜单 → File → Packages → Reset Package Caches
然后重新编译：Cmd + Shift + K（Clean）→ Cmd + R（Run）
```

### Q: 看不到行情数据，显示"等待行情数据"
```
- 确认Mac有网络连接
- 新浪行情在非交易时段（周末/节假日/收盘后）可能返回空数据
- K线数据会正常显示（历史数据），实时报价在交易时段才有
```

### Q: App窗口太小
```
拖拽窗口边缘放大，或者最大化窗口。
最小尺寸：1200 x 700
推荐尺寸：1400 x 850 或全屏
```

### Q: 左上角Scheme没有FuturesTraderApp选项
```
1. 等待Xcode完成包解析（看左下角进度条）
2. 如果一直没有，关闭Xcode重新打开：
   cd App && open Package.swift
```

### Q: 运行时崩溃
```
Xcode菜单 → Product → Clean Build Folder (Cmd + Shift + K)
然后重新 Run (Cmd + R)
```

## 完整命令汇总（复制粘贴即可）

```bash
# 一次性执行（如果还没克隆过）
cd ~/Desktop && git clone https://github.com/ethanzhang2025/macos_futures_trading.git && cd macos_futures_trading && swift build && cd App && open Package.swift
```

```bash
# 如果已经克隆过，拉取最新代码后运行
cd ~/Desktop/macos_futures_trading && git pull && swift build && cd App && open Package.swift
```

Xcode打开后：**选择 FuturesTraderApp → 点 ▶ 或 Cmd+R → 看到界面**
