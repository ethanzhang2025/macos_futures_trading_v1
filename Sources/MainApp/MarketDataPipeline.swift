// MainApp · 真行情数据管线
//
// 装配链：Sina（历史 + 实时）→ Provider → Driver
//        + InMemoryKLineCacheStore（spike 临时 · 重启即失效）
//        + UnifiedDataSource（cache + history merge + 实时 KLineBuilder）
//
// 暴露给 ChartScene：
//   - start() async throws -> AsyncStream<DataSourceUpdate>
//   - stop() async（窗口关闭时调）
//
// 默认 RB0 · 15min · 200 根 · 轮询 5s
// 真行情拉空 → 由 caller（ChartScene）做 Mock 兜底（不在管线层硬编码 fallback · 保持职责单一）

#if canImport(SwiftUI) && os(macOS)

import Foundation
import Shared
import DataCore

@MainActor
final class MarketDataPipeline {

    static let defaultInstrumentID = "RB0"
    static let defaultPeriod: KLinePeriod = .minute15
    static let pollingInterval: TimeInterval = 5.0
    static let cacheMaxBars: Int = 200

    /// 主图可切换的合约清单（spike 硬编码 · 后续 WP-43 接 WatchlistBook UI 替换）
    /// 复用 EndToEndDemo 验证过的 4 个 Sina 主力合约
    static let supportedContracts: [String] = ["RB0", "IF0", "AU0", "CU0"]

    /// 主图可切换的周期清单（spike 保守 6 个 · 秒级/周月 spike 阶段不暴露）
    /// Sina API 拉 tick · KLineBuilder 客户端合成任意周期 · UI 仅放主流分钟+日
    static let supportedPeriods: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30, .hour1, .daily
    ]

    let instrumentID: String
    let period: KLinePeriod

    private let sina: SinaMarketData
    private let provider: SinaMarketDataProvider
    private let driver: SinaPollingDriver
    private let uds: UnifiedDataSource

    init(
        instrumentID: String = MarketDataPipeline.defaultInstrumentID,
        period: KLinePeriod = MarketDataPipeline.defaultPeriod
    ) {
        self.instrumentID = instrumentID
        self.period = period
        let sina = SinaMarketData()
        let provider = SinaMarketDataProvider(fetcher: sina)
        self.sina = sina
        self.provider = provider
        self.driver = SinaPollingDriver(provider: provider, interval: Self.pollingInterval)
        self.uds = UnifiedDataSource(
            cache: InMemoryKLineCacheStore(),
            realtime: provider,
            historical: sina,
            cacheMaxBars: Self.cacheMaxBars
        )
    }

    /// 启动管线 · UDS 拉历史 + 订阅实时 + 启动轮询
    /// 失败：connect / start 内部不抛 · stream 由 UDS 保证至少 emit 一次 .snapshot（可能为空数组）
    func start() async -> AsyncStream<DataSourceUpdate> {
        await provider.connect()
        let stream = await uds.start(instrumentID: instrumentID, period: period)
        await driver.start()
        return stream
    }

    /// 停止管线（窗口关闭时调用 · 清理订阅 + 轮询）
    func stop() async {
        await driver.stop()
        await uds.stopAll()
        await provider.disconnect()
    }

    /// 周期对外可读字符串（信息浮层显示 · 与 toolbar Picker 中文一致）
    var periodLabel: String { period.displayName }
}

#endif
