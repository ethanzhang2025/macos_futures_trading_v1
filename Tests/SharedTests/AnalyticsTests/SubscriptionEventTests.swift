// WP-133a · subscription_event 入口测试（v15.18 · Stage B IAP 准备）

import Testing
import Foundation
@testable import Shared

@Suite("SubscriptionEvent · 4 类型 + 便利记录")
struct SubscriptionEventTests {

    @Test("4 类型 raw value 对齐 G2 spec（防 typo · 后端 SQL 依赖字符串匹配）")
    func eventTypesStable() {
        #expect(SubscriptionEventType.start.rawValue == "start")
        #expect(SubscriptionEventType.renew.rawValue == "renew")
        #expect(SubscriptionEventType.cancel.rawValue == "cancel")
        #expect(SubscriptionEventType.expire.rawValue == "expire")
        #expect(SubscriptionEventType.allCases.count == 4)
    }

    @Test("recordSubscriptionEvent · properties 含 event_type + sku")
    func recordCarriesFields() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        try await service.recordSubscriptionEvent(
            userID: "u-apple-12345",
            type: .start,
            sku: "com.futuresterminal.pro.monthly"
        )
        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 1)
        #expect(pending[0].eventName == .subscriptionEvent)
        #expect(pending[0].userID == "u-apple-12345")
        #expect(pending[0].properties["event_type"] == "start")
        #expect(pending[0].properties["sku"] == "com.futuresterminal.pro.monthly")
    }

    @Test("4 type 全 e2e 覆盖（防回归）")
    func allTypesRoundtrip() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        for type in SubscriptionEventType.allCases {
            try await service.recordSubscriptionEvent(
                userID: "u",
                type: type,
                sku: "sku.x"
            )
        }
        let pending = try await store.queryPending(limit: 0)
        #expect(pending.count == 4)
        let types = pending.map { $0.properties["event_type"] }
        #expect(Set(types) == Set(["start", "renew", "cancel", "expire"]))
    }

    @Test("setEnabled(false) · subscription_event 同样被丢弃")
    func disabledDropsSubscription() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        await service.setEnabled(false)
        let id = try await service.recordSubscriptionEvent(userID: "u", type: .start, sku: "x")
        #expect(id == nil)
        #expect(try await store.count() == 0)
    }
}
