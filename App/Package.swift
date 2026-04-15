// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FuturesTraderApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "FuturesTraderApp",
            dependencies: [
                .product(name: "Shared", package: "macos_futures_trading"),
                .product(name: "FormulaEngine", package: "macos_futures_trading"),
                .product(name: "MarketData", package: "macos_futures_trading"),
                .product(name: "ContractManager", package: "macos_futures_trading"),
                .product(name: "TradingEngine", package: "macos_futures_trading"),
            ]
        ),
    ]
)
