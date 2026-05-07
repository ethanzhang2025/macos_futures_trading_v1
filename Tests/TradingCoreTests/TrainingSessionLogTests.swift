// WP-54 v15.23 batch7 · 训练 session 历史集合 + 统计测试

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("TrainingSessionLog · WP-54 v15.23 batch7 历史 + 统计")
struct TrainingSessionLogTests {

    private let t0 = Date(timeIntervalSince1970: 1746360000)

    private func makeSession(initial: Decimal = 100000, final: Decimal,
                             errors: Int = 0, warnings: Int = 0) -> TrainingSession {
        var violations: [DisciplineViolation] = []
        for i in 0..<errors {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .stopLossPercent, occurredAt: t0,
                severity: .error, message: "e\(i)"))
        }
        for i in 0..<warnings {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .maxHoldingMinutes, occurredAt: t0,
                severity: .warning, message: "w\(i)"))
        }
        return TrainingSession(startedAt: t0, endedAt: t0.addingTimeInterval(3600),
                               initialBalance: initial, finalBalance: final,
                               violations: violations)
    }

    @Test("空 log · sessionCount=0 / averageScore=0 / bestScore=nil")
    func emptyLog() {
        let log = TrainingSessionLog()
        #expect(log.sessionCount == 0)
        #expect(log.averageScore == 0)
        #expect(log.bestScore == nil)
        // gradeDistribution 5 等级 key 都返回 0
        let dist = log.gradeDistribution
        #expect(dist.count == 5)
        #expect(dist.values.allSatisfy { $0 == 0 })
    }

    @Test("addSession · 自动评分缓存（scores[id] 非 nil）")
    func addAutoScores() {
        var log = TrainingSessionLog()
        let s = makeSession(final: 110000)   // +10% pnl
        log.addSession(s)
        #expect(log.sessionCount == 1)
        #expect(log.score(for: s.id) != nil)
        #expect(log.score(for: s.id)?.grade == .S)
    }

    @Test("addSession · 同 id 覆盖（不重复 append）")
    func addSameIDOverwrite() {
        var log = TrainingSessionLog()
        let s1 = makeSession(final: 110000)
        log.addSession(s1)
        // 用相同 id 但内容变（亏损）
        let s2 = TrainingSession(id: s1.id,
                                 startedAt: s1.startedAt, endedAt: s1.endedAt,
                                 initialBalance: 100000, finalBalance: 90000)
        log.addSession(s2)
        #expect(log.sessionCount == 1)
        #expect(log.score(for: s1.id)?.totalScore == log.score(for: s2.id)?.totalScore)
        #expect(log.session(id: s1.id)?.finalBalance == Decimal(90000))
    }

    @Test("removeSession · 同步移除 score 缓存")
    func removeAlsoRemovesScore() {
        var log = TrainingSessionLog()
        let s = makeSession(final: 110000)
        log.addSession(s)
        log.removeSession(id: s.id)
        #expect(log.sessionCount == 0)
        #expect(log.score(for: s.id) == nil)
    }

    @Test("clear · 全部清空")
    func clearAll() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(final: 110000))
        log.addSession(makeSession(final: 95000))
        log.clear()
        #expect(log.sessionCount == 0)
        #expect(log.bestScore == nil)
    }

    @Test("averageScore · 多 session 平均")
    func averageMultiple() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(final: 110000))   // +10% S(100)
        log.addSession(makeSession(final: 100000))   // 平 70 (B)
        // 平均 (100+70)/2 = 85
        #expect(log.averageScore == 85)
    }

    @Test("bestScore · 返回最高总分 session")
    func bestPicksMax() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(final: 95000))     // -5% 0 + 50 = 50 D
        log.addSession(makeSession(final: 110000))    // +10% 50 + 50 = 100 S
        log.addSession(makeSession(final: 102000))    // +2% 30 + 50 = 80 A
        let best = log.bestScore
        #expect(best?.totalScore == 100)
        #expect(best?.grade == .S)
    }

    @Test("gradeDistribution · 各等级计数 · 5 key 全在")
    func gradeDistributionShape() {
        var log = TrainingSessionLog()
        log.addSession(makeSession(final: 110000))  // S
        log.addSession(makeSession(final: 110000))  // S
        log.addSession(makeSession(final: 100000))  // B (70)
        let dist = log.gradeDistribution
        #expect(dist[.S] == 2)
        #expect(dist[.A] == 0)
        #expect(dist[.B] == 1)
        #expect(dist[.C] == 0)
        #expect(dist[.D] == 0)
        #expect(dist.keys.count == 5)
    }

    @Test("recentSessions · 按 endedAt 降序 · limit clamp")
    func recentSorted() {
        var log = TrainingSessionLog()
        let early = TrainingSession(startedAt: t0, endedAt: t0.addingTimeInterval(60),
                                    initialBalance: 100000, finalBalance: 100000)
        let mid = TrainingSession(startedAt: t0, endedAt: t0.addingTimeInterval(3600),
                                  initialBalance: 100000, finalBalance: 100000)
        let recent = TrainingSession(startedAt: t0, endedAt: t0.addingTimeInterval(7200),
                                     initialBalance: 100000, finalBalance: 100000)
        log.addSession(early)
        log.addSession(mid)
        log.addSession(recent)
        let r2 = log.recentSessions(limit: 2)
        #expect(r2.count == 2)
        #expect(r2[0].id == recent.id)
        #expect(r2[1].id == mid.id)
        // limit > count
        #expect(log.recentSessions(limit: 10).count == 3)
        // limit 0 / 负 → 空
        #expect(log.recentSessions(limit: 0).isEmpty)
        #expect(log.recentSessions(limit: -1).isEmpty)
    }

    // v15.23 batch135 · streak 连胜/连败统计
    private func makeSessionAt(_ endedAt: Date, pnl: Decimal) -> TrainingSession {
        TrainingSession(
            startedAt: endedAt.addingTimeInterval(-3600),
            endedAt: endedAt,
            initialBalance: 100_000,
            finalBalance: 100_000 + pnl,
            violations: [])
    }

    @Test("currentStreak · 空 log → (0, false)（batch135）")
    func streakEmpty() {
        let log = TrainingSessionLog()
        #expect(log.currentStreak.count == 0)
        #expect(log.currentStreak.isWinning == false)
    }

    @Test("currentStreak · 最新 1 笔 +10% 赢 → (1, true)")
    func streakSingleWin() {
        var log = TrainingSessionLog()
        log.addSession(makeSessionAt(Date(), pnl: 10000))
        let st = log.currentStreak
        #expect(st.count == 1)
        #expect(st.isWinning == true)
    }

    @Test("currentStreak · 连续 3 笔赢 → (3, true)")
    func streakThreeWins() {
        var log = TrainingSessionLog()
        let now = Date()
        log.addSession(makeSessionAt(now.addingTimeInterval(-7200), pnl: 10000))
        log.addSession(makeSessionAt(now.addingTimeInterval(-3600), pnl: 10000))
        log.addSession(makeSessionAt(now, pnl: 10000))
        let st = log.currentStreak
        #expect(st.count == 3)
        #expect(st.isWinning == true)
    }

    @Test("currentStreak · 连续 2 笔输 → (2, false)")
    func streakTwoLosses() {
        var log = TrainingSessionLog()
        let now = Date()
        // pnl 0 + 无违规 → score = 20 + 50 = 70（边界 · B 级 · 算胜）
        // pnl -3% → pnlScore=0 + disciplineScore=50 = 50（C 级 · 算败）
        // 用 -5%（pnlScore 0）+ 1 error（disciplineScore 50-10=40）= 40 D 级
        log.addSession(TrainingSession(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(-1800),
            initialBalance: 100_000, finalBalance: 95_000,
            violations: [DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                             occurredAt: now, severity: .error, message: "e")]))
        log.addSession(TrainingSession(
            startedAt: now.addingTimeInterval(-1800),
            endedAt: now,
            initialBalance: 100_000, finalBalance: 95_000,
            violations: [DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                             occurredAt: now, severity: .error, message: "e")]))
        let st = log.currentStreak
        #expect(st.count == 2)
        #expect(st.isWinning == false)
    }

    @Test("currentStreak · 最新赢 + 之前输 → 仅数最新连胜（1, true）")
    func streakLatestOnly() {
        var log = TrainingSessionLog()
        let now = Date()
        // 早期一笔输 · 后两笔赢 · streak 应仅 = 2 from latest（赢）
        log.addSession(TrainingSession(
            startedAt: now.addingTimeInterval(-7200),
            endedAt: now.addingTimeInterval(-5400),
            initialBalance: 100_000, finalBalance: 95_000,
            violations: [DisciplineViolation(ruleID: UUID(), ruleKind: .stopLossPercent,
                                             occurredAt: now, severity: .error, message: "e")]))
        log.addSession(makeSessionAt(now.addingTimeInterval(-1800), pnl: 10000))
        log.addSession(makeSessionAt(now, pnl: 10000))
        let st = log.currentStreak
        #expect(st.count == 2)
        #expect(st.isWinning == true)
    }

    @Test("Codable round-trip · 含 sessions + scores 缓存")
    func codableRoundTrip() throws {
        var log = TrainingSessionLog()
        log.addSession(makeSession(final: 110000))
        log.addSession(makeSession(final: 95000, errors: 2))
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(TrainingSessionLog.self, from: data)
        #expect(decoded == log)
    }
}
