// WP-133a · 订阅事件类型 + 便利记录方法（v15.18 · Stage B IAP 准备）
//
// 设计取舍：
// - StageA-补遗 G2 #10 subscription_event 字段：user_id / event_type / sku
// - Stage A 暂无 IAP · 此处仅骨架 + 类型安全 enum · Stage B WP-91 IAP 接入时直接调用
// - event_type 4 类与 D2 §2 Stage B 对齐：start（首次订阅）/ renew（续订）/ cancel（用户取消）/ expire（被动到期）
// - sku 字段：Apple IAP product identifier（如 "com.futuresterminal.pro.monthly"）

import Foundation

/// 订阅事件类型（StageA-补遗 G2 #10）
public enum SubscriptionEventType: String, Sendable, Codable, CaseIterable {
    case start    = "start"     // 首次订阅成功
    case renew    = "renew"     // 自动续订成功
    case cancel   = "cancel"    // 用户主动取消（仍在有效期）
    case expire   = "expire"    // 订阅到期（未续订）
}

public extension AnalyticsService {

    /// 记录订阅事件（Stage B WP-91 IAP 接入时调用）
    /// - Returns: store 赋值的 id；若 enabled=false 则 nil
    @discardableResult
    func recordSubscriptionEvent(
        userID: String,
        type: SubscriptionEventType,
        sku: String
    ) async throws -> Int64? {
        try await record(
            .subscriptionEvent,
            userID: userID,
            properties: [
                "event_type": type.rawValue,
                "sku": sku
            ]
        )
    }
}
