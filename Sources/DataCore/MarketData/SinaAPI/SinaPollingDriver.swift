// WP-31a · Production 用 Sina 轮询驱动器
//
// 与 SinaMarketDataProvider 分离的理由：
// - Provider 保持纯状态机（actor 不持 Task），与 WP-21a 哲学一致
// - 测试只测 pollOnce 行为；Driver 单独测（可注入 interval = 0 + 限定循环次数）
// - 切换 production / mock 不耦合 Driver 生命周期
//
// 默认 interval = 3.0s（Sina API 实测秒级刷新；≤6 品种数秒）
// 失败处理：pollOnce 内部已上报 stateMachine.reportConnectionLost；Driver 仅控时

import Foundation

/// 持续轮询 SinaMarketDataProvider 的 production 驱动器
public actor SinaPollingDriver {

    private let provider: SinaMarketDataProvider
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    public init(provider: SinaMarketDataProvider, interval: TimeInterval = 3.0) {
        precondition(interval > 0, "interval 必须 > 0；测试请用 pollOnce 直接驱动")
        self.provider = provider
        self.interval = interval
    }

    /// 启动后台轮询；幂等（重复 start 会先 stop 旧任务）
    public func start() {
        task?.cancel()
        let p = provider
        let nanos = UInt64(interval * 1_000_000_000)
        task = Task.detached {
            while !Task.isCancelled {
                _ = await p.pollOnce()
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    /// 停止后台轮询
    public func stop() {
        task?.cancel()
        task = nil
    }

    /// 当前是否在运行
    public func isRunning() -> Bool { task != nil }
}
