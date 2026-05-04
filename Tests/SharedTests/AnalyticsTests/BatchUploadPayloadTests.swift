// WP-133b · BatchUploadPayload JSON 编码测试（v15.18）
//
// HTTPBatchUploadClient 的网络部分用集成测试 / mock URLProtocol 验证（macOS 真环境）
// 这里覆盖纯 Codable payload 转换 · 防 schema 漂移破坏后端 contract

import Testing
import Foundation
@testable import Shared

@Suite("BatchUploadPayload · JSON 编码 schema")
struct BatchUploadPayloadTests {

    private func makeEvent(_ name: AnalyticsEventName, ts: Int64 = 1, props: [String: String] = [:]) -> AnalyticsEvent {
        AnalyticsEvent(
            id: 0,
            userID: "u-1",
            deviceID: "d-1",
            sessionID: "s-1",
            eventName: name,
            eventTimestampMs: ts,
            properties: props,
            appVersion: "1.0.0"
        )
    }

    @Test("空事件列表 · 公共字段 fallback 空字符串")
    func emptyEventsFallback() {
        let p = BatchUploadPayload(events: [])
        #expect(p.userID == "")
        #expect(p.deviceID == "")
        #expect(p.appVersion == "")
        #expect(p.events.isEmpty)
    }

    @Test("单条事件 · 公共字段从首条取 · events 1 项")
    func singleEvent() {
        let p = BatchUploadPayload(events: [makeEvent(.appLaunch)])
        #expect(p.userID == "u-1")
        #expect(p.deviceID == "d-1")
        #expect(p.appVersion == "1.0.0")
        #expect(p.events.count == 1)
        #expect(p.events[0].eventName == "app_launch")    // raw value
        #expect(p.events[0].sessionID == "s-1")
        #expect(p.events[0].eventTimestampMs == 1)
    }

    @Test("3 条事件 · properties 透传 · sessionID 各保留")
    func multipleEvents() {
        let p = BatchUploadPayload(events: [
            makeEvent(.chartOpen, ts: 100, props: ["instrument": "RB0", "period": "1分"]),
            makeEvent(.indicatorAdd, ts: 200, props: ["kinds": "MA,BOLL"]),
            makeEvent(.drawingCreate, ts: 300, props: ["drawing_type": "trendLine"])
        ])
        #expect(p.events.count == 3)
        #expect(p.events[0].properties["instrument"] == "RB0")
        #expect(p.events[1].properties["kinds"] == "MA,BOLL")
        #expect(p.events[2].properties["drawing_type"] == "trendLine")
    }

    @Test("Codable round-trip · 编码 + 解码完全等价（防字段名漂移）")
    func codableRoundtrip() throws {
        let original = BatchUploadPayload(events: [
            makeEvent(.sessionStart, ts: 999, props: ["session_id": "abc"])
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatchUploadPayload.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSON 字段名按 Swift 默认（snake_case 不强制 · 后端配合解码）· 防漂移")
    func jsonFieldNamesStable() throws {
        let p = BatchUploadPayload(events: [makeEvent(.appLaunch)])
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        // 验证关键字段名（后端解码 contract）
        #expect(json.contains("\"userID\""))
        #expect(json.contains("\"deviceID\""))
        #expect(json.contains("\"appVersion\""))
        #expect(json.contains("\"eventName\""))
        #expect(json.contains("\"app_launch\""))   // event raw
    }
}
