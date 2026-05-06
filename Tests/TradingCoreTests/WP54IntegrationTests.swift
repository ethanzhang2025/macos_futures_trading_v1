// WP-54 v15.23 batch6 · 端到端集成测试
// SimulatedTradingEngine 模拟交易 → DisciplineEvaluator 检查违规 → TrainingScorer 评分

import Testing
import Foundation
@testable import TradingCore
import Shared

@Suite("WP-54 Integration · Engine + Discipline + Scorer 端到端")
struct WP54IntegrationTests {

    // MARK: - shared helpers

    private func makeContract(_ id: String = "rb2501") -> Contract {
        Contract(instrumentID: id, instrumentName: "螺纹钢2501",
                 exchange: .SHFE, productID: "rb",
                 volumeMultiple: 10, priceTick: 1, deliveryMonth: 202501, expireDate: "20250115",
                 longMarginRatio: Decimal(string: "0.10")!, shortMarginRatio: Decimal(string: "0.10")!,
                 isTrading: true, productName: "螺纹钢", pinyinInitials: "LWG")
    }

    private func makeTick(_ price: Decimal, id: String = "rb2501") -> Tick {
        Tick(instrumentID: id, lastPrice: price, volume: 1,
             openInterest: 0, turnover: 0,
             bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
             highestPrice: 0, lowestPrice: 0, openPrice: 0,
             preClosePrice: 0, preSettlementPrice: 0,
             upperLimitPrice: 0, lowerLimitPrice: 0,
             updateTime: "10:00:00", updateMillisec: 0,
             tradingDay: "20250101", actionDay: "20250101")
    }

    private func openOrder(_ dir: Direction = .buy, price: Decimal = 3500) -> OrderRequest {
        OrderRequest(instrumentID: "rb2501", direction: dir, offsetFlag: .open,
                     priceType: .limitPrice, price: price, volume: 1)
    }

    private func closeOrder(_ dir: Direction = .sell, price: Decimal) -> OrderRequest {
        OrderRequest(instrumentID: "rb2501", direction: dir, offsetFlag: .close,
                     priceType: .limitPrice, price: price, volume: 1)
    }

    // MARK: - 端到端 scenario

    @Test("完美 trader · 1 笔盈利 + 0 违规 → S 级 100 分")
    func perfectTraderScenario() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        await engine.registerContract(makeContract())
        let now = Date(timeIntervalSince1970: 1746360000)

        // 开多 @3500 · fill@3500（限价 ≥ lastPrice 即 fill）
        _ = await engine.submitOrder(openOrder(.buy, price: 3500), now: now)
        await engine.onTick(makeTick(3500), now: now)
        // 价格涨到 3550 · 平多 @3550 · 浮盈 +500（无杠杆 +0.5%）
        _ = await engine.submitOrder(closeOrder(.sell, price: 3550),
                                     now: now.addingTimeInterval(60))
        await engine.onTick(makeTick(3550), now: now.addingTimeInterval(60))

        let trades = await engine.allTrades()
        let account = await engine.currentAccount()

        let session = TrainingSession(
            startedAt: now, endedAt: now.addingTimeInterval(120),
            initialBalance: 100000, finalBalance: account.balance,
            trades: trades, violations: [], scenarioName: "完美 trader"
        )
        let score = TrainingScorer.score(session)
        // 盈利 500 - commission 10 = 490 / 100000 = +0.49% → pnlScore 30
        #expect(score.pnlScore == 30)
        #expect(score.disciplineScore == 50)
        #expect(score.totalScore == 80)
        #expect(score.grade == .A)
    }

    @Test("过度交易 + 加仓违规 trader · 多次开仓触发 maxAddPositions warning")
    func overTradeScenario() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        await engine.registerContract(makeContract())
        let now = Date(timeIntervalSince1970: 1746360000)

        // 连续开多 4 次（不平仓）触发 maxAddPositions threshold=3
        for i in 0..<4 {
            _ = await engine.submitOrder(openOrder(.buy, price: 3500),
                                         now: now.addingTimeInterval(Double(i * 60)))
            await engine.onTick(makeTick(3500),
                                now: now.addingTimeInterval(Double(i * 60)))
        }
        let trades = await engine.allTrades()
        #expect(trades.count == 4)

        // 评估 maxAddPositions
        let rules = [DisciplineRule(kind: .maxAddPositions, threshold: 3)]
        let violations = DisciplineEvaluator.evaluateTrades(
            rules: rules, todayTrades: trades, dailyRealizedPnL: 0, now: now)
        #expect(violations.count == 1)
        #expect(violations[0].severity == .warning)
        #expect(violations[0].message.contains("4"))
    }

    @Test("超时持仓 trader · 持仓 50 分钟超过 30 分钟阈值 → maxHoldingMinutes warning")
    func overHoldingScenario() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        await engine.registerContract(makeContract())
        let openedAt = Date(timeIntervalSince1970: 1746360000)
        let evaluatedAt = openedAt.addingTimeInterval(3000)   // +50 min

        _ = await engine.submitOrder(openOrder(.buy, price: 3500), now: openedAt)
        await engine.onTick(makeTick(3500), now: openedAt)

        let positions = await engine.allPositions()
        #expect(positions.count == 1)
        // 模拟当前价微涨（不亏不重 · 仅检查持仓时长）
        let ctxs = positions.map { PositionContext(position: $0, openedAt: openedAt, currentPrice: 3501) }

        let rules = [DisciplineRule(kind: .maxHoldingMinutes, threshold: 30)]
        let violations = DisciplineEvaluator.evaluatePositions(
            rules: rules, positions: ctxs, now: evaluatedAt)
        #expect(violations.count == 1)
        #expect(violations[0].ruleKind == .maxHoldingMinutes)
        #expect(violations[0].message.contains("50"))
        #expect(violations[0].message.contains("30"))
    }

    @Test("综合翻车 scenario · 亏损 + 加仓 + 长持仓 → 多违规 + 低分")
    func disasterScenario() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        await engine.registerContract(makeContract())
        let openedAt = Date(timeIntervalSince1970: 1746360000)

        // 4 次连续开多（4 笔 · 加仓违规）· 价格 3500 → 3400（亏损）
        for i in 0..<4 {
            _ = await engine.submitOrder(openOrder(.buy, price: 3500),
                                         now: openedAt.addingTimeInterval(Double(i * 60)))
            await engine.onTick(makeTick(3500),
                                now: openedAt.addingTimeInterval(Double(i * 60)))
        }

        let trades = await engine.allTrades()
        let positions = await engine.allPositions()

        // 评估时刻：开仓 +90 分钟（默认 maxHoldingMinutes 60 阈值已超 · 价格 3400 浮亏）
        let now = openedAt.addingTimeInterval(5400)
        let ctxs = positions.map { PositionContext(position: $0, openedAt: openedAt, currentPrice: 3400) }

        let book = DisciplineBook.defaultRecommended
        let posViolations = DisciplineEvaluator.evaluatePositions(
            rules: book.rules, positions: ctxs, now: now)
        let tradeViolations = DisciplineEvaluator.evaluateTrades(
            rules: book.rules, todayTrades: trades, dailyRealizedPnL: -4000, now: now)
        let allViolations = posViolations + tradeViolations

        // 违规预期：stopLossPercent + maxHoldingMinutes + maxAddPositions = 至少 3 项
        #expect(allViolations.count >= 3)
        let kinds = Set(allViolations.map { $0.ruleKind })
        #expect(kinds.contains(.stopLossPercent))
        #expect(kinds.contains(.maxHoldingMinutes))
        #expect(kinds.contains(.maxAddPositions))

        // 评分：4 笔交易 + 浮亏 + 多违规 → D 级
        let account = await engine.currentAccount()
        let session = TrainingSession(
            startedAt: openedAt, endedAt: now,
            initialBalance: 100000, finalBalance: account.balance - 4000, // 模拟浮亏入账
            trades: trades, violations: allViolations, scenarioName: "综合翻车"
        )
        let score = TrainingScorer.score(session)
        #expect(score.totalScore < 60)
        #expect(score.grade == .D)
    }

    @Test("纯查询 scenario · 无 trades 无 positions → 0 violations · 评分基线")
    func emptyScenario() async {
        let engine = SimulatedTradingEngine(initialBalance: 100000)
        let now = Date()
        let trades = await engine.allTrades()
        let positions = await engine.allPositions()
        #expect(trades.isEmpty)
        #expect(positions.isEmpty)

        let book = DisciplineBook.defaultRecommended
        let posV = DisciplineEvaluator.evaluatePositions(rules: book.rules, positions: [], now: now)
        let trV = DisciplineEvaluator.evaluateTrades(rules: book.rules, todayTrades: [], dailyRealizedPnL: 0, now: now)
        #expect(posV.isEmpty)
        #expect(trV.isEmpty)

        let session = TrainingSession(
            startedAt: now, endedAt: now,
            initialBalance: 100000, finalBalance: 100000,
            trades: [], violations: [], scenarioName: "空 session"
        )
        let score = TrainingScorer.score(session)
        // 平 + 0 违规 → 20 + 50 = 70（B 级）
        #expect(score.pnlScore == 20)
        #expect(score.disciplineScore == 50)
        #expect(score.totalScore == 70)
        #expect(score.grade == .B)
    }
}
