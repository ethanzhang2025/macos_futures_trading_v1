// WP-133a · 埋点事件数据模型
// 锚点：StageA-补遗 G2 / D1 §4 北极星 WAPU
//
// 10 个核心事件（M1 末前落地）+ 公共字段 + 灵活属性 dict
// 持久化时 properties 序列化为 JSON 字符串入 props_json 字段
// 隐私底线：不收集订单内容 / 资金金额 / 持仓明细；用户可在设置一键关闭埋点

import Foundation

/// 10 个核心事件名（参照补遗 G2 表格）
public enum AnalyticsEventName: String, Sendable, Codable, CaseIterable {
    case appLaunch          = "app_launch"
    case sessionStart       = "session_start"
    case sessionEnd         = "session_end"
    case chartOpen          = "chart_open"
    case indicatorAdd       = "indicator_add"
    case drawingCreate      = "drawing_create"
    case replayStart        = "replay_start"
    case alertTrigger       = "alert_trigger"
    case journalEntrySave   = "journal_entry_save"
    case subscriptionEvent  = "subscription_event"
}

/// 一条埋点事件
///
/// SQLite 表 schema 对齐（StageA-补遗 G2 §SQLite 表结构）：
/// ```sql
/// CREATE TABLE events (
///   id INTEGER PRIMARY KEY AUTOINCREMENT,
///   user_id TEXT NOT NULL,
///   device_id TEXT NOT NULL,
///   session_id TEXT,
///   event_name TEXT NOT NULL,
///   event_ts INTEGER NOT NULL,
///   props_json TEXT,
///   app_version TEXT,
///   uploaded INTEGER DEFAULT 0
/// );
/// ```
public struct AnalyticsEvent: Sendable, Codable, Equatable {
    /// 自增 id（持久化层赋值；新建事件传 0 / nil 占位）
    public let id: Int64
    /// 用户 ID（未登录用 device_id 兜底）
    public let userID: String
    /// 设备 ID（持久化在客户端）
    public let deviceID: String
    /// 会话 ID（app_launch 之前可能为 nil）
    public let sessionID: String?
    /// 事件名
    public let eventName: AnalyticsEventName
    /// Unix 毫秒
    public let eventTimestampMs: Int64
    /// 灵活属性（持久化时序列化为 JSON 字符串）
    public let properties: [String: String]
    /// App 版本（兜底空串）
    public let appVersion: String
    /// 是否已上报后端（默认 false · 上报成功后翻 true）
    public let uploaded: Bool

    public init(
        id: Int64 = 0,
        userID: String,
        deviceID: String,
        sessionID: String? = nil,
        eventName: AnalyticsEventName,
        eventTimestampMs: Int64,
        properties: [String: String] = [:],
        appVersion: String = "",
        uploaded: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.deviceID = deviceID
        self.sessionID = sessionID
        self.eventName = eventName
        self.eventTimestampMs = eventTimestampMs
        self.properties = properties
        self.appVersion = appVersion
        self.uploaded = uploaded
    }
}

public extension AnalyticsEvent {
    /// 当前时间（毫秒）
    static func nowMs(_ now: Date = Date()) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000)
    }

    /// properties → JSON 字符串（持久化用）
    /// 失败时返回 "{}"（持久化不应阻断业务流）
    func propertiesJSON() -> String {
        guard let data = try? JSONEncoder().encode(properties),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    /// 返回带新 id 的副本（store append 时赋值用）
    func withID(_ id: Int64) -> AnalyticsEvent {
        AnalyticsEvent(
            id: id, userID: userID, deviceID: deviceID, sessionID: sessionID,
            eventName: eventName, eventTimestampMs: eventTimestampMs,
            properties: properties, appVersion: appVersion, uploaded: uploaded
        )
    }

    /// 返回 uploaded=true 的副本（store markUploaded 时翻位用）
    func markedUploaded() -> AnalyticsEvent {
        AnalyticsEvent(
            id: id, userID: userID, deviceID: deviceID, sessionID: sessionID,
            eventName: eventName, eventTimestampMs: eventTimestampMs,
            properties: properties, appVersion: appVersion, uploaded: true
        )
    }
}
