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
}
