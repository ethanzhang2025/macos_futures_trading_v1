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
        .library(name: "TradingCore", targets: ["TradingCore"]),
        .library(name: "StoreCore", targets: ["StoreCore"])
    ],
    dependencies: [],
    targets: [
        // MARK: - CSQLite · SQLCipher（WP-19a 持久化 + WP-19b 加密层）
        // 接口与 SQLite3 完全兼容（drop-in replacement）· 不传 passphrase 时行为同原生 SQLite
        // Linux: 需 libsqlcipher-dev；macOS: brew install sqlcipher（M5 上线时按需安装）
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            pkgConfig: "sqlcipher",
            providers: [
                .apt(["libsqlcipher-dev"]),
                .brew(["sqlcipher"])
            ]
        ),

        // MARK: - Shared · 跨端共用的模型 / 协议 / 工具
        .target(name: "Shared", dependencies: ["CSQLite"], path: "Sources/Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"], path: "Tests/SharedTests"),

        // MARK: - DataCore · Tick / K 线 / 合约 / 数据源协议
        .target(name: "DataCore", dependencies: ["Shared"], path: "Sources/DataCore"),
        .testTarget(name: "DataCoreTests", dependencies: ["DataCore"], path: "Tests/DataCoreTests"),

        // MARK: - IndicatorCore · 56 指标 + 麦语言底层函数
        .target(name: "IndicatorCore", dependencies: ["Shared", "DataCore"], path: "Sources/IndicatorCore"),
        .testTarget(name: "IndicatorCoreTests", dependencies: ["IndicatorCore"], path: "Tests/IndicatorCoreTests"),

        // MARK: - ChartCore · Metal 图表渲染管线
        // KLineShaders.metal 是 reference 文件（仅供 Xcode 浏览 + IDE 高亮）·
        // 实际 shader 通过 KLineShaderSource.metalSourceCode 内嵌字符串 device.makeLibrary(source:) 运行时编译。
        // exclude 该文件避免 Swift PM 在 Linux 端尝试 process .metal（无 metal compiler）。
        .target(
            name: "ChartCore",
            dependencies: ["Shared", "DataCore", "IndicatorCore"],
            path: "Sources/ChartCore",
            exclude: ["Metal/KLineShaders.metal"]
        ),
        .testTarget(name: "ChartCoreTests", dependencies: ["ChartCore", "IndicatorCore"], path: "Tests/ChartCoreTests"),

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

        // MARK: - StoreCore · 6 store 统一管理器（WP-19a-7 · M5 Mac App 启动入口）
        // 集中：path 模板 + passphrase 注入 + 生命周期；依赖 Shared + 3 个 store 宿主模块
        .target(
            name: "StoreCore",
            dependencies: ["Shared", "DataCore", "JournalCore", "AlertCore"],
            path: "Sources/StoreCore"
        ),
        .testTarget(name: "StoreCoreTests", dependencies: ["StoreCore"], path: "Tests/StoreCoreTests"),

        // MARK: - MainApp · macOS App 主框架（demo → 真 App · M5 集成入口）
        // SwiftUI App 协议 · WindowGroup × 2（K 线图表 / 自选合约）· Settings Scene · 主菜单 .commands
        // Linux 端 #if 跳过整 target body · @main fallback 仅打印提示后退出
        // 后续 WP 接入：WP-43 自选 UI / WP-44 多窗口 / WP-90 订阅 / M5 StoreCore 注入
        .executableTarget(
            name: "MainApp",
            dependencies: ["Shared", "DataCore", "ChartCore", "IndicatorCore", "ReplayCore"],
            path: "Sources/MainApp"
        ),

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
        ),
        // ReplaySmokeDemo · WP-51 K 线回放真数据冒烟（Sina 50 根 RB0 K 线 → 60x 回放 + 暂停/倒退/速度切换）
        .executableTarget(
            name: "ReplaySmokeDemo",
            dependencies: ["Shared", "DataCore", "ReplayCore"],
            path: "Tools/ReplaySmokeDemo"
        ),
        // MultiPeriodKLineDemo · Sina tick → KLineBuilder 多周期实时合成（1m/3m/5m/15m 同步）
        .executableTarget(
            name: "MultiPeriodKLineDemo",
            dependencies: ["Shared", "DataCore"],
            path: "Tools/MultiPeriodKLineDemo"
        ),
        // EndToEndDemo · 端到端业务流真数据冒烟（自选 + Sina 实时 + UDS + IndicatorCore + AlertCore + StoreCore v6.0+ 升级）
        .executableTarget(
            name: "EndToEndDemo",
            dependencies: ["Shared", "DataCore", "IndicatorCore", "AlertCore", "StoreCore"],
            path: "Tools/EndToEndDemo"
        ),
        // ReviewReplayDemo · 复盘 + 回放联动真数据冒烟（JournalCore × ReplayCore × DataCore-Sina）
        .executableTarget(
            name: "ReviewReplayDemo",
            dependencies: ["Shared", "DataCore", "JournalCore", "ReplayCore"],
            path: "Tools/ReviewReplayDemo"
        ),
        // UDSHistoryMergeDemo · UDS v2 历史合并真数据冒烟（v1 空 snapshot vs v2 历史 N 根）
        .executableTarget(
            name: "UDSHistoryMergeDemo",
            dependencies: ["Shared", "DataCore"],
            path: "Tools/UDSHistoryMergeDemo"
        ),
        // IndicatorAlertDemo · IndicatorCore + AlertCore 联动（MA20 crossAbove 动态预警 + Console + File 通道）
        .executableTarget(
            name: "IndicatorAlertDemo",
            dependencies: ["Shared", "DataCore", "IndicatorCore", "AlertCore"],
            path: "Tools/IndicatorAlertDemo"
        ),
        // WatchlistWorkspacePersistDemo · WP-19a-5/6 SQLite 持久化端到端（写入 + 重启恢复 + 脏 JSON 保护）
        .executableTarget(
            name: "WatchlistWorkspacePersistDemo",
            dependencies: ["Shared"],
            path: "Tools/WatchlistWorkspacePersistDemo"
        ),
        // AlertHistorySmokeDemo · history(from:to:) 真数据 + 10000 条性能压测 + 索引命中对比
        .executableTarget(
            name: "AlertHistorySmokeDemo",
            dependencies: ["Shared", "AlertCore"],
            path: "Tools/AlertHistorySmokeDemo"
        ),
        // WenhuaCSVImportDemo · 文华交割单 CSV 真实样本解析（CSV → RawDeal → Trade → 报表）
        .executableTarget(
            name: "WenhuaCSVImportDemo",
            dependencies: ["Shared", "JournalCore"],
            path: "Tools/WenhuaCSVImportDemo"
        ),
        // JournalGeneratorDemo · 半自动日志初稿（windowSeconds 配置对比 + A09 单向引用验证）
        .executableTarget(
            name: "JournalGeneratorDemo",
            dependencies: ["Shared", "JournalCore"],
            path: "Tools/JournalGeneratorDemo"
        ),
        // EncryptionDemo · WP-19b SQLCipher 加密层端到端（hexdump 字节差异 + 6 store 加密 init 串测）
        .executableTarget(
            name: "EncryptionDemo",
            dependencies: ["Shared", "DataCore", "JournalCore", "AlertCore"],
            path: "Tools/EncryptionDemo"
        ),
        // ContractStoreDemo · 合约元数据加载完整链路（JSON → ProductSpec → Contract → ContractStore）
        .executableTarget(
            name: "ContractStoreDemo",
            dependencies: ["Shared", "DataCore"],
            path: "Tools/ContractStoreDemo"
        ),
        // StoreManagerDemo · WP-19a-7 第 17 个真数据 demo（M5 启动流程预演 · 6 store 一次 init + 联动写读 + 加密重启）
        .executableTarget(
            name: "StoreManagerDemo",
            dependencies: ["Shared", "DataCore", "JournalCore", "AlertCore", "StoreCore"],
            path: "Tools/StoreManagerDemo"
        ),
        // MaiYuYanFormulaDemo · WP-62 第 18 个真数据 demo（Sina 真行情 + 8 公式 + 10 新函数全覆盖）
        .executableTarget(
            name: "MaiYuYanFormulaDemo",
            dependencies: ["Shared", "DataCore", "IndicatorCore"],
            path: "Tools/MaiYuYanFormulaDemo"
        ),
        // FuturesContextualDemo · WP-41 B1 Step 2 第 19 个真数据 demo
        // (Sina RB0 真行情 + 模拟 FuturesContext + 4 ContextualIndicator)
        .executableTarget(
            name: "FuturesContextualDemo",
            dependencies: ["Shared", "DataCore", "IndicatorCore"],
            path: "Tools/FuturesContextualDemo"
        ),
        // MetalKLineDemo · WP-20 Metal K 线 PoC 性能验收（M6 生死核心 · 10w K 60fps）
        // headless offscreen 1280x720 · 1w/10w K 各 100 帧 · 报告 avg/max/healthy60fps · Linux 端跳过
        .executableTarget(
            name: "MetalKLineDemo",
            dependencies: ["Shared", "ChartCore"],
            path: "Tools/MetalKLineDemo"
        ),
        // MetalKLineWindowDemo · WP-20 SwiftUI 真窗口 + zoom/pan gesture + WP-40 起步 MA20/MA60 折线
        // NSApplication + NSWindow + NSHostingView · ContentView pinch zoom + drag pan · 10w K 模拟数据
        // IndicatorCore 算 MA（基于 Legacy FormulaEngine 演化）· renderer 叠折线 · 同 viewMatrix
        // Mac 端 swift run 直接见画面 + trackpad 交互 · Linux 端跳过
        .executableTarget(
            name: "MetalKLineWindowDemo",
            dependencies: ["Shared", "ChartCore", "IndicatorCore"],
            path: "Tools/MetalKLineWindowDemo"
        )
    ]
)
