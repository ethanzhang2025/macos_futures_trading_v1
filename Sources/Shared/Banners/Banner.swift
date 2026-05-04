// WP-120 · App 内 Banner 推送数据模型（v15.18 · M1-M3 必做）
//
// 设计取舍（D3 §5 M1-M3 预埋）：
// - 后端可下发任意 banner（事故通知 / 公告 / 版本提醒）
// - 客户端持久化已 dismissed 的 id · 避免每次启动都弹同一条
// - level 决定视觉强度（info=蓝 / warning=黄 / critical=红）
// - expiredAt 可选 · 过期 banner 客户端自动隐藏（不依赖后端清理）

import Foundation

/// Banner 视觉层级
public enum BannerLevel: String, Sendable, Codable, CaseIterable {
    case info       = "info"        // 一般公告（蓝）
    case warning    = "warning"     // 警告（黄）· 如版本即将不兼容
    case critical   = "critical"    // 严重（红）· 如事故 / 服务降级
}

/// Banner 数据模型
public struct Banner: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let level: BannerLevel
    public let createdAtMs: Int64
    public let expiredAtMs: Int64?  // nil = 不过期
    /// 后端选填：点击后跳转的 URL（外链）· 客户端不强制处理
    public let actionURL: String?

    public init(
        id: String,
        title: String,
        body: String,
        level: BannerLevel,
        createdAtMs: Int64,
        expiredAtMs: Int64? = nil,
        actionURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.level = level
        self.createdAtMs = createdAtMs
        self.expiredAtMs = expiredAtMs
        self.actionURL = actionURL
    }

    /// 是否已过期（按当前时间）
    public func isExpired(nowMs: Int64) -> Bool {
        guard let exp = expiredAtMs else { return false }
        return nowMs >= exp
    }
}
