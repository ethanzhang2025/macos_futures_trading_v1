# macOS Futures Trading Terminal

macOS 原生期货交易终端，对标 TradingView 图表能力，兼容通达信/文华财经公式系统。

## 定位

国内期货交易软件在 macOS 平台几乎完全空白。文华财经、博易大师、快期等主流软件均无 macOS 原生版本。本项目旨在填补这一空白，提供专业级的 macOS 原生期货交易体验。

## 核心特性

- **TradingView 级图表** — Metal 渲染，60fps 流畅交互，支持 K 线/分时/Tick/Volume Profile/DOM 等
- **通达信公式兼容** — 内置 200+ 函数，支持导入通达信/文华公式文件
- **CTP 交易接入** — 标准 CTP 接口，一套对接 90%+ 国内期货公司
- **条件单系统** — 止损/止盈/追踪止损/OCO/括号单，客户端本地执行
- **期权支持** — T 型报价、Greeks 计算、策略构建器
- **程序化交易** — 策略回测 + 模拟盘 + 实盘，无缝切换

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS App (Swift)                         │
├──────────┬──────────┬──────────┬──────────┬────────────────┤
│   UI层   │  图表引擎  │ 公式引擎  │ 交易引擎  │   风控模块    │
│ SwiftUI  │  Metal   │ TDX/麦语言│  CTP    │  保证金计算   │
│ +AppKit  │  渲染    │  解释器   │  封装    │  强平预警     │
├──────────┴──────────┴──────────┴──────────┴────────────────┤
│                     数据层 (Swift Actors)                    │
├──────────┬──────────┬──────────┬───────────────────────────┤
│ CTP MdApi│ CTP Trade│  REST    │    本地存储 (SQLite)       │
│ Tick行情  │ 交易指令  │ 历史数据  │   合约/持仓/公式/配置      │
└──────────┴──────────┴──────────┴───────────────────────────┘
```

## 项目结构

```
Sources/
├── FuturesTrader/         # macOS App 入口
├── CTPBridge/             # CTP C++/Swift 封装层
│   ├── CWrapper/          # C 中间层
│   └── Swift/             # Swift Actor 封装
├── MarketData/            # 行情数据管理
│   ├── TickEngine/        # Tick 接收与分发
│   ├── KLineEngine/       # K 线合成（Tick → 任意周期）
│   └── Storage/           # 本地持久化
├── ChartEngine/           # 图表渲染引擎
│   ├── Renderer/          # Metal 渲染核心
│   ├── Charts/            # K线/分时/Tick/DOM 等图表
│   ├── Indicators/        # 指标渲染
│   └── Interaction/       # 手势/十字光标/绘图工具
├── FormulaEngine/         # 公式引擎
│   ├── Lexer/             # 词法分析
│   ├── Parser/            # 语法分析
│   ├── Interpreter/       # 解释执行
│   └── BuiltinFunctions/  # 内置函数库 (200+)
├── TradingEngine/         # 交易引擎
│   ├── OrderManager/      # 委托管理
│   ├── PositionManager/   # 持仓管理
│   ├── RiskControl/       # 风控
│   └── ConditionalOrder/  # 条件单
├── ContractManager/       # 合约与交易日历管理
└── Shared/                # 共享模型与工具
    ├── Models/            # 数据模型 (Tick/KLine/Contract/Order)
    └── Extensions/        # 工具扩展

Tests/                     # 单元测试
Resources/                 # 合约规格/交易日历数据
Docs/                      # 方案文档
```

## 开发环境

| 组件 | 版本 |
|------|------|
| Swift | 6.0+ |
| macOS 目标 | 13.0+ (Ventura) |
| Xcode | 15.0+ |
| CTP SDK | 6.7.x+ (arm64) |

**双机开发模式**：Linux 上编写代码 + 运行核心模块测试，macOS 上编译完整 App + UI 测试。

## 构建

```bash
# Linux/macOS — 编译核心模块（不含 UI/Metal/CTP）
swift build

# Linux/macOS — 运行测试
swift test

# macOS — 完整编译（需要 Xcode）
xcodebuild -scheme FuturesTrader -configuration Release
```

## 支持的交易所

| 交易所 | 代码 | 主要品种 |
|--------|------|---------|
| 上海期货交易所 | SHFE | 铜/铝/锌/黄金/白银/螺纹钢/天然橡胶 |
| 上海国际能源交易中心 | INE | 原油/国际铜/低硫燃料油 |
| 大连商品交易所 | DCE | 豆粕/铁矿石/焦炭/聚乙烯/棕榈油 |
| 郑州商品交易所 | CZCE | 白糖/棉花/PTA/甲醇/纯碱/玻璃 |
| 中国金融期货交易所 | CFFEX | 沪深300股指/国债期货 |
| 广州期货交易所 | GFEX | 工业硅/碳酸锂 |

## License

MIT
