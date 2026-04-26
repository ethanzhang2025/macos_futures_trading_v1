// WP-51 Timer 驱动器 · 自动 stepForward 循环
//
// 设计：
// - actor 包 Task：start 启动循环 / stop 取消 Task / 重复 start 自动 cancel 旧 task
// - 每步动态读 player.currentSpeed → 间隔 = baseInterval / speed.multiplier
//   → setSpeed 不需要重启 driver，下一步循环自动应用
// - 自动停条件（任一即停）：
//   1. player.currentState != .playing（pause / stop 后）
//   2. stepForward(count: 1) 返回 0（末尾）
//   3. driveTask cancel
// - 不持有 wall-clock 真实时间：用 Task.sleep（注入 baseInterval 控制粒度）
//
// 用途：UI 层 Play/Pause 按钮直接绑定到本驱动器，替代 caller 手动循环

import Foundation

public actor ReplayDriver {

    private let player: ReplayPlayer
    private let baseInterval: TimeInterval
    private var driveTask: Task<Void, Never>?

    /// - Parameters:
    ///   - player: 关联的 ReplayPlayer（必须已 load + play）
    ///   - baseInterval: 1x 速度下每步间隔（默认 1s · UI 绘图层可设小如 0.016 ≈ 60fps）
    public init(player: ReplayPlayer, baseInterval: TimeInterval = 1.0) {
        self.player = player
        self.baseInterval = baseInterval
    }

    /// 启动循环驱动 · 重复调用会取消旧 task 启动新 task
    public func start() async {
        driveTask?.cancel()
        let player = self.player
        let baseInterval = self.baseInterval
        driveTask = Task.detached {
            while !Task.isCancelled {
                let state = await player.currentState
                guard state == .playing else { break }

                let advanced = await player.stepForward(count: 1)
                if advanced == 0 { break }  // 末尾自动停

                let speed = await player.currentSpeed
                let interval = max(0.001, baseInterval / speed.multiplier)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// 立即停止驱动（player 状态不变 · 由 caller 决定是否 player.pause）
    public func stop() async {
        driveTask?.cancel()
        driveTask = nil
    }

    /// 当前是否在运行（测试 / UI 状态绑定用）
    public var isRunning: Bool {
        driveTask?.isCancelled == false
    }
}
