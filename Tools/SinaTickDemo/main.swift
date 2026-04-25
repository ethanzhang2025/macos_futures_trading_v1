// WP-31a · Sina 真网络验证 demo
//
// 用途：
// - 验证 SinaMarketData → SinaMarketDataProvider → handler 整条链路在真网络下工作
// - 跑 30 秒，4 个核心合约（螺纹钢 / 沪深300 / 黄金 / 铜）；每 3 秒一次
// - 退出时打印统计：每合约 tick 数 / 状态机 final state
//
// 运行：swift run SinaTickDemo
//
// 注意：
// - 国内期货交易时段：日盘 9:00-15:00 / 夜盘 21:00-02:30；非交易时段也能拉到但数据停滞
// - 第三方软件直连 Sina 是免费且无合规风险（与 CTP 不同）

import Foundation
import Shared
import DataCore

@main
struct SinaTickDemo {

    static func main() async throws {
        print("─────────────────────────────────────────────")
        print("WP-31a · Sina 行情真网络验证 demo")
        print("─────────────────────────────────────────────")

        let symbols = ["RB0", "IF0", "AU0", "CU0"]
        let symbolNames: [String: String] = [
            "RB0": "螺纹钢", "IF0": "沪深300", "AU0": "黄金", "CU0": "铜"
        ]

        let fetcher = SinaMarketData()
        let provider = SinaMarketDataProvider(fetcher: fetcher)
        let counter = TickCounter()

        await provider.connect()
        print("provider state = connected")

        for symbol in symbols {
            await provider.subscribe(symbol) { tick in
                let name = symbolNames[tick.instrumentID] ?? "?"
                print(String(format: "[%@] %@ %@ last=%@ bid/ask=%@/%@ vol=%d",
                             tick.updateTime,
                             tick.instrumentID,
                             name,
                             tick.lastPrice.description,
                             tick.bidPrices.first?.description ?? "0",
                             tick.askPrices.first?.description ?? "0",
                             tick.volume))
                Task { await counter.tally(tick.instrumentID) }
            }
        }
        print("已订阅 \(symbols.count) 合约：\(symbols.joined(separator: ", "))")
        print("─────────────────────────────────────────────")

        let driver = SinaPollingDriver(provider: provider, interval: 3.0)
        await driver.start()

        // 跑 30 秒
        try await Task.sleep(nanoseconds: 30 * 1_000_000_000)

        await driver.stop()
        await provider.disconnect()

        let stats = await counter.snapshot()
        print("─────────────────────────────────────────────")
        print("结果统计（30 秒 / 3 秒间隔 ≈ 10 次轮询）：")
        for symbol in symbols {
            let count = stats[symbol] ?? 0
            let name = symbolNames[symbol] ?? "?"
            print("  \(symbol) \(name): \(count) tick")
        }
        let total = stats.values.reduce(0, +)
        print("  总计：\(total) tick")
        print("─────────────────────────────────────────────")

        if total == 0 {
            print("⚠️  未收到任何 tick；可能原因：")
            print("    1. 网络无法访问 hq.sinajs.cn / stock.finance.sina.com.cn")
            print("    2. 当前为交易日夜盘 + 日盘的间歇空档（数据停滞但 HTTP 仍可拉）")
            print("    3. Sina 接口字段格式变更（解析失败）")
        }
    }
}

/// Tick 计数器（按合约分桶）
private actor TickCounter {
    private var counts: [String: Int] = [:]
    func tally(_ instrumentID: String) {
        counts[instrumentID, default: 0] += 1
    }
    func snapshot() -> [String: Int] { counts }
}
