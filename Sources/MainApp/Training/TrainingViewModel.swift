// MainApp · WP-54 模拟训练 ViewModel（v15.23 batch9 · M5 节点 UI 收尾）
//
// 职责：
// - 持有 DisciplineBook（规则集 · trader 自定义 5 类纪律）
// - 持有 TrainingSessionLog（历史 session + 评分缓存）
// - 持有当前进行中 session 的累积状态（startedAt/initialBalance/violations/scenarioName）
// - 暴露 CRUD + Session 控制 + 推荐导入 4 类方法 · 子 Panel 共享同一 VM
//
// 设计要点：
// - @MainActor 保证 UI 线程一致 · @Published 触发 SwiftUI 刷新
// - book/log 为值类型副本（mutating 方法在本 VM 内统一封装）
// - inProgressSession 仅在 active 模式下有值 · endSession 关闭后清空并 push 到 log

#if canImport(SwiftUI) && os(macOS)

import Foundation
import SwiftUI
import Shared
import TradingCore

@MainActor
final class TrainingViewModel: ObservableObject {

    // MARK: - 持久化状态（值类型 · 等后续接 viewState.v1）

    @Published var book: DisciplineBook = .defaultRecommended
    @Published var log: TrainingSessionLog = TrainingLogPersistence.load() {
        didSet { TrainingLogPersistence.save(log) }
    }

    // MARK: - 进行中 session

    @Published var sessionStartedAt: Date? = nil
    @Published var sessionInitialBalance: Decimal = 0
    @Published var sessionScenarioName: String = ""
    /// v15.23 batch118 · 训练形态（preset 启动时记录 · history panel thumbnail 用）
    @Published var sessionScenarioPattern: TrainingScenarioPattern? = nil
    /// v15.23 batch138 · 推荐训练时长（来自 preset · 用于 ControlBar 进度条）· 自定义训练为 nil
    @Published var sessionRecommendedMinutes: Int? = nil
    @Published var liveViolations: [DisciplineViolation] = []
    /// v15.23 batch132 · 「再练同形态」请求（score sheet → controlBar 监听 · 触发后清回 nil）
    @Published var pendingRetrainPattern: TrainingScenarioPattern? = nil

    /// v16.46 · history panel mostViolatedRules chip 点击 → 跳 rules panel · TrainingWindow 监听清 nil
    @Published var pendingJumpToRulesTab: Bool = false

    /// v16.101 · ControlBar streak chip / 7 天 mini bar 点击 → 跳 history panel
    /// 与 pendingJumpToRulesTab 同模式 · TrainingWindow 监听切 tab + 清回 false
    @Published var pendingJumpToHistoryTab: Bool = false

    /// 训练结束后弹 sheet 用 · endSession 写入 · 关闭 sheet 清空
    @Published var lastFinishedSession: TrainingSession? = nil
    @Published var lastFinishedScore: TrainingScore? = nil

    /// v16.58 · 最近新加 session ID · dismiss sheet 时设 · HistoryPanel 监听高亮 5s + 自动 scroll
    /// 与 lastFinishedSession 分开持有：sheet 关闭后这个还保留 5s，trader 回到 history 能看清楚是哪条
    @Published var recentlyAddedSessionID: UUID? = nil

    var isSessionActive: Bool { sessionStartedAt != nil }

    // MARK: - v16.42 · 暂停/继续（trader 训练中接电话/上厕所 · elapsed 时钟暂停）

    /// 当前暂停的开始时间（nil = 未暂停 · 非 nil = 暂停中）
    @Published var sessionPausedAt: Date? = nil
    /// 累积暂停时长（多次暂停求和 · 用于扣减 elapsed）· session 结束清 0
    @Published var sessionAccumulatedPause: TimeInterval = 0

    var isSessionPaused: Bool { sessionPausedAt != nil }

    func pauseSession() {
        guard isSessionActive, sessionPausedAt == nil else { return }
        sessionPausedAt = Date()
    }

    func resumeSession() {
        guard let pausedAt = sessionPausedAt else { return }
        sessionAccumulatedPause += Date().timeIntervalSince(pausedAt)
        sessionPausedAt = nil
    }

    // MARK: - 规则 CRUD

    func addRule(_ rule: DisciplineRule) {
        book.addRule(rule)
    }

    func updateRule(_ rule: DisciplineRule) {
        book.updateRule(rule)
    }

    func removeRule(id: UUID) {
        book.removeRule(id: id)
    }

    func setEnabled(id: UUID, enabled: Bool) {
        book.setEnabled(id: id, enabled: enabled)
    }

    /// 导入 5 条推荐配置（覆盖当前 book）· 空 book 一键启用最常用
    func importRecommended() {
        book = .defaultRecommended
    }

    /// v16.43 · 直接覆盖整个 book（trader 切换风格模板用）
    func applyRuleTemplate(_ template: DisciplineBook) {
        book = template
    }

    /// 清空所有规则
    func clearRules() {
        book = DisciplineBook()
    }

    // MARK: - Session 控制（batch11 详细实现 · 此处仅占位接口）

    func startSession(initialBalance: Decimal, scenarioName: String,
                      scenarioPattern: TrainingScenarioPattern? = nil,
                      recommendedMinutes: Int? = nil) {
        sessionStartedAt = Date()
        sessionInitialBalance = initialBalance
        sessionScenarioName = scenarioName
        sessionScenarioPattern = scenarioPattern
        sessionRecommendedMinutes = recommendedMinutes
        liveViolations.removeAll()
    }

    /// 结束训练 · 评分 · push 到 log · 留 sheet 数据供 UI 弹
    func endSession(finalBalance: Decimal, trades: [TradeRecord]) {
        guard let startedAt = sessionStartedAt else { return }
        let session = TrainingSession(
            startedAt: startedAt,
            endedAt: Date(),
            initialBalance: sessionInitialBalance,
            finalBalance: finalBalance,
            trades: trades,
            violations: liveViolations,
            scenarioName: sessionScenarioName,
            scenarioPattern: sessionScenarioPattern
        )
        let score = TrainingScorer.score(session)
        log.addSession(session)
        lastFinishedSession = session
        lastFinishedScore = score
        sessionStartedAt = nil
        sessionInitialBalance = 0
        sessionScenarioName = ""
        sessionScenarioPattern = nil
        sessionRecommendedMinutes = nil
        sessionPausedAt = nil
        sessionAccumulatedPause = 0
        liveViolations.removeAll()
    }

    func dismissLastFinishedSheet() {
        // v16.58 · 关闭 sheet 前抓取 session id · 让 HistoryPanel 接力高亮 + scroll
        recentlyAddedSessionID = lastFinishedSession?.id
        lastFinishedSession = nil
        lastFinishedScore = nil
    }

    // MARK: - Live violation 推流（batch10 接 engine.observe）

    func pushLiveViolation(_ v: DisciplineViolation) {
        liveViolations.insert(v, at: 0)
    }
}

#endif
