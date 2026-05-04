// WP-133a · SessionGapPolicy 3 分钟规则单测（v15.18）
//
// 覆盖：首启 · 跨阈值 · 短切焦点 · 边界精确秒

import Testing
import Foundation
@testable import Shared

@Suite("SessionGapPolicy · 3 分钟规则")
struct SessionGapPolicyTests {

    @Test("首启（lastEndMs == 0）必发新 session_start")
    func firstLaunchTriggersNewSession() {
        #expect(SessionGapPolicy.shouldStartNewSession(nowMs: 1_700_000_000_000, lastEndMs: 0))
    }

    @Test("lastEndMs 损坏（负数）等同首启 · 必发")
    func corruptedLastEndTriggersNewSession() {
        #expect(SessionGapPolicy.shouldStartNewSession(nowMs: 1_700_000_000_000, lastEndMs: -1))
    }

    @Test("距上次 end > 3 分钟 · 发新 session_start")
    func gapOverThresholdTriggers() {
        let last: Int64 = 1_700_000_000_000
        let now = last + 3 * 60 * 1000 + 1   // 3min + 1ms
        #expect(SessionGapPolicy.shouldStartNewSession(nowMs: now, lastEndMs: last))
    }

    @Test("距上次 end == 3 分钟（边界精确）· 发新 session（>= 阈值）")
    func gapAtThresholdTriggers() {
        let last: Int64 = 1_700_000_000_000
        let now = last + 3 * 60 * 1000   // 正好 3 分钟
        #expect(SessionGapPolicy.shouldStartNewSession(nowMs: now, lastEndMs: last))
    }

    @Test("距上次 end < 3 分钟 · 不发新 session（短切焦点视为同 session）")
    func gapUnderThresholdSkips() {
        let last: Int64 = 1_700_000_000_000
        let now = last + 3 * 60 * 1000 - 1   // 3min - 1ms
        #expect(!SessionGapPolicy.shouldStartNewSession(nowMs: now, lastEndMs: last))
    }

    @Test("now == lastEnd（瞬间切回）· 不发新 session")
    func sameInstantSkips() {
        let same: Int64 = 1_700_000_000_000
        #expect(!SessionGapPolicy.shouldStartNewSession(nowMs: same, lastEndMs: same))
    }

    @Test("阈值常量 = 3 分钟 = 180_000ms（防误改）")
    func thresholdConstantStable() {
        #expect(SessionGapPolicy.sessionGapMs == 180_000)
    }
}
