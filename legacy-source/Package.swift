// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FuturesTrader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "FormulaEngine", targets: ["FormulaEngine"]),
        .library(name: "MarketData", targets: ["MarketData"]),
        .library(name: "ContractManager", targets: ["ContractManager"]),
        .library(name: "TradingEngine", targets: ["TradingEngine"]),
    ],
    dependencies: [],
    targets: [
        // ── Shared ──────────────────────────────────
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),

        // ── FormulaEngine ───────────────────────────
        .target(
            name: "FormulaEngine",
            dependencies: ["Shared"],
            path: "Sources/FormulaEngine"
        ),
        .testTarget(
            name: "FormulaEngineTests",
            dependencies: ["FormulaEngine"],
            path: "Tests/FormulaEngineTests"
        ),

        // ── MarketData ──────────────────────────────
        .target(
            name: "MarketData",
            dependencies: ["Shared"],
            path: "Sources/MarketData"
        ),
        .testTarget(
            name: "MarketDataTests",
            dependencies: ["MarketData"],
            path: "Tests/MarketDataTests"
        ),

        // ── ContractManager ─────────────────────────
        .target(
            name: "ContractManager",
            dependencies: ["Shared"],
            path: "Sources/ContractManager"
        ),
        .testTarget(
            name: "ContractManagerTests",
            dependencies: ["ContractManager"],
            path: "Tests/ContractManagerTests"
        ),

        // ── TradingEngine ───────────────────────────
        .target(
            name: "TradingEngine",
            dependencies: ["Shared", "MarketData"],
            path: "Sources/TradingEngine"
        ),
        .testTarget(
            name: "TradingEngineTests",
            dependencies: ["TradingEngine"],
            path: "Tests/TradingEngineTests"
        ),

        // ── ChartEngine (macOS only) ────────────────
        // 图表引擎依赖 Metal/AppKit，仅在 macOS 上编译
        // 在 Xcode 中通过 xcodeproj 引入，不在 SPM 中定义

        // ── CTPBridge (macOS only) ──────────────────
        // CTP SDK 依赖 macOS dylib，仅在 macOS 上编译
        // 在 Xcode 中通过 xcodeproj 引入，不在 SPM 中定义
    ]
)
