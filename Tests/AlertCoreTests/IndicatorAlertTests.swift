// WP-52 v15.x · 指标条件预警测试
// 覆盖 IndicatorAlertSpec / AlertCondition.indicator Codable + evaluator.onBar 触发逻辑

import Testing
import Foundation
import Shared
@testable import AlertCore

// MARK: - 辅助：K 线工厂

private func makeBar(_ close: Decimal, instrumentID: String = "RB0", period: KLinePeriod = .minute5,
                     openTime: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> KLine {
    KLine(
        instrumentID: instrumentID, period: period, openTime: openTime,
        open: close, high: close, low: close, close: close,
        volume: 0, openInterest: 0, turnover: 0
    )
}

private func makeBars(_ closes: [Decimal], baseTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
                      stepSec: TimeInterval = 300) -> [KLine] {
    closes.enumerated().map { i, c in
        makeBar(c, openTime: baseTime.addingTimeInterval(stepSec * Double(i)))
    }
}

// MARK: - 1. 数据契约 / Codable

@Suite("IndicatorAlertSpec · Codable + 数据契约")
struct IndicatorAlertSpecTests {

    @Test("IndicatorAlertSpec JSON 往返")
    func codableRoundTrip() throws {
        let spec = IndicatorAlertSpec(
            indicator: .macd, params: [12, 26, 9],
            event: .macdGoldenCross, period: .minute15
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(IndicatorAlertSpec.self, from: data)
        #expect(decoded == spec)
    }

    @Test("AlertCondition.indicator Codable 往返")
    func conditionCodable() throws {
        let cond: AlertCondition = .indicator(IndicatorAlertSpec(
            indicator: .rsi, params: [14],
            event: .rsiCrossAbove(70), period: .hour1
        ))
        let data = try JSONEncoder().encode(cond)
        let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
        #expect(decoded == cond)
    }

    @Test("KLinePeriod Codable")
    func klinePeriodCodable() throws {
        let periods: [KLinePeriod] = [.minute1, .minute5, .hour1, .daily]
        let data = try JSONEncoder().encode(periods)
        let decoded = try JSONDecoder().decode([KLinePeriod].self, from: data)
        #expect(decoded == periods)
    }

    @Test("旧 JSON（不含 indicator case）解码兼容")
    func legacyJSONCompat() throws {
        // 模拟 v14.0 末的 alert JSON（仅含 priceAbove）
        let cond: AlertCondition = .priceAbove(3500)
        let data = try JSONEncoder().encode(cond)
        let decoded = try JSONDecoder().decode(AlertCondition.self, from: data)
        #expect(decoded == cond)
    }

    @Test("displayDescription 含指标名 / 周期")
    func displayDescription() {
        let spec = IndicatorAlertSpec(indicator: .ma, params: [20],
                                      event: .priceCrossAboveLine, period: .minute5)
        let desc = spec.displayDescription
        #expect(desc.contains("MA"))
        #expect(desc.contains("5分"))
        #expect(desc.contains("价格上穿"))
    }

    @Test("IndicatorKind.defaultParams · MACD 三参 / RSI 一参")
    func defaultParams() {
        #expect(IndicatorKind.macd.defaultParams == [12, 26, 9])
        #expect(IndicatorKind.rsi.defaultParams == [14])
        #expect(IndicatorKind.ma.defaultParams == [20])
        #expect(IndicatorKind.ema.defaultParams == [12])
    }

    @Test("IndicatorKind.supportedEvents 不重叠")
    func supportedEvents() {
        let maEvents = IndicatorKind.ma.supportedEvents
        let macdEvents = IndicatorKind.macd.supportedEvents
        #expect(maEvents.contains(.priceCrossAboveLine))
        #expect(maEvents.contains(.priceCrossBelowLine))
        #expect(macdEvents.contains(.macdGoldenCross))
        #expect(!maEvents.contains(.macdGoldenCross))
    }
}

// MARK: - 2. evaluator.onBar 评估逻辑

@Suite("AlertEvaluator · onBar 指标条件触发")
struct OnBarEvaluatorTests {

    private func makeAlert(spec: IndicatorAlertSpec, instrumentID: String = "RB0") -> Alert {
        Alert(
            name: "test-\(spec.indicator.rawValue)",
            instrumentID: instrumentID,
            condition: .indicator(spec),
            channels: [],   // 不发通知 · 测试只看 history / event stream
            cooldownSeconds: 0
        )
    }

    @Test("MA 上穿单线 · 价格上穿 MA20 触发")
    func maCrossAbove() async throws {
        // 前 20 根 close=100（bar 19 起 MA 有值 / bar 20 首次 pair 有效进 baseline）· 第 21 根 99 · 第 22 根 110（cross 严格触发）
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(99)
        closes.append(110)
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .ma, params: [20],
                                      event: .priceCrossAboveLine, period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        // 等订阅就绪
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message.contains("价格 110") == true)
    }

    @Test("MA 下穿单线 · 价格下穿 MA20 触发")
    func maCrossBelow() async throws {
        // 前 20 根 close=100（bar 20 首次 pair 进 baseline）· 第 21 根 101（> MA）· 第 22 根 90（cross 严格满足 prev>prevRef && current<currentRef）
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(101)
        closes.append(90)
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .ma, params: [20],
                                      event: .priceCrossBelowLine, period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.count == 1)
        #expect(events.first?.message.contains("下穿") == true)
    }

    @Test("RSI 上穿 70 阈值 触发")
    func rsiCrossAbove() async throws {
        // 前 14 根递增（gain 单边 · RSI → 100）然后保持高位
        // 实际构造：close 序列从 100 单调上升到 113 · RSI 应该升过 70
        var closes: [Decimal] = []
        var price: Decimal = 100
        for _ in 0..<5 {
            closes.append(price)
            price += 1
        }
        // 前 5 根 plateau 让 RSI 起步在 50 附近
        for _ in 0..<5 {
            closes.append(price - 1)
            closes.append(price)
        }
        // 后续单边上升让 RSI 上穿 70
        for _ in 0..<10 {
            price += 2
            closes.append(price)
        }

        let bars = makeBars(closes)
        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .rsi, params: [14],
                                      event: .rsiCrossAbove(70), period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.count >= 1)
        #expect(events.first?.message.contains("RSI") == true)
    }

    @Test("RSI 下穿 30 阈值 触发")
    func rsiCrossBelow() async throws {
        // 单边下降让 RSI 跌破 30
        var closes: [Decimal] = []
        var price: Decimal = 200
        for _ in 0..<5 {
            closes.append(price)
            price -= 1
        }
        for _ in 0..<5 {
            closes.append(price + 1)
            closes.append(price)
        }
        for _ in 0..<10 {
            price -= 2
            closes.append(price)
        }

        let bars = makeBars(closes)
        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .rsi, params: [14],
                                      event: .rsiCrossBelow(30), period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.count >= 1)
    }

    @Test("period 不匹配不触发")
    func periodMismatch() async throws {
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(110)
        // 喂的 K 线是 minute5
        let bars = makeBars(closes, stepSec: 300)

        let evaluator = AlertEvaluator()
        // 但预警绑定 minute1 · 应该完全不触发
        let spec = IndicatorAlertSpec(indicator: .ma, params: [20],
                                      event: .priceCrossAboveLine, period: .minute1)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.isEmpty)
    }

    @Test("instrumentID 不匹配不触发")
    func instrumentMismatch() async throws {
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(110)
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .ma, params: [20],
                                      event: .priceCrossAboveLine, period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec, instrumentID: "AU0"))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        #expect(events.isEmpty)
    }

    @Test("update condition 后 baseline reset · 不立即误触发")
    func updateConditionResetsBaseline() async throws {
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(99)
        closes.append(110)
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        var alert = makeAlert(spec: IndicatorAlertSpec(
            indicator: .ma, params: [20],
            event: .priceCrossAboveLine, period: .minute5
        ))
        await evaluator.addAlert(alert)

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }
        // 至此第 21 根已触发上穿（events.count == 1）

        try? await Task.sleep(nanoseconds: 100_000_000)

        // 改条件为下穿 · 喂同样高位的 K 线 → 不应该立即误触发（baseline 已 reset）
        alert.condition = .indicator(IndicatorAlertSpec(
            indicator: .ma, params: [20],
            event: .priceCrossBelowLine, period: .minute5
        ))
        _ = await evaluator.updateAlert(alert)
        // 喂一根再次 close=110 的 K 线 · 不应该再触发新事件
        let extra = makeBar(110, openTime: bars.last!.openTime.addingTimeInterval(300))
        await evaluator.onBar(extra, instrumentID: "RB0", period: .minute5, now: extra.openTime)

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        // 上穿触发了 1 次 · 改条件后没新触发
        #expect(events.count == 1)
    }

    @Test("baseline 首根不触发（即使数学上 cross 满足）")
    func baselineFirstBarDoesNotTrigger() async throws {
        // 用 MA(3) 让首次 pair 有效时 cross 数学也严格满足 · baseline 路径必须吞掉这次触发
        // closes=[98, 99, 99, 110]：第 3 根 line[2]=98.67 但 line[1]=nil → pair=nil；第 4 根 line[3]=102.67 line[2]=98.67 都有值 → 首次 pair · cross 严格满足 (99<98.67? no)
        // 改用 closes=[101, 100, 100, 110]：line[2]=avg(101,100,100)=100.33, line[3]=avg(100,100,110)=103.33
        //   第 4 根 pair：cur close=110 cur MA=103.33 prev close=100 prev MA=100.33 · cross: 100<100.33(✓) && 110>=103.33(✓) → 数学满足 · 但 baseline 路径吞掉
        let closes: [Decimal] = [101, 100, 100, 110]
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        let spec = IndicatorAlertSpec(indicator: .ma, params: [3],
                                      event: .priceCrossAboveLine, period: .minute5)
        await evaluator.addAlert(makeAlert(spec: spec))

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        // 首次评估即使 cross 数学满足也不触发（baseline 无 previous 比较）
        #expect(events.isEmpty)
    }

    @Test("cooldown 内不重复触发")
    func cooldownPreventsRepeat() async throws {
        // 24 根：100×20（bar 20 baseline）+ 99 + 110（bar 22 上穿触发）+ 95（回踩 cooldown 内）+ 113（bar 24 cross 但 cooldown 仍生效）
        var closes = [Decimal](repeating: 100, count: 20)
        closes.append(99)
        closes.append(110)
        closes.append(95)
        closes.append(113)
        let bars = makeBars(closes)

        let evaluator = AlertEvaluator()
        var a = makeAlert(spec: IndicatorAlertSpec(
            indicator: .ma, params: [20],
            event: .priceCrossAboveLine, period: .minute5
        ))
        a.cooldownSeconds = 900   // 15 分钟冷却 · 大于第二次 cross 距首次 600s 间距
        await evaluator.addAlert(a)

        let collector = EventCollector()
        let task = Task {
            for await event in await evaluator.observe() {
                await collector.add(event)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        for bar in bars {
            await evaluator.onBar(bar, instrumentID: "RB0", period: .minute5, now: bar.openTime)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let events = await collector.snapshot()
        // 第 21 根触发 · 第 23 根因 cooldown 不触发
        #expect(events.count == 1)
    }
}

// MARK: - 辅助：事件收集器

private actor EventCollector {
    private var events: [AlertTriggeredEvent] = []
    func add(_ e: AlertTriggeredEvent) { events.append(e) }
    func snapshot() -> [AlertTriggeredEvent] { events }
}
