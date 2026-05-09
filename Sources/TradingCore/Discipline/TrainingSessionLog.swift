// WP-54 v15.23 batch7 · 训练 session 历史集合 + 统计（Codable 持久化）
//
// 设计：
// - 持有 [TrainingSession] + 缓存评分 [UUID: TrainingScore]（避免每次重算 · 但 score 是纯函数 · 留接口给将来扩展）
// - CRUD：addSession（自动评分缓存）/ removeSession / clear
// - 统计：averageScore / bestScore / gradeDistribution / recentSessions(limit:)
// - Codable round-trip 支持（未来接 viewState.v1 / SQLite 持久化）

import Foundation

public struct TrainingSessionLog: Sendable, Equatable, Codable {
    public private(set) var sessions: [TrainingSession]
    public private(set) var scores: [UUID: TrainingScore]

    public init(sessions: [TrainingSession] = [], scores: [UUID: TrainingScore] = [:]) {
        self.sessions = sessions
        self.scores = scores
    }

    // MARK: - CRUD

    /// 添加 session · 自动评分并缓存
    public mutating func addSession(_ session: TrainingSession) {
        // 同 id 覆盖（防重复 add）
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        scores[session.id] = TrainingScorer.score(session)
    }

    public mutating func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        scores.removeValue(forKey: id)
    }

    public mutating func clear() {
        sessions.removeAll()
        scores.removeAll()
    }

    // MARK: - 查询 helpers

    public func session(id: UUID) -> TrainingSession? {
        sessions.first { $0.id == id }
    }

    public func score(for sessionID: UUID) -> TrainingScore? {
        scores[sessionID]
    }

    /// 最近 N 次（按 endedAt 降序 · trader 训练首页常用）
    public func recentSessions(limit: Int) -> [TrainingSession] {
        sessions.sorted { $0.endedAt > $1.endedAt }.prefix(max(0, limit)).map { $0 }
    }

    // MARK: - 统计

    /// 平均总分（无 session 返回 0）
    public var averageScore: Double {
        guard !scores.isEmpty else { return 0 }
        let sum = scores.values.reduce(0) { $0 + $1.totalScore }
        return Double(sum) / Double(scores.count)
    }

    /// 最高分（无 session 返回 nil）
    public var bestScore: TrainingScore? {
        scores.values.max { $0.totalScore < $1.totalScore }
    }

    /// 等级分布（缺失等级值为 0 · 全部 5 等级 key 都返回）
    public var gradeDistribution: [TrainingScore.Grade: Int] {
        var dist: [TrainingScore.Grade: Int] = [:]
        for grade in TrainingScore.Grade.allCases { dist[grade] = 0 }
        for s in scores.values { dist[s.grade, default: 0] += 1 }
        return dist
    }

    /// 总训练次数
    public var sessionCount: Int { sessions.count }

    /// v15.23 batch135 · 当前连胜/连败 streak
    /// - count: 连续次数（≥ 1）· 0 表示无 session
    /// - isWinning: true = 连胜 / false = 连败
    /// - 胜负阈值：score ≥ 70（B 级以上算胜）· 可后续调整
    public var currentStreak: (count: Int, isWinning: Bool) {
        let recent = sessions.sorted { $0.endedAt > $1.endedAt }
        guard !recent.isEmpty else { return (0, false) }
        let firstScore = score(for: recent[0].id)?.totalScore ?? 0
        let firstIsWin = firstScore >= 70
        var count = 1
        for i in 1..<recent.count {
            let s = score(for: recent[i].id)?.totalScore ?? 0
            let isWin = s >= 70
            if isWin == firstIsWin { count += 1 } else { break }
        }
        return (count, firstIsWin)
    }

    // MARK: - v16.13 · 同形态历史对比（score sheet 显示提升趋势）

    /// 计算 sessionID 对应同形态的历史对比（不含 sessionID 自己）
    /// 返回 nil 条件：sessionID 不存在 / 无 scenarioPattern / 无 score
    public func patternComparison(for sessionID: UUID) -> PatternComparison? {
        guard let target = session(id: sessionID),
              let pattern = target.scenarioPattern,
              let currentScore = score(for: sessionID)?.totalScore else { return nil }
        let priorScores = sessions
            .filter { $0.id != sessionID && $0.scenarioPattern == pattern }
            .compactMap { score(for: $0.id)?.totalScore }
        let priorAvg = priorScores.isEmpty ? 0.0
                       : Double(priorScores.reduce(0, +)) / Double(priorScores.count)
        return PatternComparison(
            pattern: pattern,
            priorCount: priorScores.count,
            priorAverageScore: priorAvg,
            priorBestScore: priorScores.max() ?? 0,
            currentScore: currentScore
        )
    }
}

/// v16.13 · 同形态历史对比结果（trader 看分时回报"同形态 5 次 平均 75 ↑（提升 +7）"）
public struct PatternComparison: Sendable, Equatable {
    public let pattern: TrainingScenarioPattern
    public let priorCount: Int               // 不含当前 session
    public let priorAverageScore: Double     // 历史均值（priorCount=0 时为 0）
    public let priorBestScore: Int           // 历史最佳（priorCount=0 时为 0）
    public let currentScore: Int

    public init(pattern: TrainingScenarioPattern, priorCount: Int,
                priorAverageScore: Double, priorBestScore: Int, currentScore: Int) {
        self.pattern = pattern
        self.priorCount = priorCount
        self.priorAverageScore = priorAverageScore
        self.priorBestScore = priorBestScore
        self.currentScore = currentScore
    }

    /// 当前分相对历史均值的趋势
    public var trendVsAverage: Trend {
        Trend.compute(current: currentScore, baseline: Int(priorAverageScore.rounded()), priorCount: priorCount)
    }

    /// 当前分相对历史最佳的趋势（用于"创新高"提示）
    public var isNewBest: Bool {
        priorCount > 0 && currentScore > priorBestScore
    }

    /// 当前分 vs 历史均值的差额（priorCount=0 时为 0）
    public var deltaVsAverage: Int {
        guard priorCount > 0 else { return 0 }
        return currentScore - Int(priorAverageScore.rounded())
    }

    public enum Trend: String, Sendable, Equatable {
        case up        // 高于均值 ≥ 3 分
        case down      // 低于均值 ≥ 3 分
        case flat      // 接近均值（|diff| < 3）
        case firstTime // 历史无同形态记录

        public static func compute(current: Int, baseline: Int, priorCount: Int) -> Trend {
            guard priorCount > 0 else { return .firstTime }
            let diff = current - baseline
            if abs(diff) < 3 { return .flat }
            return diff > 0 ? .up : .down
        }

        public var emoji: String {
            switch self {
            case .up:        return "↑"
            case .down:      return "↓"
            case .flat:      return "→"
            case .firstTime: return "✨"
            }
        }
    }
}
