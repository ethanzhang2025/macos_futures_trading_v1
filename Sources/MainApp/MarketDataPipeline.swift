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

    /// 缓存上限按 period 动态（v12.9 · 中国期货每天约 540min 交易 · 让小周期能覆盖更多天 · 大周期合理保留长跨度）
    /// - 1min: 10000 ≈ 18 个交易日（短线分析）
    /// - 5min:  5000 ≈ 46 天（中期）
    /// - 15min: 3000 ≈ 80 天（约 4 个月）
    /// - 30min: 2000 ≈ 110 天（约 5 个月）
    /// - 60min: 1500 ≈ 165 天（约 8 个月）
    /// - daily: 1500 ≈ 6 年（长期）
    /// - weekly/monthly: 各自合理跨度
    static func cacheMaxBars(for period: KLinePeriod) -> Int {
        switch period {
        case .minute1:  return 10000
        case .minute5:  return 5000
        case .minute15: return 3000
        case .minute30: return 2000
        case .hour1:    return 1500
        case .daily:    return 1500
        case .weekly:   return 500
        case .monthly:  return 300
        default:        return 5000
        }
    }

    /// 主图可切换的合约清单（v12.16 动态主力月）
    /// 4 主连续（RB0/IF0/AU0/CU0）+ 4 active 月份合约（DominantMonthCalculator 按品种规则推断 · 半年自动续期）
    /// 实测 2026-04-29 主力月：rb2609 / i2609 / au2606 / IF2605（与 SinaMonthlyContractDemo oi 排序吻合）
    /// 实时报价对小写 + I 字母合约 v12.3 W1 修复后全支持 · K 线端点 v12.6 SinaKLineGranularityDemo 验证 type=1/5/15/30/60 全支持
    static var supportedContracts: [String] {
        let mainContinuous = ["RB0", "IF0", "AU0", "CU0"]
        let activeMonthlyPrefixes = ["rb", "i", "au", "IF"]
        let activeMonthly = activeMonthlyPrefixes.compactMap {
            DominantMonthCalculator.dominantContract(prefix: $0)
        }
        return mainContinuous + activeMonthly
    }

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
            cacheMaxBars: Self.cacheMaxBars(for: period)
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
