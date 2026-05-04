// WP-120 · Banner 来源协议 + Stub 实现（v15.18）
//
// 设计取舍：
// - 协议 + 多实现：StubBannerSource（hardcoded list · 后端未就绪占位）
//   未来接 WP-80 后端：HTTPBannerSource（URLSession + JSON list）
// - fetch 抛错时 BannerService 静默 fallback 缓存（不阻塞 UI）
// - 后端就绪后只换 source · 上层 BannerService 不动

import Foundation

public protocol BannerSource: Sendable {
    /// 拉取后端最新 banner 列表 · 客户端 dedupe 已 dismissed + 过期
    func fetchLatest() async throws -> [Banner]
}

/// 占位实现 · 默认空列表（无骚扰）· 测试 / 联调可注入固定列表
public actor StubBannerSource: BannerSource {
    private var fixed: [Banner]
    public init(fixed: [Banner] = []) {
        self.fixed = fixed
    }
    public func setFixed(_ list: [Banner]) {
        self.fixed = list
    }
    public func fetchLatest() async throws -> [Banner] {
        fixed
    }
}
