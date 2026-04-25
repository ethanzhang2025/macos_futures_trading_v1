// WP-52 · 条件预警中心测试
// Alert 数据 / AlertHistoryStore / NotificationChannel + Dispatcher / AlertEvaluator 6 类触发 + 频控

import Testing
import Foundation
import Shared
@testable import AlertCore

// MARK: - 测试辅助

private func makeTick(_ instrumentID: String, price: Decimal, volume: Int = 0, time: Date = Date()) -> Tick {
    Tick(
        instrumentID: instrumentID,
        lastPrice: price, volume: volume, openInterest: 0, turnover: 0,
        bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
        highestPrice: 0, lowestPrice: 0, openPrice: 0,
        preClosePrice: 0, preSettlementPrice: 0,
        upperLimitPrice: 0, lowerLimitPrice: 0,
        updateTime: "00:00:00", updateMillisec: 0,
        tradingDay: "20260425", actionDay: "20260425"
    )
}

private actor LoggerCapture {
    private(set) var lines: [String] = []
    func add(_ s: String) { lines.append(s) }
    func count() -> Int { lines.count }
    func snapshot() -> [String] { lines }
}

// MARK: - 1. Alert 数据契约

@Suite("Alert · 数据契约 + canTrigger")
struct AlertDataTests {

    @Test("默认值")
    func defaults() {
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500))
        #expect(a.status == .active)
        #expect(a.channels == [.inApp, .systemNotice])
        #expect(a.cooldownSeconds == 60)
        #expect(a.lastTriggeredAt == nil)
    }

    @Test("canTrigger：active + 无 lastTriggered → true")
    func canTriggerInitial() {
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500))
        #expect(a.canTrigger())
    }

    @Test("canTrigger：paused → false")
    func canTriggerPaused() {
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500), status: .paused)
        #expect(!a.canTrigger())
    }

    @Test("canTrigger：cooldown 内 → false / 冷却结束 → true")
    func canTriggerCooldown() {
        let now = Date()
        let a = Alert(
            name: "t", instrumentID: "rb2510", condition: .priceAbove(3500),
            cooldownSeconds: 60, lastTriggeredAt: now
        )
        #expect(!a.canTrigger(at: now.addingTimeInterval(30)))
        #expect(a.canTrigger(at: now.addingTimeInterval(60)))
    }

    @Test("Codable JSON 往返")
    func codableRoundTrip() throws {
        // 用整秒 Date 避免 iso8601 亚秒精度丢失
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Alert(
            name: "螺纹突破", instrumentID: "rb2510",
            condition: .priceCrossAbove(3500), createdAt: createdAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(a)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Alert.self, from: data)
        #expect(decoded == a)
    }
}

// MARK: - 2. AlertHistoryStore

@Suite("InMemoryAlertHistoryStore")
struct AlertHistoryTests {

    private func makeEntry(alertID: UUID, time: Date) -> AlertHistoryEntry {
        AlertHistoryEntry(
            alertID: alertID, alertName: "t", instrumentID: "rb2510",
            conditionSnapshot: .priceAbove(3500),
            triggeredAt: time, triggerPrice: 3500, message: "msg"
        )
    }

    @Test("append + history(forAlertID:) 按 triggeredAt 降序")
    func appendAndSort() async throws {
        let store = InMemoryAlertHistoryStore()
        let aID = UUID()
        let t1 = Date()
        let t2 = t1.addingTimeInterval(60)

        try await store.append(makeEntry(alertID: aID, time: t1))
        try await store.append(makeEntry(alertID: aID, time: t2))

        let result = try await store.history(forAlertID: aID)
        #expect(result.count == 2)
        #expect(result[0].triggeredAt == t2)  // 最近在前
        #expect(result[1].triggeredAt == t1)
    }

    @Test("clear(alertID:) 仅清指定 alert")
    func clearOne() async throws {
        let store = InMemoryAlertHistoryStore()
        let a1 = UUID()
        let a2 = UUID()
        try await store.append(makeEntry(alertID: a1, time: Date()))
        try await store.append(makeEntry(alertID: a2, time: Date()))

        try await store.clear(alertID: a1)
        #expect(try await store.history(forAlertID: a1).isEmpty)
        #expect(try await store.history(forAlertID: a2).count == 1)
    }

    @Test("clearAll 清全部")
    func clearAll() async throws {
        let store = InMemoryAlertHistoryStore()
        try await store.append(makeEntry(alertID: UUID(), time: Date()))
        try await store.clearAll()
        #expect(try await store.allHistory().isEmpty)
    }
}

// MARK: - 3. NotificationChannel + Dispatcher

@Suite("NotificationChannel + Dispatcher")
struct NotificationLayerTests {

    @Test("LoggingNotificationChannel 调用 logger 一次")
    func loggingChannelCalls() async {
        let capture = LoggerCapture()
        let channel = LoggingNotificationChannel(kind: .inApp) { line in
            Task { await capture.add(line) }
        }
        let event = NotificationEvent(
            alertID: UUID(), alertName: "t", instrumentID: "rb2510",
            triggerPrice: 3500, triggeredAt: Date(), message: "m"
        )
        await channel.send(event)
        for _ in 0..<5 { await Task.yield() }
        #expect(await capture.count() == 1)
    }

    @Test("Dispatcher 注册多 channel + 选择性广播")
    func dispatcherSelective() async {
        let capInApp = LoggerCapture()
        let capSound = LoggerCapture()
        let channelInApp = LoggingNotificationChannel(kind: .inApp) { line in
            Task { await capInApp.add(line) }
        }
        let channelSound = LoggingNotificationChannel(kind: .sound) { line in
            Task { await capSound.add(line) }
        }
        let dispatcher = NotificationDispatcher(channels: [channelInApp, channelSound])
        #expect(await dispatcher.registeredKinds() == [.inApp, .sound])

        let event = NotificationEvent(
            alertID: UUID(), alertName: "t", instrumentID: "rb2510",
            triggerPrice: 3500, triggeredAt: Date(), message: "m"
        )

        // 仅广播到 inApp
        await dispatcher.dispatch(event, to: [.inApp])
        for _ in 0..<5 { await Task.yield() }
        #expect(await capInApp.count() == 1)
        #expect(await capSound.count() == 0)

        // 广播到 inApp + sound
        await dispatcher.dispatch(event, to: [.inApp, .sound])
        for _ in 0..<5 { await Task.yield() }
        #expect(await capInApp.count() == 2)
        #expect(await capSound.count() == 1)
    }

    @Test("Dispatcher unregister 后不再发")
    func dispatcherUnregister() async {
        let cap = LoggerCapture()
        let channel = LoggingNotificationChannel(kind: .inApp) { line in
            Task { await cap.add(line) }
        }
        let dispatcher = NotificationDispatcher(channels: [channel])
        await dispatcher.unregister(.inApp)
        let event = NotificationEvent(
            alertID: UUID(), alertName: "t", instrumentID: "rb2510",
            triggerPrice: 0, triggeredAt: Date(), message: ""
        )
        await dispatcher.dispatch(event, to: [.inApp])
        for _ in 0..<5 { await Task.yield() }
        #expect(await cap.count() == 0)
    }
}

// MARK: - 4. AlertEvaluator · CRUD

@Suite("AlertEvaluator · CRUD")
struct EvaluatorCRUDTests {

    @Test("addAlert / removeAlert / updateAlert")
    func crudBasics() async {
        let evaluator = AlertEvaluator()
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500))
        await evaluator.addAlert(a)
        #expect(await evaluator.allAlerts().count == 1)

        // updateAlert 保留 lastTriggeredAt
        let now = Date()
        var updated = a
        updated.name = "renamed"
        updated.lastTriggeredAt = nil  // 故意置空，evaluator 应保留原值（这里原也是 nil，做更严格的测试见下）
        let r = await evaluator.updateAlert(updated)
        #expect(r)
        #expect(await evaluator.allAlerts().first?.name == "renamed")

        await evaluator.removeAlert(id: a.id)
        #expect(await evaluator.allAlerts().isEmpty)
        _ = now
    }

    @Test("updateAlert 保留原 lastTriggeredAt（caller 不能误清频控）")
    func updateKeepsLastTriggered() async {
        let evaluator = AlertEvaluator()
        let then = Date().addingTimeInterval(-100)
        let original = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500), lastTriggeredAt: then)
        await evaluator.addAlert(original)

        var changed = original
        changed.name = "改"
        changed.lastTriggeredAt = nil  // 用户从 UI 编辑时不传 lastTriggeredAt
        let _ = await evaluator.updateAlert(changed)
        #expect(await evaluator.allAlerts().first?.lastTriggeredAt == then)
    }

    @Test("pauseAlert / resumeAlert 状态转移")
    func pauseResume() async {
        let evaluator = AlertEvaluator()
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500))
        await evaluator.addAlert(a)

        let paused = await evaluator.pauseAlert(id: a.id)
        #expect(paused)
        #expect(await evaluator.allAlerts().first?.status == .paused)

        let resumed = await evaluator.resumeAlert(id: a.id)
        #expect(resumed)
        #expect(await evaluator.allAlerts().first?.status == .active)
    }

    @Test("resumeAlert 仅 paused 可恢复")
    func resumeOnlyFromPaused() async {
        let evaluator = AlertEvaluator()
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500), status: .cancelled)
        await evaluator.addAlert(a)
        let r = await evaluator.resumeAlert(id: a.id)
        #expect(!r)
        #expect(await evaluator.allAlerts().first?.status == .cancelled)
    }
}

// MARK: - 5. AlertEvaluator · 价格类触发

@Suite("AlertEvaluator · 价格类触发")
struct EvaluatorPriceTests {

    @Test("priceAbove：>= target 时触发")
    func priceAbove() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "突破 3500", instrumentID: "rb2510",
            condition: .priceAbove(3500), channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        await evaluator.onTick(makeTick("rb2510", price: 3499))
        #expect(try await history.allHistory().isEmpty)

        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().count == 1)
    }

    @Test("priceCrossAbove：边界不重复触发（prev + current 两点判定）")
    func crossAboveBoundary() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "上穿 3500", instrumentID: "rb2510",
            condition: .priceCrossAbove(3500), channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        // 第一次推送，无 prev → 不触发
        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().isEmpty)

        // prev=3500, current=3500 → 不触发（不是上穿，已在线上）
        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().isEmpty)

        // prev=3500, current=3499 → 不触发
        await evaluator.onTick(makeTick("rb2510", price: 3499))
        #expect(try await history.allHistory().isEmpty)

        // prev=3499, current=3500 → 触发（真正上穿）
        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().count == 1)
    }

    @Test("priceCrossBelow：边界不重复触发")
    func crossBelowBoundary() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "下穿 3500", instrumentID: "rb2510",
            condition: .priceCrossBelow(3500), channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        await evaluator.onTick(makeTick("rb2510", price: 3501))
        await evaluator.onTick(makeTick("rb2510", price: 3500))  // prev>target, current<=target → 触发
        #expect(try await history.allHistory().count == 1)

        // prev=3500, current=3499 → 不再触发（prev 不大于 target）
        await evaluator.onTick(makeTick("rb2510", price: 3499))
        #expect(try await history.allHistory().count == 1)
    }

    @Test("horizontalLineTouched：上穿或下穿都触发")
    func horizontalTouchedBothDirections() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let drawingID = UUID()
        let a = Alert(
            name: "触水平线", instrumentID: "rb2510",
            condition: .horizontalLineTouched(drawingID: drawingID, price: 3500),
            channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        await evaluator.onTick(makeTick("rb2510", price: 3499))
        await evaluator.onTick(makeTick("rb2510", price: 3500))  // 上穿 → 触发
        #expect(try await history.allHistory().count == 1)

        await evaluator.onTick(makeTick("rb2510", price: 3501))
        await evaluator.onTick(makeTick("rb2510", price: 3500))  // 下穿 → 再触发
        #expect(try await history.allHistory().count == 2)
    }
}

// MARK: - 6. AlertEvaluator · 频控

@Suite("AlertEvaluator · 频控冷却（A08 验收硬要求）")
struct EvaluatorCooldownTests {

    @Test("cooldown 内不重复触发；冷却结束后重触")
    func cooldownPreventsRapidFire() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "持续高于", instrumentID: "rb2510",
            condition: .priceAbove(3500), channels: [], cooldownSeconds: 60
        )
        await evaluator.addAlert(a)

        let baseTime = Date()
        await evaluator.onTick(makeTick("rb2510", price: 3500), now: baseTime)
        await evaluator.onTick(makeTick("rb2510", price: 3501), now: baseTime.addingTimeInterval(10))
        await evaluator.onTick(makeTick("rb2510", price: 3502), now: baseTime.addingTimeInterval(30))
        #expect(try await history.allHistory().count == 1)  // cooldown 内仅 1 次

        // 60s 后再触
        await evaluator.onTick(makeTick("rb2510", price: 3503), now: baseTime.addingTimeInterval(61))
        #expect(try await history.allHistory().count == 2)
    }

    @Test("cooldownSeconds=0 → 每次满足都触发")
    func zeroCooldownAlwaysTriggers() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "无冷却", instrumentID: "rb2510",
            condition: .priceAbove(3500), channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        for _ in 0..<5 {
            await evaluator.onTick(makeTick("rb2510", price: 3500))
        }
        #expect(try await history.allHistory().count == 5)
    }
}

// MARK: - 7. AlertEvaluator · 异常类触发

@Suite("AlertEvaluator · 异常类触发")
struct EvaluatorAnomalyTests {

    @Test("volumeSpike：当前 vol 是近 N 期均值的 multiple 倍以上")
    func volumeSpike() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "放量", instrumentID: "rb2510",
            condition: .volumeSpike(multiple: 3, windowBars: 5),
            channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        // 喂 5 期均值 100 的成交量
        for _ in 0..<5 {
            await evaluator.onTick(makeTick("rb2510", price: 3500, volume: 100))
        }
        #expect(try await history.allHistory().isEmpty)  // 自身均值无突变

        // 第 6 个 tick volume=400 → 是均值 100 的 4 倍 → 触发
        await evaluator.onTick(makeTick("rb2510", price: 3500, volume: 400))
        #expect(try await history.allHistory().count == 1)
    }

    @Test("priceMoveSpike：windowSeconds 内变化超阈值触发")
    func priceMoveSpike() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(
            name: "急涨 1%", instrumentID: "rb2510",
            condition: .priceMoveSpike(percentThreshold: 0.01, windowSeconds: 60),
            channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a)

        let baseTime = Date()
        await evaluator.onTick(makeTick("rb2510", price: 3500), now: baseTime)
        // 30s 内涨 0.5% → 不触发
        await evaluator.onTick(makeTick("rb2510", price: 3517), now: baseTime.addingTimeInterval(30))
        #expect(try await history.allHistory().isEmpty)

        // 60s 内涨 1.2% → 触发
        await evaluator.onTick(makeTick("rb2510", price: 3542), now: baseTime.addingTimeInterval(50))
        #expect(try await history.allHistory().count == 1)
    }
}

// MARK: - 8. AlertEvaluator · 多 alert / 多 instrument 隔离

@Suite("AlertEvaluator · 多 alert 隔离")
struct EvaluatorIsolationTests {

    @Test("多 alert 同合约：各自独立触发")
    func multipleAlertsSameInstrument() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a1 = Alert(name: "高于 3500", instrumentID: "rb2510", condition: .priceAbove(3500), channels: [], cooldownSeconds: 0)
        let a2 = Alert(name: "高于 3600", instrumentID: "rb2510", condition: .priceAbove(3600), channels: [], cooldownSeconds: 0)
        await evaluator.addAlert(a1)
        await evaluator.addAlert(a2)

        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().count == 1)  // 仅 a1

        await evaluator.onTick(makeTick("rb2510", price: 3600))
        #expect(try await history.allHistory().count == 3)  // a1 又触发 + a2 触发
    }

    @Test("多合约：rb 推 rb，hc 推 hc，互不串线")
    func multipleInstruments() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let aRB = Alert(name: "RB", instrumentID: "rb2510", condition: .priceAbove(3500), channels: [], cooldownSeconds: 0)
        let aHC = Alert(name: "HC", instrumentID: "hc2510", condition: .priceAbove(3000), channels: [], cooldownSeconds: 0)
        await evaluator.addAlert(aRB)
        await evaluator.addAlert(aHC)

        await evaluator.onTick(makeTick("rb2510", price: 3500))
        let h1 = try await history.allHistory()
        #expect(h1.count == 1)
        #expect(h1[0].alertName == "RB")

        await evaluator.onTick(makeTick("hc2510", price: 3000))
        let h2 = try await history.allHistory()
        #expect(h2.count == 2)
    }

    @Test("removeAlert 联动清 history")
    func removeClearsHistory() async throws {
        let history = InMemoryAlertHistoryStore()
        let evaluator = AlertEvaluator(history: history)
        let a = Alert(name: "t", instrumentID: "rb2510", condition: .priceAbove(3500), channels: [], cooldownSeconds: 0)
        await evaluator.addAlert(a)
        await evaluator.onTick(makeTick("rb2510", price: 3500))
        #expect(try await history.allHistory().count == 1)

        await evaluator.removeAlert(id: a.id)
        #expect(try await history.allHistory().isEmpty)
    }
}

// MARK: - 9. AlertEvaluator · NotificationDispatcher 联动

@Suite("AlertEvaluator · 通知 dispatcher 联动")
struct EvaluatorNotificationTests {

    @Test("触发时按 Alert.channels 选择性通知 + 空 channels 不通知")
    func selectiveDispatch() async {
        let cap = LoggerCapture()
        let dispatcher = NotificationDispatcher(channels: [
            LoggingNotificationChannel(kind: .inApp) { line in Task { await cap.add(line) } }
        ])
        let evaluator = AlertEvaluator(dispatcher: dispatcher)

        // alert 1：channels = [.inApp] → 应触发通知
        let a1 = Alert(
            name: "with channel", instrumentID: "rb2510", condition: .priceAbove(3500),
            channels: [.inApp], cooldownSeconds: 0
        )
        // alert 2：channels = [] → 不通知（仅写 history）
        let a2 = Alert(
            name: "no channel", instrumentID: "hc2510", condition: .priceAbove(3000),
            channels: [], cooldownSeconds: 0
        )
        await evaluator.addAlert(a1)
        await evaluator.addAlert(a2)

        await evaluator.onTick(makeTick("rb2510", price: 3500))
        await evaluator.onTick(makeTick("hc2510", price: 3000))
        for _ in 0..<10 { await Task.yield() }

        #expect(await cap.count() == 1)  // 仅 a1 触发了通知
    }
}
