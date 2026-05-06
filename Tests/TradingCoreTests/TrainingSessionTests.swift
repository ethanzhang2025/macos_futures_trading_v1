// WP-54 v15.23 batch5 · 模拟训练 session + 评分系统测试

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("TrainingSession + Scorer · WP-54 v15.23 batch5 评分系统")
struct TrainingSessionTests {

    private let t0 = Date(timeIntervalSince1970: 1746360000)
    private var t60: Date { t0.addingTimeInterval(3600) }   // +1h

    private func session(initial: Decimal, final: Decimal,
                         trades: Int = 0, errors: Int = 0, warnings: Int = 0,
                         scenarioName: String = "") -> TrainingSession {
        let tradesArr: [TradeRecord] = (0..<trades).map {
            TradeRecord(tradeID: "T-\($0)", orderRef: "O-\($0)",
                        instrumentID: "rb2410", direction: .buy, offsetFlag: .open,
                        price: 3000, volume: 1, tradeTime: "2026-05-05 10:00:00", commission: 5)
        }
        var violations: [DisciplineViolation] = []
        for i in 0..<errors {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .stopLossPercent, occurredAt: t0,
                severity: .error, message: "err\(i)"))
        }
        for i in 0..<warnings {
            violations.append(DisciplineViolation(
                ruleID: UUID(), ruleKind: .maxHoldingMinutes, occurredAt: t0,
                severity: .warning, message: "warn\(i)"))
        }
        return TrainingSession(startedAt: t0, endedAt: t60,
                               initialBalance: initial, finalBalance: final,
                               trades: tradesArr, violations: violations,
                               scenarioName: scenarioName)
    }

    // MARK: - TrainingSession 派生属性

    @Test("pnl / pnlPercent / durationMinutes 计算")
    func sessionDerivedProps() {
        let s = session(initial: 100000, final: 105000)
        #expect(s.pnl == Decimal(5000))
        #expect(s.pnlPercent == Decimal(5))
        #expect(s.durationMinutes == 60)
    }

    @Test("pnlPercent · initial=0 → 返回 0（防除零）")
    func pnlPercentZeroBalance() {
        let s = session(initial: 0, final: 1000)
        #expect(s.pnlPercent == Decimal(0))
    }

    @Test("Codable round-trip 含 trades + violations + scenarioName")
    func sessionCodable() throws {
        let s = session(initial: 100000, final: 102000, trades: 3, errors: 1, warnings: 2,
                        scenarioName: "螺纹钢测试")
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: data)
        #expect(decoded == s)
    }

    // MARK: - pnl 子分阶梯

    @Test("pnlSubScore · 阶梯 50/40/30/20/10/0")
    func pnlScoreLadder() {
        // 大赚 +10% → 50
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 110000)) == 50)
        // +3% → 40
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 103000)) == 40)
        // +1% → 30
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 101000)) == 30)
        // 平 → 20
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 100000)) == 20)
        // -1% → 10
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 99000)) == 10)
        // -5% → 0
        #expect(TrainingScorer.pnlSubScore(session(initial: 100000, final: 95000)) == 0)
    }

    // MARK: - 纪律子分

    @Test("disciplineSubScore · 0 违规 → 50 满分")
    func disciplineFullScore() {
        #expect(TrainingScorer.disciplineSubScore(session(initial: 100000, final: 100000)) == 50)
    }

    @Test("disciplineSubScore · 2 error + 3 warning → 50 - 20 - 9 = 21")
    func disciplineDeduct() {
        let s = session(initial: 100000, final: 100000, errors: 2, warnings: 3)
        #expect(TrainingScorer.disciplineSubScore(s) == 21)
    }

    @Test("disciplineSubScore · clamp 不为负（10 errors → 0 而非 -50）")
    func disciplineClampNonNeg() {
        let s = session(initial: 100000, final: 100000, errors: 10)
        #expect(TrainingScorer.disciplineSubScore(s) == 0)
    }

    // MARK: - Grade 等级

    @Test("Grade · S/A/B/C/D 边界 90/80/70/60")
    func gradeBoundaries() {
        #expect(TrainingScorer.gradeFor(100) == .S)
        #expect(TrainingScorer.gradeFor(90)  == .S)
        #expect(TrainingScorer.gradeFor(89)  == .A)
        #expect(TrainingScorer.gradeFor(80)  == .A)
        #expect(TrainingScorer.gradeFor(79)  == .B)
        #expect(TrainingScorer.gradeFor(70)  == .B)
        #expect(TrainingScorer.gradeFor(69)  == .C)
        #expect(TrainingScorer.gradeFor(60)  == .C)
        #expect(TrainingScorer.gradeFor(59)  == .D)
        #expect(TrainingScorer.gradeFor(0)   == .D)
    }

    @Test("Grade · emoji + displayName")
    func gradeEmojiDisplay() {
        #expect(TrainingScore.Grade.S.emoji == "🏆")
        #expect(TrainingScore.Grade.D.emoji == "📉")
        #expect(TrainingScore.Grade.A.displayName == "A")
    }

    // MARK: - 总分 + summary

    @Test("score · 完美 session（+10% · 0 违规）→ 100 分 S 级")
    func perfectScore() {
        let s = session(initial: 100000, final: 110000, trades: 5)
        let r = TrainingScorer.score(s)
        #expect(r.totalScore == 100)
        #expect(r.pnlScore == 50)
        #expect(r.disciplineScore == 50)
        #expect(r.grade == .S)
        #expect(r.summary.contains("总分 100"))
        #expect(r.summary.contains("10.00%"))
    }

    @Test("score · 普通 session（+3% · 1 error · 2 warning）→ 40 + 34 = 74 B 级")
    func normalScore() {
        let s = session(initial: 100000, final: 103000, trades: 5, errors: 1, warnings: 2)
        let r = TrainingScorer.score(s)
        #expect(r.totalScore == 74)
        #expect(r.pnlScore == 40)
        #expect(r.disciplineScore == 34)
        #expect(r.grade == .B)
    }

    @Test("score · 翻车 session（-5% · 3 errors）→ 0 + 20 = 20 D 级")
    func disasterScore() {
        let s = session(initial: 100000, final: 95000, trades: 8, errors: 3)
        let r = TrainingScorer.score(s)
        #expect(r.totalScore == 20)
        #expect(r.pnlScore == 0)
        #expect(r.disciplineScore == 20)
        #expect(r.grade == .D)
    }

    @Test("score · TrainingScore Codable round-trip")
    func scoreCodable() throws {
        let s = session(initial: 100000, final: 102000, trades: 2)
        let r = TrainingScorer.score(s)
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(TrainingScore.self, from: data)
        #expect(decoded == r)
    }
}
