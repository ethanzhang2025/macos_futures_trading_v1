// WP-21a · 断线重连状态机 + 退避策略测试
// 退避：序列正确性 / cap / jitter 范围 / 边界
// 状态机：状态转移完备性 / attempt 计数 / observe AsyncStream / reset

import Testing
import Foundation
@testable import DataCore

// MARK: - BackoffPolicy

@Suite("ExponentialBackoff · 退避序列与 cap")
struct ExponentialBackoffTests {

    @Test("attempt = 0 始终返回 0")
    func attemptZeroReturnsZero() {
        let backoff = ExponentialBackoff(jitterRatio: 0)
        #expect(backoff.nextDelay(forAttempt: 0) == 0)
        #expect(backoff.nextDelay(forAttempt: -1) == 0)
    }

    @Test("无 jitter 时退避序列为 base * factor^(attempt-1)")
    func exponentialSequence() {
        let backoff = ExponentialBackoff(baseDelay: 1, factor: 2, maxDelay: 100, jitterRatio: 0)
        #expect(backoff.nextDelay(forAttempt: 1) == 1)
        #expect(backoff.nextDelay(forAttempt: 2) == 2)
        #expect(backoff.nextDelay(forAttempt: 3) == 4)
        #expect(backoff.nextDelay(forAttempt: 4) == 8)
        #expect(backoff.nextDelay(forAttempt: 5) == 16)
    }

    @Test("超出 maxDelay 时被 cap")
    func cappedAtMax() {
        let backoff = ExponentialBackoff(baseDelay: 1, factor: 2, maxDelay: 10, jitterRatio: 0)
        #expect(backoff.nextDelay(forAttempt: 5) == 10)  // raw 16 → cap 10
        #expect(backoff.nextDelay(forAttempt: 10) == 10)
        #expect(backoff.nextDelay(forAttempt: 100) == 10)
    }

    @Test("jitter rng=0 时为 -jitterRatio · rng→1 时趋向 +jitterRatio")
    func jitterRange() {
        let lowRNG: @Sendable () -> Double = { 0 }
        let backoff1 = ExponentialBackoff(baseDelay: 10, factor: 1, maxDelay: 10, jitterRatio: 0.2, rng: lowRNG)
        // 10 + 10*0.2*(0*2-1) = 10 - 2 = 8
        #expect(backoff1.nextDelay(forAttempt: 1) == 8)

        let highRNG: @Sendable () -> Double = { 0.999_999 }
        let backoff2 = ExponentialBackoff(baseDelay: 10, factor: 1, maxDelay: 10, jitterRatio: 0.2, rng: highRNG)
        // 10 + 10*0.2*(0.999998-1) ≈ 10 + 2*0.999998 ≈ 11.999996
        let result = backoff2.nextDelay(forAttempt: 1)
        #expect(result > 11.999 && result < 12.001)
    }

    @Test("jitter 不会让结果变负")
    func jitterClampedToZero() {
        let veryNegativeRNG: @Sendable () -> Double = { 0 }  // -jitterRatio 方向最大
        let backoff = ExponentialBackoff(baseDelay: 0.1, factor: 1, maxDelay: 0.1, jitterRatio: 0.99, rng: veryNegativeRNG)
        // 0.1 + 0.1*0.99*(0*2-1) = 0.1 - 0.099 = 0.001 → 仍 >= 0
        #expect(backoff.nextDelay(forAttempt: 1) >= 0)
    }
}

@Suite("NoBackoff · 总是 0")
struct NoBackoffTests {
    @Test("任何 attempt 都返回 0")
    func alwaysZero() {
        let policy = NoBackoff()
        #expect(policy.nextDelay(forAttempt: 0) == 0)
        #expect(policy.nextDelay(forAttempt: 1) == 0)
        #expect(policy.nextDelay(forAttempt: 100) == 0)
    }
}

// MARK: - ConnectionStateMachine

@Suite("ConnectionStateMachine · 状态转移")
struct StateTransitionTests {

    @Test("初始状态为 disconnected")
    func initialState() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        #expect(await machine.state == .disconnected)
        #expect(await machine.attemptCount == 0)
    }

    @Test("disconnected → connecting → connected 正常流程")
    func happyPath() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        await machine.reportConnecting()
        #expect(await machine.state == .connecting)

        await machine.reportConnected()
        #expect(await machine.state == .connected)
        #expect(await machine.attemptCount == 0)
    }

    @Test("connectionLost 进入 reconnecting(attempt: N) 并返回退避秒数")
    func connectionLostIncrementsAttempt() async {
        let machine = ConnectionStateMachine(backoff: ExponentialBackoff(baseDelay: 1, factor: 2, maxDelay: 100, jitterRatio: 0))
        await machine.reportConnecting()
        await machine.reportConnected()

        let d1 = await machine.reportConnectionLost()
        #expect(await machine.state == .reconnecting(attempt: 1))
        #expect(d1 == 1)

        let d2 = await machine.reportConnectionLost()
        #expect(await machine.state == .reconnecting(attempt: 2))
        #expect(d2 == 2)

        let d3 = await machine.reportConnectionLost()
        #expect(await machine.state == .reconnecting(attempt: 3))
        #expect(d3 == 4)
    }

    @Test("reportConnected 在 reconnecting 后重置 attempt")
    func reconnectedResetsAttempt() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        await machine.reportConnecting()
        await machine.reportConnected()
        _ = await machine.reportConnectionLost()
        _ = await machine.reportConnectionLost()
        #expect(await machine.attemptCount == 2)

        await machine.reportConnecting()
        await machine.reportConnected()
        #expect(await machine.state == .connected)
        #expect(await machine.attemptCount == 0)
    }

    @Test("reportDisconnected 重置 attempt 并回到 disconnected")
    func disconnectResetsAttempt() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        await machine.reportConnecting()
        await machine.reportConnected()
        _ = await machine.reportConnectionLost()
        await machine.reportDisconnected()
        #expect(await machine.state == .disconnected)
        #expect(await machine.attemptCount == 0)
    }

    @Test("reportError 进入 error 终态并清空 attempt")
    func errorClearsAttempt() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        await machine.reportConnecting()
        _ = await machine.reportConnectionLost()
        await machine.reportError("CTP 鉴权失败")
        #expect(await machine.state == .error("CTP 鉴权失败"))
        #expect(await machine.attemptCount == 0)
    }

    @Test("reset 从任意态回到 disconnected")
    func resetFromAnyState() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        await machine.reportError("X")
        await machine.reset()
        #expect(await machine.state == .disconnected)
        #expect(await machine.attemptCount == 0)
    }
}

@Suite("ConnectionStateMachine · observe AsyncStream")
struct ObservationTests {

    @Test("observe 推送初始状态")
    func observeInitial() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        let stream = await machine.observe()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .disconnected)
    }

    @Test("observe 推送状态转移序列")
    func observeTransitions() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        let stream = await machine.observe()

        // 后台收集前 4 个状态
        let collectTask = Task<[ConnectionState], Never> {
            var collected: [ConnectionState] = []
            var iter = stream.makeAsyncIterator()
            for _ in 0..<4 {
                if let s = await iter.next() { collected.append(s) }
            }
            return collected
        }

        // 主动触发转移
        await machine.reportConnecting()
        await machine.reportConnected()
        _ = await machine.reportConnectionLost()

        let collected = await collectTask.value
        #expect(collected == [
            .disconnected,
            .connecting,
            .connected,
            .reconnecting(attempt: 1),
        ])
    }

    @Test("多订阅者各自收到状态")
    func multipleObservers() async {
        let machine = ConnectionStateMachine(backoff: NoBackoff())
        let s1 = await machine.observe()
        let s2 = await machine.observe()

        let task1 = Task<ConnectionState?, Never> {
            var iter = s1.makeAsyncIterator()
            _ = await iter.next()  // 跳过初始
            return await iter.next()
        }
        let task2 = Task<ConnectionState?, Never> {
            var iter = s2.makeAsyncIterator()
            _ = await iter.next()
            return await iter.next()
        }

        await machine.reportConnecting()

        #expect(await task1.value == .connecting)
        #expect(await task2.value == .connecting)
    }
}
