// WP-133b · 上报客户端协议（v15.18 · 客户端层闭环）
//
// 设计取舍（与 D2 §WP-133 + StageA-补遗 G2 §上报机制对齐）：
// - 协议先行 · 多实现：StubBatchUploadClient（log only · 后端未就绪占位）
//   未来接 WP-80 后端：HTTPBatchUploadClient（URLSession + JSON 批量 POST + 重试）
// - upload 接受批量 · 一次性传 N 条事件 · 后端 PostgreSQL events 表批量 insert
// - 失败抛错 · driver 层捕获 + 不 markUploaded（下轮 queryPending 自然重试）
// - Sendable · driver 在 actor 中调用 · 无并发陷阱

import Foundation

/// 上报失败错误
public enum BatchUploadError: Error, CustomStringConvertible, Equatable {
    case networkFailed(String)
    case serverRejected(statusCode: Int, message: String)
    case payloadInvalid(String)

    public var description: String {
        switch self {
        case .networkFailed(let m):           return "网络上报失败: \(m)"
        case .serverRejected(let c, let m):   return "后端拒绝 (\(c)): \(m)"
        case .payloadInvalid(let m):          return "payload 无效: \(m)"
        }
    }
}

/// 上报客户端协议
public protocol BatchUploadClient: Sendable {
    /// 批量上报 · 抛错 = 整批失败（driver 不 markUploaded 下轮重试）
    /// 后端语义：N 条事件原子写入 PostgreSQL events 表
    func upload(_ events: [AnalyticsEvent]) async throws
}
