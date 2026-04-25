// WP-133a · AnalyticsService 高层 API 测试
// 覆盖：record / 隐私开关 / session / 时间注入 / 透传

import Testing
import Foundation
@testable import Shared

@Suite("AnalyticsService · 记录与隐私开关")
struct AnalyticsServiceRecordTests {

    private func makeService(now: Date = Date(timeIntervalSince1970: 1_700_000_000))
        -> (AnalyticsService, InMemoryAnalyticsEventStore) {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(
            store: store,
            deviceID: "device-A",
            appVersion: "1.0.0",
            now: { now }
        )
        return (service, store)
    }

    @Test("默认 enabled · record 成功入库")
    func defaultEnabledWritesEvent() async throws {
        let (service, store) = makeService()
        let id = try await service.record(.appLaunch, userID: "u1")
        #expect(id != nil)
        #expect(try await store.count() == 1)
    }

    @Test("setEnabled(false) · record 直接丢弃返回 nil")
    func disabledDropsEvent() async throws {
        let (service, store) = makeService()
        await service.setEnabled(false)
        let id = try await service.record(.appLaunch, userID: "u1")
        #expect(id == nil)
        #expect(try await store.count() == 0)
    }

    @Test("setEnabled(true) 后恢复记录")
    func reenableResumesRecording() async throws {
        let (service, store) = makeService()
        await service.setEnabled(false)
        _ = try? await service.record(.appLaunch, userID: "u1")
        await service.setEnabled(true)
        _ = try? await service.record(.appLaunch, userID: "u1")
        #expect(try await store.count() == 1)
    }

    @Test("公共字段（device_id / app_version）一次注入 · 每条事件附带")
    func commonFieldsPropagated() async throws {
        let (service, store) = makeService()
        try await service.record(.chartOpen, userID: "u1", properties: ["contract_code": "RB0"])
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].deviceID == "device-A")
        #expect(pending[0].appVersion == "1.0.0")
        #expect(pending[0].properties["contract_code"] == "RB0")
    }

    @Test("时间注入 · eventTimestampMs 由 now 闭包决定")
    func injectedNowControlsTimestamp() async throws {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)  // ms = 1_700_000_000_000
        let (service, store) = makeService(now: fixed)
        try await service.record(.appLaunch, userID: "u1")
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].eventTimestampMs == 1_700_000_000_000)
    }
}

@Suite("AnalyticsService · session 管理")
struct AnalyticsServiceSessionTests {

    @Test("setSession + record · sessionID 携带")
    func sessionAttached() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        await service.setSession("session-X")
        try await service.record(.chartOpen, userID: "u1")
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].sessionID == "session-X")
    }

    @Test("setSession(nil) · 后续事件 sessionID = nil")
    func sessionCleared() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        await service.setSession("X")
        try await service.record(.chartOpen, userID: "u1")
        await service.setSession(nil)
        try await service.record(.chartOpen, userID: "u1")
        let pending = try await store.queryPending(limit: 0)
        #expect(pending[0].sessionID == "X")
        #expect(pending[1].sessionID == nil)
    }

    @Test("currentSession 内省")
    func currentSessionIntrospection() async {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")
        #expect(await service.currentSession() == nil)
        await service.setSession("S1")
        #expect(await service.currentSession() == "S1")
    }
}

@Suite("AnalyticsService · 上报路径透传")
struct AnalyticsServicePassthroughTests {

    @Test("queryPending / markUploaded / cleanup 透传到 store")
    func passthroughToStore() async throws {
        let store = InMemoryAnalyticsEventStore()
        let service = AnalyticsService(store: store, deviceID: "d1", appVersion: "1.0")

        let id1 = try await service.record(.appLaunch, userID: "u1") ?? -1
        let id2 = try await service.record(.appLaunch, userID: "u1") ?? -1

        let pending = try await service.queryPending(limit: 0)
        #expect(pending.count == 2)

        try await service.markUploaded(ids: [id1])
        let remaining = try await service.queryPending(limit: 0)
        #expect(remaining.count == 1)
        #expect(remaining[0].id == id2)
    }
}
