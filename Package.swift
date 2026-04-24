// swift-tools-version: 6.0
// 本文件由 WP-24 · Swift Package 8 Core 骨架建立 · 2026-04-24
// 详见 Docs/architecture/stage-a-baseline.md
// 依赖 DAG：Shared → DataCore → IndicatorCore → ChartCore
//                          ↓         ↓
//                    JournalCore  AlertCore / ReplayCore
// WorkspaceCore 仅依赖 Shared

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
        .library(name: "WorkspaceCore", targets: ["WorkspaceCore"])
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
        .testTarget(name: "WorkspaceCoreTests", dependencies: ["WorkspaceCore"], path: "Tests/WorkspaceCoreTests")
    ]
)
