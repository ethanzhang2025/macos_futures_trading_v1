# 中国期货 Mac/iPad 原生交易终端

为专业交易者打造的 Mac/iPad 原生专业工作台 —— 盯盘、预警、复盘、训练、日志。

- **Stage A（M0-M9）**：专业工作台，不接 CTP 下单，聚焦 M6 Pro ¥399/年订阅上线
- **Stage B（M12-M24）**：加 CTP 下单 + 麦语言完整兼容 + iPad 专业工作流 + B2B2C
- **Stage C（M24+）**：据结果定（Windows / 证券 / 出海 / 策略市场）

## 项目结构

```
macos_futures_trading_v1/
├── Package.swift                 # Swift 6 主 Package，声明 8 Core targets
├── Sources/                      # 8 Core 业务模块
│   ├── Shared/                   # 跨端共用模型 / 协议 / 工具
│   ├── DataCore/                 # Tick / K 线 / 合约 / 数据源协议
│   ├── IndicatorCore/            # 56 指标 + 麦语言底层函数
│   ├── ChartCore/                # Metal 图表渲染管线
│   ├── JournalCore/              # 交易日志 + 复盘分析
│   ├── AlertCore/                # 条件预警
│   ├── ReplayCore/               # K 线回放
│   └── WorkspaceCore/            # 工作区模板 + 自选
├── Tests/                        # 对应 8 个 testTarget 骨架（Swift Testing）
├── Docs/
│   └── architecture/
│       └── stage-a-baseline.md   # Stage A 架构基线（WP-24 交付物）
├── legacy-source/                # Legacy 代码（subtree 保留 83 commit 历史）
├── chatgpt_工作包清单/            # Claude Code 工程执行参考包
├── ppt/                          # 4 份对外 PPT
├── 新探索/                        # ChatGPT 洞察原档
├── D1-顶层设计.md / D2-... / D3-... / D4-...  # 战略文档
├── 产品设计书.md / Legacy迁移融合方案.md / ...
├── Stage A 工作包清单.md          # Stage A 执行主索引（63 WP）
├── Stage B 工作包清单.md          # Stage B 执行主索引（粗颗粒 37 WP）
├── 工作包映射表.md                 # ChatGPT ↔ 我的 WP 双向映射
└── Claude Code 启动 prompt 模板.md # 编码开工 prompt 生成器
```

## 快速启动

### Linux（纯逻辑 Core）
```bash
swift build                       # 编译 8 Core
swift test                        # 跑 8 个 Core 测试（Swift Testing）
```

### macOS（含 SwiftUI / AppKit / Metal）
```bash
# 在 Mac 上拉取最新代码并用 Xcode 打开
cd /Users/admin/Documents/MAC版本_期货交易终端/macos_futures_trading_v1 && git pull && open Package.swift
```

## 阅读顺序（新会话入口）

1. `会话交接文档.md` — 项目全景索引
2. `D1-顶层设计.md` — 愿景 / 原则 / 北极星
3. `Stage A 工作包清单.md` — 执行主索引
4. `Docs/architecture/stage-a-baseline.md` — 工程架构基线

## 开发约定

- **语言**：Swift 6（严格并发）· macOS 13+ / iOS 16+
- **图表**：Metal 自研（60fps · 10w K 线）
- **后端**：Go（未来 WP-80 起）
- **云同步**：CloudKit（非敏感）+ 阿里云自建（敏感，合规详 StageA-补遗与深化.md G1）
- **支付**：Apple IAP + 微信/支付宝（Stage A 末）
- **编码规则**：遵循 Karpathy Guidelines（避免过度复杂 / 手术式修改 / 显性假设 / 可验证成功标准）
