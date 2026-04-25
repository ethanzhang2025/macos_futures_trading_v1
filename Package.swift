// swift-tools-version: 6.0
// WP-24 · Swift Package 8 Core 骨架 · 2026-04-24 建立
// WP-30 · Legacy 5 targets 迁入（Shared/MarketData/ContractManager/FormulaEngine/TradingEngine.ConditionalOrder）· 新增 TradingCore target
// 详见 Docs/architecture/stage-a-baseline.md
// 依赖 DAG：Shared → DataCore → IndicatorCore → ChartCore
//                          ↓         ↓
//                    JournalCore  AlertCore / ReplayCore / TradingCore
// WorkspaceCore 仅依赖 Shared
// TradingCore Stage A 不激活到 App，Stage B WP-220 起使用

import PackageDescription

let package = Package(
    name: "FuturesTerminal",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "DataCore", targets: ["DataCore"]),
        .library(name: "IndicatorCore", targets: ["IndicatorCore"]),
        .library(name: "ChartCore", targets: ["ChartCore"]),
        .library(name: "JournalCore", targets: ["JournalCore"]),
        .library(name: "AlertCore", targets: ["AlertCore"]),
        .library(name: "ReplayCore", targets: ["ReplayCore"]),
        .library(name: "WorkspaceCore", targets: ["WorkspaceCore"]),
        .library(name: "TradingCore", targets: ["TradingCore"])
    ],
    dependencies: [],
    targets: [
        // MARK: - Shared · 跨端共用的模型 / 协议 / 工具
        .target(name: "Shared", path: "Sources/Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"], path: "Tests/SharedTests"),

        // MARK: - DataCore · Tick / K 线 / 合约 / 数据源协议
        .target(name: "DataCore", dependencies: ["Shared"], path: "Sources/DataCore"),
        .testTarget(name: "DataCoreTests", dependencies: ["DataCore"], path: "Tests/DataCoreTests"),

        // MARK: - IndicatorCore · 56 指标 + 麦语言底层函数
        .target(name: "IndicatorCore", dependencies: ["Shared", "DataCore"], path: "Sources/IndicatorCore"),
        .testTarget(name: "IndicatorCoreTests", dependencies: ["IndicatorCore"], path: "Tests/IndicatorCoreTests"),

        // MARK: - ChartCore · Metal 图表渲染管线
        .target(name: "ChartCore", dependencies: ["Shared", "DataCore", "IndicatorCore"], path: "Sources/ChartCore"),
        .testTarget(name: "ChartCoreTests", dependencies: ["ChartCore"], path: "Tests/ChartCoreTests"),

        // MARK: - JournalCore · 交易日志 + 复盘分析
        .target(name: "JournalCore", dependencies: ["Shared", "DataCore"], path: "Sources/JournalCore"),
        .testTarget(name: "JournalCoreTests", dependencies: ["JournalCore"], path: "Tests/JournalCoreTests"),

        // MARK: - AlertCore · 条件预警
        .target(name: "AlertCore", dependencies: ["Shared", "DataCore", "IndicatorCore"], path: "Sources/AlertCore"),
        .testTarget(name: "AlertCoreTests", dependencies: ["AlertCore"], path: "Tests/AlertCoreTests"),

        // MARK: - ReplayCore · K 线回放
        .target(name: "ReplayCore", dependencies: ["Shared", "DataCore"], path: "Sources/ReplayCore"),
        .testTarget(name: "ReplayCoreTests", dependencies: ["ReplayCore"], path: "Tests/ReplayCoreTests"),

        // MARK: - WorkspaceCore · 工作区模板 + 自选
        .target(name: "WorkspaceCore", dependencies: ["Shared"], path: "Sources/WorkspaceCore"),
        .testTarget(name: "WorkspaceCoreTests", dependencies: ["WorkspaceCore"], path: "Tests/WorkspaceCoreTests"),

        // MARK: - TradingCore · CTP 下单与条件单（Legacy TradingEngine/ConditionalOrder 迁入）
        // Stage A 不激活到 App；Stage B WP-220 起使用
        .target(name: "TradingCore", dependencies: ["Shared", "DataCore"], path: "Sources/TradingCore"),
        .testTarget(name: "TradingCoreTests", dependencies: ["TradingCore"], path: "Tests/TradingCoreTests"),

        // MARK: - Tools · 命令行验证工具（非生产代码，CI 可跳过）
        // SinaTickDemo · WP-31a 真网络回归（拉 RB0/IF0/AU0/CU0 实时报价 30s）
        .executableTarget(
            name: "SinaTickDemo",
            dependencies: ["Shared", "DataCore"],
            path: "Tools/SinaTickDemo"
        ),
        // IndicatorSmokeDemo · WP-41 真数据冒烟（Sina 60min K 线 → MA/EMA/MACD/RSI/BOLL/KDJ）
        .executableTarget(
            name: "IndicatorSmokeDemo",
            dependencies: ["Shared", "DataCore", "IndicatorCore"],
            path: "Tools/IndicatorSmokeDemo"
        ),
        // ReviewSmokeDemo · WP-50 复盘 8 图真数据冒烟（基于 RB0 真实价位 12 笔成交 → FIFO 配对 → 8 个聚合算法）
        .executableTarget(
            name: "ReviewSmokeDemo",
            dependencies: ["Shared", "DataCore", "JournalCore"],
            path: "Tools/ReviewSmokeDemo"
        ),
        // AlertSmokeDemo · WP-52 条件预警真数据冒烟（Sina 真行情 → 4 类预警 → 触发记录）
        .executableTarget(
            name: "AlertSmokeDemo",
            dependencies: ["Shared", "DataCore", "AlertCore"],
            path: "Tools/AlertSmokeDemo"
        )
    ]
)
