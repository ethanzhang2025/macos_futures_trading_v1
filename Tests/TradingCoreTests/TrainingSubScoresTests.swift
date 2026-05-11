// v16.6 评分 v2 · TrainingSubScores 五维 + weakness 测试
//
// 覆盖：
// - pnlScore100 / disciplineScore100 / winRateScore100 / riskScore100 / efficiencyScore100 各自边界
// - closedPairs FIFO 配对（开-平/部分平仓/不平衡/多合约）
// - weakness 选最弱维度 + 中文建议
// - TrainingSubScores Codable + TrainingScore.subScores 老 JSON 兼容（decodeIfPresent）
// - score(_:) 入口同时填 subScores · 老 totalScore 算法不变

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("TrainingSubScores · v16.6 评分 v2 五维 + weakness")
struct TrainingSubScoresTests {

    private let t0 = Date(timeIntervalSince1970: 1746360000)
    private var t60: Date { t0.addingTimeInterval(3600) }

    /// 简化构造 · trades 显式传 · violations 仅 errors/warnings 计数
    private func session(initial: Decimal = 100_000, final: Decimal = 100_000,
                         trades: [TradeRecord] = [],
                         errors: Int = 0, warnings: Int = 0) -> TrainingSession {
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
                               trades: trades, violations: violations)
    }

    private func openTrade(_ id: String, instrument: String = "rb2410",
                           direction: Direction = .buy, price: Decimal, volume: Int = 1) -> TradeRecord {
        TradeRecord(tradeID: id, orderRef: "O-\(id)", instrumentID: instrument,
                    direction: direction, offsetFlag: .open,
                    price: price, volume: volume, tradeTime: "10:00", commission: 0)
    }

    private func closeTrade(_ id: String, instrument: String = "rb2410",
                            direction: Direction = .buy, price: Decimal, volume: Int = 1) -> TradeRecord {
        TradeRecord(tradeID: id, orderRef: "O-\(id)", instrumentID: instrument,
                    direction: direction, offsetFlag: .close,
                    price: price, volume: volume, tradeTime: "10:30", commission: 0)
    }

    // MARK: - pnlScore100 阶梯

    @Test("pnlScore100 · 阶梯 100/80/60/40/20/0")
    func test_pnlScore100_ladder() {
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 110)) == 100)  // +10%
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 103)) == 80)   // +3%
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 101)) == 60)   // +1%
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 100)) == 40)   // 0
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 99)) == 20)    // -1%
        #expect(TrainingScorer.pnlScore100(session(initial: 100, final: 95)) == 0)     // -5%
    }

    // MARK: - disciplineScore100

    @Test("disciplineScore100 · 0 违规 → 100 满分")
    func test_disciplineScore100_perfect() {
        #expect(TrainingScorer.disciplineScore100(session()) == 100)
    }

    @Test("disciplineScore100 · 2 error + 3 warning → 100 - 40 - 18 = 42")
    func test_disciplineScore100_mixed() {
        #expect(TrainingScorer.disciplineScore100(session(errors: 2, warnings: 3)) == 42)
    }

    @Test("disciplineScore100 · clamp 不为负（10 errors → 0）")
    func test_disciplineScore100_clamp() {
        #expect(TrainingScorer.disciplineScore100(session(errors: 10)) == 0)
    }

    // MARK: - closedPairs FIFO 配对

    @Test("closedPairs · 简单一开一平")
    func test_closedPairs_simple() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000, volume: 2),
            closeTrade("B", price: 3010, volume: 2),
        ])
        #expect(pairs.count == 1)
        #expect(pairs[0].pnl == Decimal(20))   // (3010-3000) * 2
    }

    @Test("closedPairs · 部分平仓（开 5 · 平 2 + 平 3 → 2 个 pair）")
    func test_closedPairs_partialClose() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000, volume: 5),
            closeTrade("B", price: 3010, volume: 2),
            closeTrade("C", price: 3020, volume: 3),
        ])
        #expect(pairs.count == 2)
        #expect(pairs[0].volume == 2 && pairs[0].closePrice == 3010)
        #expect(pairs[1].volume == 3 && pairs[1].closePrice == 3020)
    }

    @Test("closedPairs · FIFO 跨多笔开仓（2+3 各 1 平 → 拆分配对）")
    func test_closedPairs_fifo() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000, volume: 2),
            openTrade("B", price: 3050, volume: 3),
            closeTrade("C", price: 3100, volume: 4),   // 吃完 A(2) + B 的 2
        ])
        #expect(pairs.count == 2)
        #expect(pairs[0].openPrice == 3000 && pairs[0].volume == 2)
        #expect(pairs[1].openPrice == 3050 && pairs[1].volume == 2)
    }

    @Test("closedPairs · 空仓未平 + 多余平仓忽略 · 不抛异常")
    func test_closedPairs_unbalanced() {
        // 仅开仓 → 0 pair
        let onlyOpen = TrainingScorer.closedPairs(from: [openTrade("A", price: 3000)])
        #expect(onlyOpen.isEmpty)
        // 仅平仓 → 0 pair（队列空 · 平仓被忽略）
        let onlyClose = TrainingScorer.closedPairs(from: [closeTrade("A", price: 3000)])
        #expect(onlyClose.isEmpty)
    }

    @Test("closedPairs · 空头方向 pnl = open - close")
    func test_closedPairs_short() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", direction: .sell, price: 3000, volume: 1),
            closeTrade("B", direction: .sell, price: 2980, volume: 1),
        ])
        #expect(pairs.count == 1)
        #expect(pairs[0].pnl == Decimal(20))   // 3000 - 2980 = +20（空头赚）
    }

    @Test("closedPairs · 多合约方向独立 FIFO 队列")
    func test_closedPairs_multiInstrument() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", instrument: "rb2410", price: 3000),
            openTrade("B", instrument: "ag2412", price: 7000),
            closeTrade("C", instrument: "ag2412", price: 7050),
            closeTrade("D", instrument: "rb2410", price: 3010),
        ])
        #expect(pairs.count == 2)
        // 不假设顺序 · 但两 pair 都成对
        let totalVol = pairs.reduce(0) { $0 + $1.volume }
        #expect(totalVol == 2)
    }

    // MARK: - winRateScore100

    @Test("winRateScore100 · 无 pair → 50 中性")
    func test_winRate_noPair() {
        #expect(TrainingScorer.winRateScore100(pairs: []) == 50)
    }

    @Test("winRateScore100 · 全赢 → 100")
    func test_winRate_allWin() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000), closeTrade("A2", price: 3010),
            openTrade("B", price: 3000), closeTrade("B2", price: 3020),
        ])
        #expect(TrainingScorer.winRateScore100(pairs: pairs) == 100)
    }

    @Test("winRateScore100 · 半赢半亏 → 50")
    func test_winRate_half() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000), closeTrade("A2", price: 3010),  // win
            openTrade("B", price: 3000), closeTrade("B2", price: 2990),  // lose
        ])
        #expect(TrainingScorer.winRateScore100(pairs: pairs) == 50)
    }

    // MARK: - riskScore100

    @Test("riskScore100 · 无 pair → 50 中性")
    func test_risk_noPair() {
        #expect(TrainingScorer.riskScore100(pairs: [], initialBalance: 100_000) == 50)
    }

    @Test("riskScore100 · 全盈 → 100（worstLoss=0）")
    func test_risk_allWin() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000, volume: 1), closeTrade("A2", price: 3010, volume: 1),
        ])
        #expect(TrainingScorer.riskScore100(pairs: pairs, initialBalance: 100_000) == 100)
    }

    @Test("riskScore100 · 单笔 5% 亏损 → 0")
    func test_risk_5pctLoss() {
        // 单笔亏损 5000 元（initial=100000） → 5% → 0
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000, volume: 1),
            closeTrade("A2", price: 3000 - 5000, volume: 1),  // 亏 5000
        ])
        #expect(TrainingScorer.riskScore100(pairs: pairs, initialBalance: 100_000) == 0)
    }

    // MARK: - efficiencyScore100

    @Test("efficiencyScore100 · 无 pair → 50 中性")
    func test_efficiency_noPair() {
        #expect(TrainingScorer.efficiencyScore100(pairs: [], initialBalance: 100_000) == 50)
    }

    @Test("efficiencyScore100 · 平均 +0.5%/笔 → 100")
    func test_efficiency_max() {
        // 单笔 +500 / 100000 = 0.5% → 100
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000), closeTrade("A2", price: 3500),
        ])
        #expect(TrainingScorer.efficiencyScore100(pairs: pairs, initialBalance: 100_000) == 100)
    }

    @Test("efficiencyScore100 · 平均 0 → 50")
    func test_efficiency_breakeven() {
        let pairs = TrainingScorer.closedPairs(from: [
            openTrade("A", price: 3000), closeTrade("A2", price: 3000),
        ])
        #expect(TrainingScorer.efficiencyScore100(pairs: pairs, initialBalance: 100_000) == 50)
    }

    // MARK: - weakness 选最弱维度

    @Test("weakness · 5 维全 100 时 weakest 落 pnl（同分按枚举顺序）")
    func test_weakness_allMax() {
        // pnl 100 / disc 100 / win 50（无 pair） / risk 50 / eff 50 → weakest 是 winRate（first 50）
        let s = session(initial: 100_000, final: 110_000)
        let sub = TrainingScorer.computeSubScores(s)
        #expect(sub.pnl == 100)
        #expect(sub.discipline == 100)
        // 无 trades → win/risk/eff 都 50 → weakest 是它们之一
        #expect([.winRate, .risk, .efficiency].contains(sub.weakest))
    }

    @Test("weakness · 纪律违规多 → weakness 指向 discipline")
    func test_weakness_discipline() {
        let s = session(initial: 100_000, final: 105_000, errors: 4)
        let sub = TrainingScorer.computeSubScores(s)
        #expect(sub.discipline == 20)
        #expect(sub.weakest == .discipline)
        #expect(sub.weakness.contains("纪律"))
    }

    @Test("weakness · 大亏损 → weakness 指向 pnl 或 risk")
    func test_weakness_bigLoss() {
        // 亏 10% · 单笔 5000 亏损
        let s = session(initial: 100_000, final: 90_000,
                        trades: [
                            TradeRecord(tradeID: "T1", orderRef: "O1", instrumentID: "rb2410",
                                        direction: .buy, offsetFlag: .open,
                                        price: 3000, volume: 1, tradeTime: "10:00", commission: 0),
                            TradeRecord(tradeID: "T2", orderRef: "O2", instrumentID: "rb2410",
                                        direction: .buy, offsetFlag: .close,
                                        price: 3000 - 5000, volume: 1, tradeTime: "10:30", commission: 0),
                        ])
        let sub = TrainingScorer.computeSubScores(s)
        #expect(sub.pnl == 0)            // -10% → 0
        #expect(sub.risk == 0)           // 5% 亏损 → 0
        #expect([.pnl, .risk, .efficiency].contains(sub.weakest))
    }

    // MARK: - TrainingScorer.score 集成（v1 + v2）

    @Test("score · 同时填 v1 + v2（subScores 非 nil · totalScore 算法不变）")
    func test_score_v1_v2_integration() {
        let s = session(initial: 100_000, final: 105_000, errors: 1, warnings: 2)
        let result = TrainingScorer.score(s)
        // v1 主分仍是老算法（+5% → pnl 40 / 1err+2warn → disc 50-10-6=34 / total 74）
        #expect(result.totalScore == 74)
        #expect(result.pnlScore == 40)
        #expect(result.disciplineScore == 34)
        // v2 subScores 已填
        #expect(result.subScores != nil)
        #expect(result.subScores?.pnl == 80)        // +5% 在 100 制下属 80（>2% 阶梯）
        #expect(result.subScores?.discipline == 68) // 100 - 20 - 12
    }

    // MARK: - Codable 兼容老 JSON

    @Test("TrainingSubScores · Codable round-trip")
    func test_subScores_codable() throws {
        let sub = TrainingSubScores(
            pnl: 80, discipline: 70, winRate: 60, risk: 50, efficiency: 40,
            weakest: .efficiency,
            weakness: "效率分最低 · 减少 over-trading"
        )
        let data = try JSONEncoder().encode(sub)
        let decoded = try JSONDecoder().decode(TrainingSubScores.self, from: data)
        #expect(decoded == sub)
    }

    @Test("TrainingScore · 老 JSON（无 subScores 字段）→ subScores=nil（不抛）")
    func test_trainingScore_oldJsonCompat() throws {
        let oldJson = #"""
        {"totalScore":74,"pnlScore":40,"disciplineScore":34,"grade":"B","summary":"sample"}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TrainingScore.self, from: oldJson)
        #expect(decoded.totalScore == 74)
        #expect(decoded.subScores == nil)
    }

    @Test("TrainingScore · subScores 非 nil 时 encode 输出含 subScores key")
    func test_trainingScore_encodeSubScores() throws {
        let sub = TrainingSubScores(
            pnl: 80, discipline: 70, winRate: 60, risk: 50, efficiency: 40,
            weakest: .efficiency, weakness: "test"
        )
        let score = TrainingScore(totalScore: 74, pnlScore: 40, disciplineScore: 34,
                                  grade: .B, summary: "x", subScores: sub)
        let data = try JSONEncoder().encode(score)
        let str = String(data: data, encoding: .utf8) ?? ""
        #expect(str.contains("subScores"))
        // round-trip
        let decoded = try JSONDecoder().decode(TrainingScore.self, from: data)
        #expect(decoded.subScores == sub)
    }

    @Test("TrainingScore · subScores=nil 时 encode 不输出 subScores key（diff 友好）")
    func test_trainingScore_omitNilSubScores() throws {
        let score = TrainingScore(totalScore: 50, pnlScore: 25, disciplineScore: 25,
                                  grade: .D, summary: "x")
        let data = try JSONEncoder().encode(score)
        let str = String(data: data, encoding: .utf8) ?? ""
        #expect(!str.contains("subScores"))
    }

    // MARK: - v16.56 · subScoreBreakdown drilldown 数据

    @Test("subScoreBreakdown · 空 session · 全部 0/中性")
    func test_breakdown_emptySession() {
        let s = session(initial: 100_000, final: 100_000)
        let b = TrainingScorer.subScoreBreakdown(s)
        #expect(b.pnlPct == 0)
        #expect(b.pnlV1 == 20)            // 0 → 20 阶梯
        #expect(b.errorCount == 0)
        #expect(b.warningCount == 0)
        #expect(b.disciplineV1 == 50)
        #expect(b.tradeCount == 0)
        #expect(b.pairCount == 0)
        #expect(b.winCount == 0)
        #expect(b.worstLoss == 0)
        #expect(b.totalPairPnL == 0)
        #expect(b.initialBalance == 100_000)
    }

    @Test("subScoreBreakdown · 1 盈利 + 1 亏损 · 配对/胜率/最大亏损 计算正确")
    func test_breakdown_mixedPairs() {
        let trades: [TradeRecord] = [
            openTrade("a", price: 100, volume: 1),
            closeTrade("b", price: 110, volume: 1),  // +10
            openTrade("c", price: 100, volume: 1),
            closeTrade("d", price: 95, volume: 1),   // -5
        ]
        let s = session(initial: 1000, final: 1005, trades: trades)
        let b = TrainingScorer.subScoreBreakdown(s)
        #expect(b.pairCount == 2)
        #expect(b.winCount == 1)
        #expect(b.worstLoss == 5)
        #expect(b.worstLossPct == 0.5)    // 5/1000*100
        #expect(b.totalPairPnL == 5)
        #expect(b.tradeCount == 4)
    }

    @Test("subScoreBreakdown · 违规计数与 v1 sub score 一致")
    func test_breakdown_violationCount() {
        let s = session(errors: 2, warnings: 3)
        let b = TrainingScorer.subScoreBreakdown(s)
        #expect(b.errorCount == 2)
        #expect(b.warningCount == 3)
        // 50 - 2×10 - 3×3 = 21
        #expect(b.disciplineV1 == 21)
    }

    @Test("subScoreBreakdown · 与 computeSubScores 同源（防漂移）")
    func test_breakdown_consistentWithSubScores() {
        let trades: [TradeRecord] = [
            openTrade("a", price: 100, volume: 1),
            closeTrade("b", price: 102, volume: 1),
        ]
        let s = session(initial: 1000, final: 1002, trades: trades, errors: 1)
        let b = TrainingScorer.subScoreBreakdown(s)
        let sub = TrainingScorer.computeSubScores(s)
        // discipline v1 ×2 必须等于 sub.discipline
        #expect(b.disciplineV1 * 2 == sub.discipline)
        // pnl v1 ×2 必须等于 sub.pnl
        #expect(b.pnlV1 * 2 == sub.pnl)
    }

    // MARK: - v16.147 · improvementPlan 5 步行动建议

    @Test("improvementPlan · 5 维全部返回 5 步行动")
    func test_improvementPlan_allDimsHave5Steps() {
        for dim in TrainingSubScores.Dimension.allCases {
            let plan = TrainingScorer.improvementPlan(for: dim, score: 30)
            #expect(plan.count == 5, "\(dim) 应返回 5 步")
            #expect(plan.allSatisfy { !$0.isEmpty }, "\(dim) 行动建议不应为空")
        }
    }

    @Test("improvementPlan · pnl 维度建议含信号 / 止盈关键词")
    func test_improvementPlan_pnlKeywords() {
        let plan = TrainingScorer.improvementPlan(for: .pnl, score: 20)
        let joined = plan.joined(separator: "\n")
        #expect(joined.contains("信号"))
        #expect(joined.contains("止盈"))
    }

    @Test("improvementPlan · discipline 维度建议含止损 / 计划关键词")
    func test_improvementPlan_disciplineKeywords() {
        let plan = TrainingScorer.improvementPlan(for: .discipline, score: 25)
        let joined = plan.joined(separator: "\n")
        #expect(joined.contains("止损"))
        #expect(joined.contains("计划"))
    }

    @Test("improvementPlan · risk 维度建议含 1% 仓位硬上限")
    func test_improvementPlan_riskHardCap() {
        let plan = TrainingScorer.improvementPlan(for: .risk, score: 10)
        let joined = plan.joined(separator: "\n")
        #expect(joined.contains("1%"))
        #expect(joined.contains("仓位"))
    }
}
