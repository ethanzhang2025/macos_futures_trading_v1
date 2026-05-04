// WP-133b · 占位上报客户端（v15.18 · 后端未就绪占位）
//
// 设计取舍：
// - WP-80 后端就绪前 · 用 stub 跑通客户端链路（queryPending → upload → markUploaded）
// - 默认行为：成功（counter++）· 不真发网络请求 · 调试时可看 stats 验证 driver 调度逻辑
// - 可注入 fail mode（测试 + 未来 / staging 联调用）· 走 BatchUploadError.networkFailed 路径
// - 后端就绪后替换为 HTTPBatchUploadClient（URLSession + JSON · endpoint 待 WP-80 出）

import Foundation

/// 占位上报客户端（无网络 · driver 调度链路验证用）
public actor StubBatchUploadClient: BatchUploadClient {

    /// 上报模式
    public enum Mode: Sendable, Equatable {
        case success                    // 默认 · 成功（不上报真请求）
        case alwaysFail(String)         // 始终失败（注入消息 · 测试 driver 重试路径）
    }

    private var mode: Mode
    private var uploadCallCount: Int = 0
    private var totalEventsReceived: Int = 0

    public init(mode: Mode = .success) {
        self.mode = mode
    }

    public func setMode(_ mode: Mode) {
        self.mode = mode
    }

    public func upload(_ events: [AnalyticsEvent]) async throws {
        uploadCallCount += 1
        totalEventsReceived += events.count
        switch mode {
        case .success:
            return
        case .alwaysFail(let msg):
            throw BatchUploadError.networkFailed(msg)
        }
    }

    // MARK: - 内省（测试 / 调试用）

    public func stats() -> (calls: Int, eventsReceived: Int) {
        (uploadCallCount, totalEventsReceived)
    }
}
