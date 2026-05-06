// WP-54 v15.23 batch5 · 模拟训练 session 数据模型 + 评分系统（M5 节点）
//
// 设计：
// - TrainingSession：一次训练完整记录（时间/资金/trades/violations）
// - TrainingScore：百分制评分（盈亏 50 + 纪律 50）+ 5 等级（S/A/B/C/D）+ 评价文案
// - TrainingScorer：纯函数评分器（不依赖外部状态 · 测试友好）
//
// 评分公式（最小可用版 · batch5）：
// - pnlScore (0-50)：按盈亏百分比阶梯（>5% 50 / >2% 40 / >0 30 / =0 20 / <-2% 0）
// - disciplineScore (0-50)：50 - error×10 - warning×3 · clamp [0, 50]
// - 总分 = pnlScore + disciplineScore（0-100）· 等级 S(≥90)/A(≥80)/B(≥70)/C(≥60)/D(<60)

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

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date,
                initialBalance: Decimal, finalBalance: Decimal,
                trades: [TradeRecord] = [], violations: [DisciplineViolation] = [],
                scenarioName: String = "") {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.initialBalance = initialBalance
        self.finalBalance = finalBalance
        self.trades = trades
        self.violations = violations
        self.scenarioName = scenarioName
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

/// 训练评分结果
public struct TrainingScore: Sendable, Codable, Equatable {
    public let totalScore: Int          // 0-100
    public let pnlScore: Int            // 0-50
    public let disciplineScore: Int     // 0-50
    public let grade: Grade
    public let summary: String

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
                grade: Grade, summary: String) {
        self.totalScore = totalScore
        self.pnlScore = pnlScore
        self.disciplineScore = disciplineScore
        self.grade = grade
        self.summary = summary
    }
}

/// 纯函数评分器
public enum TrainingScorer {

    /// 评分入口 · 输入 session 输出完整 TrainingScore
    public static func score(_ session: TrainingSession) -> TrainingScore {
        let pnl = pnlSubScore(session)
        let disc = disciplineSubScore(session)
        let total = pnl + disc
        let grade = gradeFor(total)
        let summary = buildSummary(session: session, total: total, pnl: pnl, disc: disc)
        return TrainingScore(totalScore: total, pnlScore: pnl,
                             disciplineScore: disc, grade: grade, summary: summary)
    }

    // MARK: - 子分

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
}
