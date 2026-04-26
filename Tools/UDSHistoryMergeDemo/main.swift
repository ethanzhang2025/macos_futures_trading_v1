// UnifiedDataSource v2 历史合并真数据冒烟 demo（第 9 个真数据 demo）
//
// 用途：
// - 验证 UDS v2 注入 HistoricalKLineProvider 后 start() 立即返回完整历史 K snapshot
// - v1 vs v2 对比：cache 空时 v1 = 空 snapshot；v2 = 历史 N 根 snapshot
// - 模拟 UI 层启动场景："开图表立刻有完整历史 + 实时拼接最新一根"
//
// 拓扑：
//   段 1（v1 基线对照）：UDS 不注入 historical → start RB0 hour1 → snapshot 应空
//   段 2（v2 历史合并）：同 UDS 注入 SinaMarketData → start RB0 hour1 → snapshot N 根真历史
//   段 3（实时拼接）：跑 60s 真 Sina tick → 跨周期时 yield .completedBar 增量
//
// 共享：1 个 SinaMarketData 实例同时充当 historical（HistoricalKLineProvider）+ realtime fetcher
//
// 运行：swift run UDSHistoryMergeDemo
// 注意：非交易时段段 3 可能 0 .completedBar（KLineBuilder 对齐失败，与 EndToEndDemo 同因）

import Foundation
import Shared
import DataCore

@main
struct UDSHistoryMergeDemo {

    static func main() async throws {
        printSection("UDS v2 历史合并真数据冒烟（v1 空 snapshot vs v2 历史 N 根）")

        let sina = SinaMarketData()

        // 段 1：v1 基线（不注入 historical）
        printSection("段 1 · v1 基线对照（不注入 historical）")
        let cache1 = InMemoryKLineCacheStore()
        let providerSilent = SimulatedMarketDataProvider()  // 不连真网络，避免污染段 1
        let udsV1 = UnifiedDataSource(cache: cache1, realtime: providerSilent)
        let v1Stream = await udsV1.start(instrumentID: "RB0", period: .hour1)
        let v1Snapshot = await firstSnapshot(from: v1Stream)
        print("  📦 v1 snapshot：\(v1Snapshot.count) 根（cache 空 + 无 historical → 期望 0）")
        await udsV1.stopAll()

        // 段 2：v2 注入 historical
        printSection("段 2 · v2 注入 SinaMarketData 作为 historical")
        let cache2 = InMemoryKLineCacheStore()
        let providerLive = SinaMarketDataProvider(fetcher: sina)
        await providerLive.connect()
        let udsV2 = UnifiedDataSource(
            cache: cache2,
            realtime: providerLive,
            historical: sina,
            cacheMaxBars: 200  // 与 v2 默认对齐 · 历史多了截尾保留最近 200 根
        )
        let v2Stream = await udsV2.start(instrumentID: "RB0", period: .hour1)
        let v2Snapshot = await firstSnapshot(from: v2Stream)
        print("  📦 v2 snapshot：\(v2Snapshot.count) 根（cache 空 + historical hour1 → 期望 ≥1）")

        if let first = v2Snapshot.first, let last = v2Snapshot.last {
            print("  📅 时间范围：\(formatTime(first.openTime)) ~ \(formatTime(last.openTime))")
            print("  💰 起始 close=\(fmt(first.close)) → 末尾 close=\(fmt(last.close))")
            printSample(label: "首", bars: Array(v2Snapshot.prefix(3)))
            if v2Snapshot.count > 3 {
                printSample(label: "末", bars: Array(v2Snapshot.suffix(3)))
            }
        }

        // 跨 Core 一致性：snapshot 末尾 close ≈ Sina 当前实时报价
        let liveQuote = (try? await sina.fetchQuote(symbol: "RB0"))?.lastPrice
        if let liveQuote, let last = v2Snapshot.last {
            let diff = abs(NSDecimalNumber(decimal: last.close - liveQuote).doubleValue)
            print("  🔗 一致性：snapshot 末尾 close=\(fmt(last.close)) · Sina 实时 last=\(fmt(liveQuote)) · 差 \(String(format: "%.2f", diff))")
        }

        // 段 3：实时拼接 60s
        printSection("段 3 · 实时拼接（跑 60s · Sina 3s 间隔轮询）")
        let counter = StreamCounter()
        let consumeTask = Task {
            for await update in v2Stream {
                switch update {
                case .snapshot(let bars):
                    print(stamp() + "  📦 [意外] 段 3 又收到 snapshot \(bars.count) 根")
                case .completedBar(let k):
                    print(stamp() + "  📈 实时合成 1 根 · openTime=\(formatTime(k.openTime)) close=\(fmt(k.close))")
                    await counter.bumpBar()
                }
            }
        }

        let driver = SinaPollingDriver(provider: providerLive, interval: 3.0)
        await driver.start()
        try await Task.sleep(nanoseconds: 60 * 1_000_000_000)

        await driver.stop()
        await udsV2.stopAll()
        await providerLive.disconnect()
        consumeTask.cancel()

        let completedBars = await counter.barsEmitted
        print(stamp() + "  实时合成 \(completedBars) 根 .completedBar（非交易时段可能 = 0）")

        // 总结
        printSection("v1 vs v2 对比总结")
        print("  v1（仅 cache）         · snapshot \(v1Snapshot.count) 根")
        print("  v2（cache + historical）· snapshot \(v2Snapshot.count) 根（启动即有完整历史）")
        print("  v2 实时拼接            · 60s 内 +\(completedBars) 根 .completedBar")

        let v2HasHistory = v2Snapshot.count > v1Snapshot.count
        printSection(v2HasHistory
            ? "🎉 UDS v2 历史合并真数据冒烟通过（启动即有 \(v2Snapshot.count) 根历史 K）"
            : "⚠️  v2 未拉到历史（可能网络异常或 Sina 返回空）")
    }

    // MARK: - Stream 辅助

    /// 拉一次 .snapshot 事件后立即返回（不消耗后续事件）
    static func firstSnapshot(from stream: AsyncStream<DataSourceUpdate>) async -> [KLine] {
        for await update in stream {
            if case .snapshot(let bars) = update { return bars }
        }
        return []
    }

    /// 打印 K 线抽样段（label 例："首" / "末"）
    static func printSample(label: String, bars: [KLine]) {
        print("  📋 \(label) \(bars.count) 根：")
        for k in bars {
            print("     \(formatTime(k.openTime)) O=\(fmt(k.open)) H=\(fmt(k.high)) L=\(fmt(k.low)) C=\(fmt(k.close)) V=\(k.volume)")
        }
    }

    // MARK: - 通用 helpers

    static let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let kLineTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    static func fmt(_ value: Decimal) -> String {
        priceFormatter.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func stamp() -> String {
        "[\(stampFormatter.string(from: Date()))]"
    }

    static func formatTime(_ date: Date) -> String {
        kLineTimeFormatter.string(from: date)
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}

// MARK: - 计数器 actor

private actor StreamCounter {
    private(set) var barsEmitted: Int = 0
    func bumpBar() { barsEmitted += 1 }
}
