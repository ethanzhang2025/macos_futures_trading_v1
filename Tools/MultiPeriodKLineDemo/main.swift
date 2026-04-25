// WP-44 子任务 · Sina + KLineBuilder 多周期实时合成 demo
//
// 用途：
// - SinaProvider 实时报价（每 3s 一次）→ KLineBuilder 4 周期同步合成 K 线（1m/3m/5m/15m）
// - 跑 120 秒 · 1m K 应产出 1-2 根（跨 1-2 个分钟边界）；3m/5m/15m 大概率 0（120s 不够跨 3m 边界）
// - 验证：Sina tick → KLineBuilder.onTick → completedBar 整条链路真数据流通
//
// 运行：swift run MultiPeriodKLineDemo
//
// 注意：
// - Sina 实时报价每 3s 一次，多个 tick 落在同一分钟内累积成 1 根 1m K
// - 跨 60s 边界时 KLineBuilder.onTick 返回完成 K 线
// - "完成 K 线"的 close 是上一根的最后一个 tick 的 lastPrice

import Foundation
import Shared
import DataCore

@main
struct MultiPeriodKLineDemo {

    static func main() async throws {
        print("─────────────────────────────────────────────")
        print("WP-44 多周期 · Sina + KLineBuilder 实时合成 demo")
        print("─────────────────────────────────────────────")

        let symbol = "RB0"
        let periods: [KLinePeriod] = [.minute1, .minute3, .minute5, .minute15]
        let aggregator = MultiPeriodAggregator(instrumentID: symbol, periods: periods)

        let fetcher = SinaMarketData()
        let provider = SinaMarketDataProvider(fetcher: fetcher)
        await provider.connect()

        await provider.subscribe(symbol) { tick in
            Task {
                let completed = await aggregator.onTick(tick)
                let stamp = formatNow()
                if !completed.isEmpty {
                    for (period, k) in completed {
                        print(String(format: "[%@] 🟢 %@ K 完成 · openTime=%@ open=%@ high=%@ low=%@ close=%@",
                                     stamp, period.rawValue,
                                     formatTime(k.openTime), fmt(k.open), fmt(k.high), fmt(k.low), fmt(k.close)))
                    }
                } else {
                    print(String(format: "[%@] · tick last=%@ vol=%d", stamp, fmt(tick.lastPrice), tick.volume))
                }
            }
        }

        let driver = SinaPollingDriver(provider: provider, interval: 3.0)
        await driver.start()

        let totalSec = 120
        print("✅ 启动 \(periods.count) 周期合成 · \(periods.map { $0.rawValue }.joined(separator: ", "))")
        print("✅ Sina 轮询 3s · 跑 \(totalSec) 秒")
        print("─────────────────────────────────────────────")

        try await Task.sleep(nanoseconds: UInt64(totalSec) * 1_000_000_000)

        await driver.stop()
        await provider.disconnect()

        print("─────────────────────────────────────────────")
        let stats = await aggregator.snapshot()
        print("结果统计（\(totalSec) 秒）：")
        for period in periods {
            let count = stats.completedCount[period] ?? 0
            let bar = stats.currentBar[period]
            let barInfo = bar.map { "当前 K open=\(fmt($0.open)) close=\(fmt($0.close)) vol=\($0.volume)" } ?? "无"
            print("  \(period.rawValue): 完成 \(count) 根 · \(barInfo)")
        }
        print("  Sina 推送 tick 数：\(stats.tickCount)")
        print("─────────────────────────────────────────────")

        let oneMinCompleted = stats.completedCount[.minute1] ?? 0
        if oneMinCompleted >= 1 {
            print("🎉 1m K 跨边界产出 \(oneMinCompleted) 根 · KLineBuilder 真数据合成验证通过")
        } else {
            print("⚠️  1m K 未产出；可能原因：120s 内无 tick / 时间未跨 1m 边界 / 网络异常")
        }
    }

    static func formatNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: date)
    }

    static func fmt(_ d: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal; nf.maximumFractionDigits = 2; nf.minimumFractionDigits = 2
        return nf.string(from: d as NSDecimalNumber) ?? "?"
    }
}

// MARK: - 多周期聚合器（actor 包装多个 KLineBuilder）

/// 同 instrumentID 多周期同步喂 tick · 返回每周期完成的 K 线（如有）
private actor MultiPeriodAggregator {
    private let instrumentID: String
    private var builders: [KLinePeriod: KLineBuilder]
    private var completedCount: [KLinePeriod: Int] = [:]
    private var tickCount = 0

    init(instrumentID: String, periods: [KLinePeriod]) {
        self.instrumentID = instrumentID
        var dict: [KLinePeriod: KLineBuilder] = [:]
        for period in periods {
            dict[period] = KLineBuilder(instrumentID: instrumentID, period: period)
        }
        self.builders = dict
    }

    /// 喂 tick · 返回该 tick 触发的所有"完成 K 线"
    func onTick(_ tick: Tick) -> [(KLinePeriod, KLine)] {
        tickCount += 1
        var completed: [(KLinePeriod, KLine)] = []
        for (period, builder) in builders {
            if let k = builder.onTick(tick) {
                completed.append((period, k))
                completedCount[period, default: 0] += 1
            }
        }
        return completed
    }

    struct Snapshot: Sendable {
        let tickCount: Int
        let completedCount: [KLinePeriod: Int]
        let currentBar: [KLinePeriod: KLine]
    }

    func snapshot() -> Snapshot {
        var current: [KLinePeriod: KLine] = [:]
        for (period, builder) in builders {
            if let bar = builder.currentKLine { current[period] = bar }
        }
        return Snapshot(tickCount: tickCount, completedCount: completedCount, currentBar: current)
    }
}
