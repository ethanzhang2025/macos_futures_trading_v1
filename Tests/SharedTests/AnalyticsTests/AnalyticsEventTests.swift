// WP-133a · AnalyticsEvent 数据模型测试
// 覆盖：10 事件 enum / Codable / properties JSON / nowMs

import Testing
import Foundation
@testable import Shared

@Suite("AnalyticsEvent · 数据模型")
struct AnalyticsEventTests {

    @Test("10 事件 enum 字符串值与 G2 表对齐")
    func eventNamesAlignWithSpec() {
        let expected: [(AnalyticsEventName, String)] = [
            (.appLaunch, "app_launch"),
            (.sessionStart, "session_start"),
            (.sessionEnd, "session_end"),
            (.chartOpen, "chart_open"),
            (.indicatorAdd, "indicator_add"),
            (.drawingCreate, "drawing_create"),
            (.replayStart, "replay_start"),
            (.alertTrigger, "alert_trigger"),
            (.journalEntrySave, "journal_entry_save"),
            (.subscriptionEvent, "subscription_event")
        ]
        #expect(AnalyticsEventName.allCases.count == 10)
        for (name, raw) in expected {
            #expect(name.rawValue == raw)
        }
    }

    @Test("Codable 往返")
    func codableRoundtrip() throws {
        let event = AnalyticsEvent(
            id: 42, userID: "u1", deviceID: "d1", sessionID: "s1",
            eventName: .chartOpen,
            eventTimestampMs: 1_700_000_000_000,
            properties: ["contract_code": "RB0", "period": "60"],
            appVersion: "1.0.0",
            uploaded: false
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AnalyticsEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test("properties JSON 序列化")
    func propertiesJSON() {
        let event = AnalyticsEvent(
            userID: "u1", deviceID: "d1",
            eventName: .indicatorAdd,
            eventTimestampMs: 0,
            properties: ["indicator_id": "MA"]
        )
        let json = event.propertiesJSON()
        #expect(json.contains("\"indicator_id\""))
        #expect(json.contains("\"MA\""))
    }

    @Test("空 properties → \"{}\"")
    func emptyPropertiesJSON() {
        let event = AnalyticsEvent(
            userID: "u1", deviceID: "d1",
            eventName: .appLaunch, eventTimestampMs: 0
        )
        #expect(event.propertiesJSON() == "{}")
    }

    @Test("nowMs 时间换算")
    func nowMsConversion() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC
        #expect(AnalyticsEvent.nowMs(date) == 1_700_000_000_000)
    }

    @Test("默认值 · uploaded=false / sessionID=nil / properties=[:]")
    func defaultValues() {
        let event = AnalyticsEvent(
            userID: "u1", deviceID: "d1",
            eventName: .appLaunch, eventTimestampMs: 0
        )
        #expect(event.uploaded == false)
        #expect(event.sessionID == nil)
        #expect(event.properties.isEmpty)
        #expect(event.appVersion == "")
    }
}
