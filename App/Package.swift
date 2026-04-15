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
                .product(name: "Shared", package: "FuturesTrader"),
                .product(name: "FormulaEngine", package: "FuturesTrader"),
                .product(name: "MarketData", package: "FuturesTrader"),
                .product(name: "ContractManager", package: "FuturesTrader"),
                .product(name: "TradingEngine", package: "FuturesTrader"),
            ]
        ),
    ]
)
