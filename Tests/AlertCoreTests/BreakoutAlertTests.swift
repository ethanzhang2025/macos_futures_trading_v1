// WP-52 v15.19+ batch16 · Donchian 突破预警测试
// 覆盖 AlertCondition.priceBreakoutHigh / priceBreakoutLow + evaluator.onBar 触发逻辑

import Testing
import Foundation
import Shared
@testable import AlertCore

// MARK: - 辅助：K 线工厂（含 high/low 显式设置 · 区别于 IndicatorAlertTests 中 OHLC 同价）

private func bar(_ open: Decimal, _ high: Decimal, _ low: Decimal, _ close: Decimal,
                 instrumentID: String = "RB0", period: KLinePeriod = .minute15,
                 openTime: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> KLine {
    KLine(
        instrumentID: instrumentID, period: period, openTime: openTime,
        open: open, high: high, low: low, close: close,
        volume: 0, openInterest: 0, turnover: 0
    )
}

private func barsAt(_ ohlcs: [(Decimal, Decimal, Decimal, Decimal)],
                    baseTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
                    stepSec: TimeInterval = 900) -> [KLine] {
    ohlcs.enumerated().map { i, x in
        bar(x.0, x.1, x.2, x.3, openTime: baseTime.addingTimeInterval(stepSec * Double(i)))
    }
}

@Suite("Donchian 突破预警 · v15.19+ batch16")
struct BreakoutAlertTests {

    private func makeBreakoutHighAlert(period: KLinePeriod = .minute15, lookback: Int = 5,
                                        instrumentID: String = "RB0") -> Alert {
        Alert(
            name: "突破前 \(lookback) 根高",
            instrumentID: instrumentID,
            condition: .priceBreakoutHigh(period: period, lookback: lookback),
            channels: [],
            cooldownSeconds: 0
        )
    }

    private func makeBreakoutLowAlert(period: KLinePeriod = .minute15, lookback: Int = 5,
                                       instrumentID: String = "RB0") -> Alert {
        Alert(
            name: "跌破前 \(lookback) 根低",
            instrumentID: instrumentID,
            condition: .priceBreakoutLow(period: period, lookback: lookback),
            channels: [],
            cooldownSeconds: 0
        )
    }

    @Test("priceBreakoutHigh · close 突破前 N 根 high 最大值 → 触发")
    func breakoutHighFires() async throws {
        // 前 5 根 high = 100,101,102,103,104（max=104）· 第 6 根 close=110 > 104 → 触发
        let bars = barsAt([
            (100, 100, 99, 100),
            (100, 101, 99, 100),
            (100, 102, 99, 101),
            (100, 103, 99, 102),
            (100, 104, 99, 103),
            (105, 111, 105, 110)   // close=110 突破前 5 根 high max=104
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutHighAlert(lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute15, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message.contains("突破前 5 根") == true)
    }

    @Test("priceBreakoutHigh · close 未越过 → 不触发")
    func breakoutHighNoTrigger() async throws {
        // 前 5 根 high max=104 · 第 6 根 close=104（等于不算突破 · close > priorMax 严格大于）
        let bars = barsAt([
            (100, 100, 99, 100),
            (100, 101, 99, 100),
            (100, 102, 99, 101),
            (100, 103, 99, 102),
            (100, 104, 99, 103),
            (104, 104, 103, 104)
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutHighAlert(lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute15, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.isEmpty)
    }

    @Test("priceBreakoutLow · close 跌破前 N 根 low 最小值 → 触发")
    func breakoutLowFires() async throws {
        // 前 5 根 low = 100,99,98,97,96（min=96）· 第 6 根 close=90 < 96 → 触发
        let bars = barsAt([
            (101, 102, 100, 101),
            (101, 102, 99, 100),
            (101, 102, 98, 100),
            (101, 102, 97, 100),
            (101, 102, 96, 100),
            (95, 95, 89, 90)
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutLowAlert(lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute15, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message.contains("跌破前 5 根") == true)
    }

    @Test("lookback 不足时不触发（窗口短于 lookback+1）")
    func insufficientWindow() async throws {
        // 仅 3 根 · lookback 5 → 永不触发
        let bars = barsAt([
            (100, 100, 99, 100),
            (100, 101, 99, 100),
            (100, 200, 99, 200)   // 即使大涨 · 窗口不够 5 根历史 · 不触发
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutHighAlert(lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute15, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.isEmpty)
    }

    @Test("period 不匹配时不触发（不同周期 onBar 来 · 跳过评估）")
    func periodMismatch() async throws {
        // alert 监 minute15 · 数据用 minute5 喂 · 不应触发
        let bars = barsAt([
            (100, 100, 99, 100),
            (100, 101, 99, 100),
            (100, 102, 99, 101),
            (100, 103, 99, 102),
            (100, 104, 99, 103),
            (105, 111, 105, 110)
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutHighAlert(period: .minute15, lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            // 注入 minute5 周期 · alert 是 minute15 · 应跳过
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute5, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.isEmpty)
    }

    @Test("AlertCondition.priceBreakoutHigh Codable 往返")
    func breakoutCodable() throws {
        let cond: AlertCondition = .priceBreakoutHigh(period: .daily, lookback: 20)
        let data = try JSONEncoder().encode(cond)
        let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
        #expect(decoded == cond)
    }

    @Test("priceBreakoutHigh + priceBreakoutLow 都注册 · 同周期 · 一根 bar 两侧不会双触发")
    func bothSides() async throws {
        // 前 5 根 high max=104, low min=96 · 第 6 根 close=110 > 104 触发 high · 但 close=110 不 < 96 · low 不触发
        let bars = barsAt([
            (101, 100, 99, 100),
            (101, 101, 99, 100),
            (101, 102, 98, 100),
            (101, 103, 97, 100),
            (101, 104, 96, 100),
            (105, 111, 105, 110)
        ])
        let evaluator = AlertEvaluator()
        await evaluator.addAlert(makeBreakoutHighAlert(lookback: 5))
        await evaluator.addAlert(makeBreakoutLowAlert(lookback: 5))
        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        for b in bars {
            await evaluator.onBar(b, instrumentID: "RB0", period: .minute15, now: b.openTime)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let events = await collector.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message.contains("突破") == true)
    }
}

// MARK: - 辅助：事件收集器（与 IndicatorAlertTests 共用 actor pattern · 但 IndicatorAlertTests 内是 private actor · 这里独立定义）

private actor EventCollector {
    private var events: [AlertTriggeredEvent] = []
    func add(_ e: AlertTriggeredEvent) { events.append(e) }
    func snapshot() -> [AlertTriggeredEvent] { events }
}
