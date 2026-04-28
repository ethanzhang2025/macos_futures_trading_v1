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

    /// 周期对外可读字符串（信息浮层显示用）
    /// rawValue 本身是中国习惯写法（1m/15m/1h 等），仅日/周/月转中文
    var periodLabel: String {
        switch period {
        case .daily:   return "日"
        case .weekly:  return "周"
        case .monthly: return "月"
        default:       return period.rawValue
        }
    }
}

#endif
