// WP-51 模块 2 · K 线回放 player
// actor 隔离 + 离散 step 推进 + AsyncStream 推送
// caller 责任：用 Timer / DisplayLink 驱动 stepForward（频率由 ReplaySpeed.multiplier 决定）

import Foundation
import Shared

/// K 线回放 player · 数据驱动核心
public actor ReplayPlayer {

    // MARK: - 状态

    private var bars: [KLine] = []
    private var tradeMarks: [TradeMark] = []
    /// -1 = 未加载；0..<count = 当前 K 线索引
    private var currentIndex: Int = -1
    private var state: ReplayState = .stopped
    private var speed: ReplaySpeed = .x1
    private var direction: ReplayDirection = .forward

    private var continuations: [UUID: AsyncStream<ReplayUpdate>.Continuation] = [:]

    public init() {}

    // MARK: - 加载 / 重置

    /// 加载历史数据（自动按 openTime 升序）+ 重置游标
    public func load(bars: [KLine], tradeMarks: [TradeMark] = []) {
        self.bars = bars.sorted { $0.openTime < $1.openTime }
        self.tradeMarks = tradeMarks.sorted { $0.time < $1.time }
        self.currentIndex = bars.isEmpty ? -1 : 0
        self.state = .stopped
        emitStateChanged()
    }

    // MARK: - 播放控制

    /// 进入 playing 状态（caller 应开始周期性调用 stepForward）
    public func play() {
        guard !bars.isEmpty else { return }
        guard state != .playing else { return }
        state = .playing
        emitStateChanged()
    }

    public func pause() {
        guard state == .playing else { return }
        state = .paused
        emitStateChanged()
    }

    /// 停止 + 重置游标到 0
    public func stop() {
        currentIndex = bars.isEmpty ? -1 : 0
        state = .stopped
        emitStateChanged()
    }

    // MARK: - 步进

    /// 前进 N 根 K 线（默认 1）；自动到末尾时切 paused
    /// - Returns: 实际推进的根数
    @discardableResult
    public func stepForward(count: Int = 1) -> Int {
        guard !bars.isEmpty, count > 0 else { return 0 }
        let oldIndex = max(currentIndex, 0)
        let newIndex = min(oldIndex + count, bars.count - 1)
        let advanced = newIndex - oldIndex
        guard advanced > 0 else {
            // 已在末尾 → 自动 paused
            pauseIfPlayingAtEnd()
            return 0
        }
        currentIndex = newIndex
        emitBar()
        pauseIfPlayingAtEnd()
        return advanced
    }

    /// 后退 N 根 K 线（默认 1）；起点处 noop
    /// - Returns: 实际后退的根数
    @discardableResult
    public func stepBackward(count: Int = 1) -> Int {
        guard !bars.isEmpty, count > 0, currentIndex > 0 else { return 0 }
        let oldIndex = currentIndex
        let newIndex = max(oldIndex - count, 0)
        let regressed = oldIndex - newIndex
        guard regressed > 0 else { return 0 }
        currentIndex = newIndex
        emitBar()
        return regressed
    }

    /// 跳转到指定 index（自动 clamp 到 [0, count-1]）
    /// emit seekFinished 而非 barEmitted（caller 自行从 currentBar 重画）
    @discardableResult
    public func seek(to index: Int) -> Bool {
        guard !bars.isEmpty else { return false }
        let target = max(0, min(index, bars.count - 1))
        guard target != currentIndex else { return false }
        currentIndex = target
        broadcast(.seekFinished(cursor: cursor))
        return true
    }

    // MARK: - 配置

    public func setSpeed(_ speed: ReplaySpeed) {
        guard self.speed != speed else { return }
        self.speed = speed
        emitStateChanged()
    }

    public func setDirection(_ direction: ReplayDirection) {
        guard self.direction != direction else { return }
        self.direction = direction
        emitStateChanged()
    }

    // MARK: - 查询

    public var cursor: ReplayCursor {
        ReplayCursor(currentIndex: currentIndex, totalCount: bars.count)
    }

    public var currentBar: KLine? {
        guard currentIndex >= 0, currentIndex < bars.count else { return nil }
        return bars[currentIndex]
    }

    public var currentState: ReplayState { state }
    public var currentSpeed: ReplaySpeed { speed }
    public var currentDirection: ReplayDirection { direction }

    /// 取当前 K 线时间窗口内的成交点（[openTime, openTime + period.seconds))
    /// v1 简单实现：用前后相邻 K 线 openTime 作为窗口边界
    public func tradeMarksAtCurrentBar() -> [TradeMark] {
        guard let bar = currentBar else { return [] }
        let nextOpen = (currentIndex + 1 < bars.count) ? bars[currentIndex + 1].openTime : .distantFuture
        return tradeMarks.filter { mark in
            mark.instrumentID == bar.instrumentID
                && mark.time >= bar.openTime
                && mark.time < nextOpen
        }
    }

    // MARK: - 订阅

    public func observe() -> AsyncStream<ReplayUpdate> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - 私有：广播

    private func broadcast(_ update: ReplayUpdate) {
        for cont in continuations.values { cont.yield(update) }
    }

    private func emitBar() {
        guard let bar = currentBar else { return }
        broadcast(.barEmitted(bar, cursor: cursor))
    }

    private func emitStateChanged() {
        broadcast(.stateChanged(state: state, speed: speed, direction: direction))
    }

    /// stepForward 末尾自动暂停 helper（playing && isAtEnd → paused）
    private func pauseIfPlayingAtEnd() {
        guard state == .playing, cursor.isAtEnd else { return }
        state = .paused
        emitStateChanged()
    }
}
