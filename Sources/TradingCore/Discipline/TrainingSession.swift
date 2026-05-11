// WP-54 v15.23 batch5 / v16.6 评分 v2 · 模拟训练 session 数据模型 + 评分系统（M5 节点）
//
// 设计：
// - TrainingSession：一次训练完整记录（时间/资金/trades/violations）
// - TrainingScore：百分制评分（盈亏 50 + 纪律 50）+ 5 等级（S/A/B/C/D）+ 评价文案 + v2 subScores
// - TrainingScorer：纯函数评分器（不依赖外部状态 · 测试友好）
//
// 评分公式（v1 主分 · 历史兼容不动）：
// - pnlScore (0-50)：按盈亏百分比阶梯（>5% 50 / >2% 40 / >0 30 / =0 20 / >-2% 10 / else 0）
// - disciplineScore (0-50)：50 - error×10 - warning×3 · clamp [0, 50]
// - 总分 = pnlScore + disciplineScore（0-100）· 等级 S(≥90)/A(≥80)/B(≥70)/C(≥60)/D(<60)
//
// v2 五维细分（v16.6 · 仅作分析视角 · 不参与 totalScore 加和 · 兼容老 JSON）：
// - pnl / discipline / winRate / risk / efficiency 各 0-100
// - winRate / risk / efficiency 由 trades FIFO 配对（合约+方向）派生 closedPositions 算
// - weakness：5 维最低者 · 中文改进建议（trader 看分知道改哪里）

import Foundation
import Shared

/// 一次模拟训练 session
public struct TrainingSession: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let initialBalance: Decimal
    public let finalBalance: Decimal
    public let trades: [TradeRecord]
    public let violations: [DisciplineViolation]
    public let scenarioName: String        // 训练场景名（如"螺纹钢急涨急跌 2020-08-12"）
    /// v15.23 batch118 · 训练场景形态（用于 history panel mini thumbnail · Optional 兼容老 session JSON）
    public let scenarioPattern: TrainingScenarioPattern?

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date,
                initialBalance: Decimal, finalBalance: Decimal,
                trades: [TradeRecord] = [], violations: [DisciplineViolation] = [],
                scenarioName: String = "",
                scenarioPattern: TrainingScenarioPattern? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.initialBalance = initialBalance
        self.finalBalance = finalBalance
        self.trades = trades
        self.violations = violations
        self.scenarioName = scenarioName
        self.scenarioPattern = scenarioPattern
    }

    public var pnl: Decimal { finalBalance - initialBalance }

    public var pnlPercent: Decimal {
        guard initialBalance > 0 else { return 0 }
        return (pnl / initialBalance) * 100
    }

    public var durationMinutes: Int {
        Int(endedAt.timeIntervalSince(startedAt) / 60)
    }
}

/// v2 评分五维（每维 0-100 · 仅作分析视角 · 不参与 totalScore 加和）
public struct TrainingSubScores: Sendable, Codable, Equatable {
    public let pnl: Int          // 盈亏率维度
    public let discipline: Int   // 纪律维度
    public let winRate: Int      // 胜率维度（trades FIFO 配对派生）
    public let risk: Int         // 风险控制维度（单笔最大亏损 vs initialBalance）
    public let efficiency: Int   // 效率维度（每笔平仓平均 pnl%）
    /// 最弱维度（5 维最低者 · 用于 weakness 提示）
    public let weakest: Dimension
    /// 最弱维度的中文改进建议
    public let weakness: String

    public enum Dimension: String, Sendable, Equatable, Codable, CaseIterable {
        case pnl, discipline, winRate, risk, efficiency

        public var displayName: String {
            switch self {
            case .pnl:        return "盈亏"
            case .discipline: return "纪律"
            case .winRate:    return "胜率"
            case .risk:       return "风险"
            case .efficiency: return "效率"
            }
        }

        public var emoji: String {
            switch self {
            case .pnl:        return "💰"
            case .discipline: return "📋"
            case .winRate:    return "🎯"
            case .risk:       return "🛡️"
            case .efficiency: return "⚡"
            }
        }
    }

    public init(pnl: Int, discipline: Int, winRate: Int, risk: Int, efficiency: Int,
                weakest: Dimension, weakness: String) {
        self.pnl = pnl
        self.discipline = discipline
        self.winRate = winRate
        self.risk = risk
        self.efficiency = efficiency
        self.weakest = weakest
        self.weakness = weakness
    }

    /// 5 维分数有序数组（用于 UI 雷达图 / 遍历显示）
    public var ordered: [(dimension: Dimension, score: Int)] {
        [(.pnl, pnl), (.discipline, discipline), (.winRate, winRate),
         (.risk, risk), (.efficiency, efficiency)]
    }
}

/// 训练评分结果
public struct TrainingScore: Sendable, Codable, Equatable {
    public let totalScore: Int          // 0-100
    public let pnlScore: Int            // 0-50（v1 主分 · 兼容历史）
    public let disciplineScore: Int     // 0-50（v1 主分 · 兼容历史）
    public let grade: Grade
    public let summary: String
    /// v16.6 评分 v2 · 五维细分（老 JSON 反序列化为 nil · UI 兜底显示老二维）
    public let subScores: TrainingSubScores?

    public enum Grade: String, Sendable, Equatable, Codable, CaseIterable {
        case S, A, B, C, D

        public var displayName: String { rawValue }

        public var emoji: String {
            switch self {
            case .S: return "🏆"
            case .A: return "🥇"
            case .B: return "🥈"
            case .C: return "🥉"
            case .D: return "📉"
            }
        }
    }

    public init(totalScore: Int, pnlScore: Int, disciplineScore: Int,
                grade: Grade, summary: String,
                subScores: TrainingSubScores? = nil) {
        self.totalScore = totalScore
        self.pnlScore = pnlScore
        self.disciplineScore = disciplineScore
        self.grade = grade
        self.summary = summary
        self.subScores = subScores
    }

    // Codable 由编译器合成：subScores 为 Optional → decode/encodeIfPresent
    // 老 JSON 缺 subScores key 自动 decode 成 nil；nil 时 encode 不输出 key（diff 友好）
}

/// 纯函数评分器
public enum TrainingScorer {

    /// 评分入口 · 输入 session 输出完整 TrainingScore（含 v2 五维 subScores）
    public static func score(_ session: TrainingSession) -> TrainingScore {
        let pnl = pnlSubScore(session)
        let disc = disciplineSubScore(session)
        let total = pnl + disc
        let grade = gradeFor(total)
        let summary = buildSummary(session: session, total: total, pnl: pnl, disc: disc)
        let sub = computeSubScores(session)
        return TrainingScore(totalScore: total, pnlScore: pnl,
                             disciplineScore: disc, grade: grade, summary: summary,
                             subScores: sub)
    }

    // MARK: - v1 子分（兼容历史 · 总分含义不变）

    /// pnl 阶梯（0-50）
    static func pnlSubScore(_ session: TrainingSession) -> Int {
        let pct = (session.pnlPercent as NSDecimalNumber).doubleValue
        if pct > 5 { return 50 }
        if pct > 2 { return 40 }
        if pct > 0 { return 30 }
        if pct == 0 { return 20 }
        if pct > -2 { return 10 }
        return 0
    }

    /// 纪律子分（50 - error×10 - warning×3 · clamp）
    static func disciplineSubScore(_ session: TrainingSession) -> Int {
        let errors = session.violations.filter { $0.severity == .error }.count
        let warnings = session.violations.filter { $0.severity == .warning }.count
        return max(0, min(50, 50 - errors * 10 - warnings * 3))
    }

    static func gradeFor(_ totalScore: Int) -> TrainingScore.Grade {
        switch totalScore {
        case 90...:    return .S
        case 80..<90:  return .A
        case 70..<80:  return .B
        case 60..<70:  return .C
        default:       return .D
        }
    }

    static func buildSummary(session: TrainingSession, total: Int, pnl: Int, disc: Int) -> String {
        let pnlPct = String(format: "%.2f", (session.pnlPercent as NSDecimalNumber).doubleValue)
        let errors = session.violations.filter { $0.severity == .error }.count
        let warnings = session.violations.filter { $0.severity == .warning }.count
        return "总分 \(total)（盈亏 \(pnl)/50 · 纪律 \(disc)/50）· 盈亏率 \(pnlPct)% · \(errors) 违规 + \(warnings) 警告 · \(session.trades.count) 笔交易"
    }

    // MARK: - v2 五维子分（v16.6 · 仅分析视角 · 不参与 totalScore）

    /// 计算 5 维子分 + weakness 提示
    public static func computeSubScores(_ session: TrainingSession) -> TrainingSubScores {
        let pnl = pnlScore100(session)
        let disc = disciplineScore100(session)
        let pairs = closedPairs(from: session.trades)
        let win = winRateScore100(pairs: pairs)
        let risk = riskScore100(pairs: pairs, initialBalance: session.initialBalance)
        let eff = efficiencyScore100(pairs: pairs, initialBalance: session.initialBalance)
        // 维度顺序（pnl/discipline/winRate/risk/efficiency）即同分时 weakest 落 first 的隐性约定
        // min(by:) 在 < 严格比较下保留先到的元素，正好匹配此约定
        let dimensions: [(dimension: TrainingSubScores.Dimension, score: Int)] = [
            (.pnl, pnl), (.discipline, disc), (.winRate, win),
            (.risk, risk), (.efficiency, eff),
        ]
        let weakest = dimensions.min(by: { $0.score < $1.score }) ?? (.pnl, pnl)
        return TrainingSubScores(
            pnl: pnl, discipline: disc, winRate: win, risk: risk, efficiency: eff,
            weakest: weakest.dimension,
            weakness: weaknessAdvice(for: weakest.dimension, score: weakest.score)
        )
    }

    /// 盈亏维度 0-100 · 老阶梯 ×2（保证两套阶梯始终同步 · 改 v1 自动反映到 v2）
    static func pnlScore100(_ session: TrainingSession) -> Int {
        pnlSubScore(session) * 2
    }

    /// 纪律维度 0-100 · 老公式 ×2（系数与 clamp 上限同步翻倍 · 数学等价）
    static func disciplineScore100(_ session: TrainingSession) -> Int {
        disciplineSubScore(session) * 2
    }

    /// 胜率维度 0-100：closed pairs 中 pnl > 0 的比例 ×100 · 无 pair → 50（中性）
    static func winRateScore100(pairs: [ClosedPair]) -> Int {
        guard !pairs.isEmpty else { return 50 }
        let wins = pairs.filter { $0.pnl > 0 }.count
        return Int(round(Double(wins) / Double(pairs.count) * 100))
    }

    /// 风险维度 0-100：单笔最大亏损率 · 0% → 100 / 5%+ → 0 · 无 pair → 50
    static func riskScore100(pairs: [ClosedPair], initialBalance: Decimal) -> Int {
        guard !pairs.isEmpty, initialBalance > 0 else { return 50 }
        let principalDouble = (initialBalance as NSDecimalNumber).doubleValue
        let worstLoss = pairs.map { (-($0.pnl as NSDecimalNumber).doubleValue) }.max() ?? 0
        let lossPct = max(0, worstLoss) / principalDouble * 100
        if lossPct >= 5 { return 0 }
        return Int(round((1.0 - lossPct / 5.0) * 100))
    }

    /// 效率维度 0-100：平均每笔 pnl% · 0.5%+ → 100 / 0 → 50 / -0.5%+ → 0 · 无 pair → 50
    static func efficiencyScore100(pairs: [ClosedPair], initialBalance: Decimal) -> Int {
        guard !pairs.isEmpty, initialBalance > 0 else { return 50 }
        let principalDouble = (initialBalance as NSDecimalNumber).doubleValue
        let totalPnL = pairs.reduce(0.0) { $0 + ($1.pnl as NSDecimalNumber).doubleValue }
        let avgPct = totalPnL / Double(pairs.count) / principalDouble * 100
        let clamped = max(-0.5, min(0.5, avgPct))
        return Int(round((clamped + 0.5) * 100))
    }

    // MARK: - v16.56 · 5 维主分 drilldown 原始数据（trader 点击主分行展开看本次具体计算）

    /// 5 维评分本次计算原始数据（view 层展开行渲染）· 不含格式化，纯数字。
    public struct SubScoreBreakdown: Sendable, Equatable {
        public let pnlPct: Double           // session.pnlPercent
        public let pnlV1: Int               // pnlSubScore 0-50
        public let errorCount: Int
        public let warningCount: Int
        public let disciplineV1: Int        // disciplineSubScore 0-50
        public let tradeCount: Int          // session.trades.count
        public let pairCount: Int
        public let winCount: Int
        public let worstLoss: Double        // 单笔最大亏损（正数 · 无亏损 = 0）
        public let worstLossPct: Double     // 占初始资金 %
        public let totalPairPnL: Double     // 配对总盈亏
        public let avgPairPnLPct: Double    // 平均每笔 pnl% （未 clamp）
        public let initialBalance: Double
    }

    /// 计算 drilldown 数据（与 computeSubScores 同源 · 防漂移）
    public static func subScoreBreakdown(_ session: TrainingSession) -> SubScoreBreakdown {
        let pairs = closedPairs(from: session.trades)
        let errors = session.violations.filter { $0.severity == .error }.count
        let warnings = session.violations.filter { $0.severity == .warning }.count
        let principal = (session.initialBalance as NSDecimalNumber).doubleValue
        let pairPnLs = pairs.map { ($0.pnl as NSDecimalNumber).doubleValue }
        // 避免 -0.0 IEEE 符号污染 CSV 输出（"-0.00"）
        let worstLossRaw = pairPnLs.min() ?? 0
        let worstLoss = worstLossRaw < 0 ? -worstLossRaw : 0
        let worstLossPct = principal > 0 ? worstLoss / principal * 100 : 0
        let total = pairPnLs.reduce(0, +)
        let avgPct: Double = {
            guard !pairs.isEmpty, principal > 0 else { return 0 }
            return total / Double(pairs.count) / principal * 100
        }()
        return SubScoreBreakdown(
            pnlPct: (session.pnlPercent as NSDecimalNumber).doubleValue,
            pnlV1: pnlSubScore(session),
            errorCount: errors,
            warningCount: warnings,
            disciplineV1: disciplineSubScore(session),
            tradeCount: session.trades.count,
            pairCount: pairs.count,
            winCount: pairs.filter { $0.pnl > 0 }.count,
            worstLoss: worstLoss,
            worstLossPct: worstLossPct,
            totalPairPnL: total,
            avgPairPnLPct: avgPct,
            initialBalance: principal
        )
    }

    static func weaknessAdvice(for dim: TrainingSubScores.Dimension, score: Int) -> String {
        switch dim {
        case .pnl:
            return "盈亏分最低 · 复盘交易决策时机 · 建议先观察更明确信号再入场"
        case .discipline:
            return "纪律分最低 · 严守止损规则与持仓时长上限 · 减少冲动单"
        case .winRate:
            return "胜率分最低 · 减少试探单 · 等更强信号入场（信号源/RSI/形态确认）"
        case .risk:
            return "风险分最低 · 单笔亏损过大 · 缩小仓位 + 严守止损（建议 ≤ 1% 单笔风险）"
        case .efficiency:
            return "效率分最低 · 每笔平均贡献过低 · 减少 over-trading · 一笔吃透行情"
        }
    }

    // MARK: - trades FIFO 配对派生 closedPositions（合约+方向 · 简化 · 不算手续费）

    /// 一对开-平仓（同合约同方向 FIFO 配对 · pnl 含方向修正 · 不含手续费）
    public struct ClosedPair: Sendable, Equatable {
        public let instrumentID: String
        public let direction: Direction
        public let openPrice: Decimal
        public let closePrice: Decimal
        public let volume: Int
        public var pnl: Decimal {
            // long: (close - open) * vol · short: (open - close) * vol
            let diff = (direction == .buy) ? (closePrice - openPrice) : (openPrice - closePrice)
            return diff * Decimal(volume)
        }
    }

    /// trades FIFO 配对（同合约同方向 · 时间序）· 部分平仓自动拆分 · open/close 不平衡时余下 open 忽略
    static func closedPairs(from trades: [TradeRecord]) -> [ClosedPair] {
        struct OpenLot { let price: Decimal; var remaining: Int }
        var queues: [String: [OpenLot]] = [:]   // key = "instrumentID:directionRaw"
        var pairs: [ClosedPair] = []
        for trade in trades {
            let key = "\(trade.instrumentID):\(trade.direction.rawValue)"
            if trade.offsetFlag == .open {
                queues[key, default: []].append(OpenLot(price: trade.price, remaining: trade.volume))
            } else {
                var remainingClose = trade.volume
                while remainingClose > 0, var lots = queues[key], !lots.isEmpty {
                    let take = min(lots[0].remaining, remainingClose)
                    pairs.append(ClosedPair(
                        instrumentID: trade.instrumentID,
                        direction: trade.direction,
                        openPrice: lots[0].price,
                        closePrice: trade.price,
                        volume: take
                    ))
                    lots[0].remaining -= take
                    remainingClose -= take
                    if lots[0].remaining == 0 { lots.removeFirst() }
                    queues[key] = lots
                }
            }
        }
        return pairs
    }
}
