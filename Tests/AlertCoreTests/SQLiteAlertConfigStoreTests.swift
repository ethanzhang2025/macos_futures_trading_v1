// WP-19a-8 · SQLiteAlertConfigStore 协议合约测试
// 与 SQLiteAlertHistoryStoreTests / WatchlistBookStoreTests 同款模式

import Testing
import Foundation
import Shared
@testable import AlertCore

private func makeStore() throws -> SQLiteAlertConfigStore {
    try SQLiteAlertConfigStore(path: ":memory:")
}

private func makeAlert(
    name: String = "测试预警",
    instrumentID: String = "rb2510",
    condition: AlertCondition = .priceAbove(3500),
    cooldownSeconds: TimeInterval = 60
) -> Alert {
    Alert(
        name: name,
        instrumentID: instrumentID,
        condition: condition,
        cooldownSeconds: cooldownSeconds
    )
}

@Suite("SQLiteAlertConfigStore · 协议合约")
struct SQLiteAlertConfigStoreTests {

    @Test("空 store load → nil")
    func emptyLoadReturnsNil() async throws {
        let store = try makeStore()
        let loaded = try await store.load()
        #expect(loaded == nil)
    }

    @Test("save then load · 数组等价 + 顺序保留")
    func saveThenLoadRoundtrip() async throws {
        let store = try makeStore()
        let a1 = makeAlert(name: "a1", condition: .priceAbove(3500))
        let a2 = makeAlert(name: "a2", instrumentID: "ag2510", condition: .priceBelow(7000))
        let a3 = makeAlert(name: "a3", condition: .priceCrossAbove(3600))
        let alerts = [a1, a2, a3]

        try await store.save(alerts)
        let loaded = try await store.load()

        #expect(loaded == alerts)  // Alert: Equatable
        #expect(loaded?.map(\.name) == ["a1", "a2", "a3"])
    }

    @Test("save 后再 save · 后写覆盖")
    func secondSaveOverridesFirst() async throws {
        let store = try makeStore()
        try await store.save([makeAlert(name: "old1"), makeAlert(name: "old2")])
        try await store.save([makeAlert(name: "new")])

        let loaded = try await store.load()
        #expect(loaded?.count == 1)
        #expect(loaded?.first?.name == "new")
    }

    @Test("clear 后 load → nil")
    func clearRemovesData() async throws {
        let store = try makeStore()
        try await store.save([makeAlert()])
        try await store.clear()

        #expect(try await store.load() == nil)
    }

    @Test("save 空数组 · load 返回空数组（与 nil 区分）")
    func emptyArrayPersistsAsEmptyNotNil() async throws {
        let store = try makeStore()
        try await store.save([])
        let loaded = try await store.load()
        #expect(loaded != nil)
        #expect(loaded?.isEmpty == true)
    }

    @Test("AlertCondition 5 种 JSON 往返")
    func conditionRoundtrip() async throws {
        let store = try makeStore()
        let drawingID = UUID()
        let conditions: [AlertCondition] = [
            .priceAbove(3500),
            .priceCrossBelow(3200.5),
            .volumeSpike(multiple: 3, windowBars: 20),
            .priceMoveSpike(percentThreshold: 1.5, windowSeconds: 300),
            .horizontalLineTouched(drawingID: drawingID, price: 3500)
        ]
        let alerts = conditions.enumerated().map { i, c in
            makeAlert(name: "c\(i)", condition: c)
        }
        try await store.save(alerts)
        let loaded = try await store.load()

        #expect(loaded?.count == 5)
        #expect(loaded?.map(\.condition) == conditions)
    }

    @Test("Alert 全字段保真（status / channels / cooldown / lastTriggeredAt）")
    func fullFieldFidelity() async throws {
        let store = try makeStore()
        let triggeredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let alert = Alert(
            name: "完整字段",
            instrumentID: "rb2510",
            condition: .priceAbove(3500),
            status: .paused,
            channels: [.inApp, .systemNotice, .file],
            cooldownSeconds: 120,
            createdAt: Date(timeIntervalSince1970: 1_699_900_000),
            lastTriggeredAt: triggeredAt
        )
        try await store.save([alert])
        let loaded = try await store.load()

        #expect(loaded?.first == alert)  // Alert: Equatable
        #expect(loaded?.first?.status == .paused)
        #expect(loaded?.first?.channels.count == 3)
        #expect(loaded?.first?.cooldownSeconds == 120)
        #expect(loaded?.first?.lastTriggeredAt == triggeredAt)
    }
}
