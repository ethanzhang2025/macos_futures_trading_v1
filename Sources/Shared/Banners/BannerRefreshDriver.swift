// WP-120 · Banner 周期刷新 driver（v15.18 · 启动后周期 fetch）
//
// 设计取舍（与 BatchUploadDriver 同模式）：
// - 周期 5 分钟 fetch · 后端可推送新 banner / 撤回旧 banner
// - poll 节奏注入便于测试（pollIntervalSec）· 默认 300s
// - actor 持 task · cancel + await 旧 task 防双 task（v15.16 hotfix #12 经验）
// - 失败：BannerService.refresh 已静默 fallback · driver 不再处理

import Foundation

public actor BannerRefreshDriver {

    private let service: BannerService
    private let pollIntervalSec: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void

    private var pollTask: Task<Void, Never>?

    public init(
        service: BannerService,
        pollIntervalSec: UInt64 = 300,    // 默认 5 分钟
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.service = service
        self.pollIntervalSec = pollIntervalSec
        self.sleep = sleep
    }

    /// 启动周期 poll · 已运行则先 cancel + await 旧 task
    public func start() async {
        if let old = pollTask {
            old.cancel()
            await old.value
            pollTask = nil
        }
        pollTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() async {
        guard let task = pollTask else { return }
        pollTask = nil
        task.cancel()
        await task.value
    }

    // MARK: - 内部

    private func runLoop() async {
        // 立即拉一次（不等 5min · 启动即有数据）
        _ = await service.refresh()
        while !Task.isCancelled {
            do {
                try await sleep(pollIntervalSec * 1_000_000_000)
            } catch {
                break
            }
            _ = await service.refresh()
        }
    }
}
