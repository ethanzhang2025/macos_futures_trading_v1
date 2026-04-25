// WP-133a · 埋点高层 API
//
// 设计取舍（与 WP-21a / WP-23 哲学一致）：
// - actor 包装 store · 隐私开关单一入口（不散落 if FeatureFlag）
// - now 注入便于测试 · 关闭埋点时事件直接丢弃（不写库）
// - session 3 分钟规则不在本类（UI 层 / 业务层调 setSession 决定；本类只管接收事件）
// - 公共字段（device_id / app_version）一次设置；userID / sessionID 每次传入

import Foundation

public actor AnalyticsService {

    // MARK: - 依赖（构造注入）

    private let store: any AnalyticsEventStore
    private let deviceID: String
    private let appVersion: String
    private let now: @Sendable () -> Date

    // MARK: - 状态

    private var enabled: Bool = true
    private var currentSessionID: String?

    // MARK: - 初始化

    public init(
        store: any AnalyticsEventStore,
        deviceID: String,
        appVersion: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.now = now
    }

    // MARK: - 隐私开关

    /// 启用 / 关闭埋点（StageA-补遗 G2 §隐私：用户可在设置一键关闭）
    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func isEnabled() -> Bool { enabled }

    // MARK: - Session 管理（外部驱动）

    /// 由 UI 层 / 业务层调（如 app_launch 后 / session_start 后 setSession(newID)）
    public func setSession(_ sessionID: String?) {
        currentSessionID = sessionID
    }

    public func currentSession() -> String? { currentSessionID }

    // MARK: - 记录事件

    /// 记录一个事件 · 关闭时直接丢弃（返回 nil）
    /// - Returns: store 赋值的 id；若 enabled=false 则 nil
    @discardableResult
    public func record(
        _ name: AnalyticsEventName,
        userID: String,
        properties: [String: String] = [:]
    ) async throws -> Int64? {
        guard enabled else { return nil }
        let event = AnalyticsEvent(
            userID: userID,
            deviceID: deviceID,
            sessionID: currentSessionID,
            eventName: name,
            eventTimestampMs: AnalyticsEvent.nowMs(now()),
            properties: properties,
            appVersion: appVersion
        )
        return try await store.append(event)
    }

    // MARK: - 上报路径透传（WP-133b 上报 driver 调用）

    public func queryPending(limit: Int = 0) async throws -> [AnalyticsEvent] {
        try await store.queryPending(limit: limit)
    }

    public func markUploaded(ids: [Int64]) async throws {
        try await store.markUploaded(ids: ids)
    }

    @discardableResult
    public func cleanupUploaded(beforeTimestampMs: Int64) async throws -> Int {
        try await store.cleanupUploaded(beforeTimestampMs: beforeTimestampMs)
    }

    // MARK: - 内省（测试用）

    public func storeCount() async throws -> Int {
        try await store.count()
    }
}
