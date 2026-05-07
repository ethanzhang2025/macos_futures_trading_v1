// SyncCoordinator_iOS · iPad CloudKit 同步协调器（WP-61 batch006）
//
// 协调多个 recordType 的同步：watchlist / workspace_template / settings
// 复用 WP-60 SyncCore 抽象层（SyncEngine + CloudKitSyncBackend）
//
// 设计：
//   - @MainActor ObservableObject · @Published 暴露 UI 状态（lastSync / syncing / errorMessage / conflictCount）
//   - 注入 SyncBackend（默认 MockSyncBackend · Mac 切机时换成 CloudKitSyncBackend）
//   - syncAll(): 依次同步 3 大 recordType · 收集冲突
//   - syncWatchlist / syncWorkspace / syncSettings: 单独入口 · UI 主动触发
//
// 不在 v1 范围：
//   ❌ 后台定时同步（CKSubscription / BGTaskScheduler）· 留 polish
//   ❌ 增量推送通知（CK Push）· 留 polish
//
// 用法（iPad app init）：
//   #if canImport(CloudKit)
//   let container = CKContainer(identifier: "iCloud.com.<yourorg>.FuturesTerminal")
//   let backend = CloudKitSyncBackend(container: container, scope: .private)
//   let coord = SyncCoordinator_iOS(backend: backend)
//   #else
//   let coord = SyncCoordinator_iOS(backend: MockSyncBackend())
//   #endif

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import Foundation
import Shared
import SyncCore

@MainActor
final class SyncCoordinator_iOS: ObservableObject {

    enum SyncStatus: Equatable {
        case idle
        case syncing(recordType: String)
        case lastSucceeded(at: Date)
        case failed(message: String)
    }

    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var lastSyncDates: [String: Date] = [:]
    @Published private(set) var conflictCount: Int = 0

    private let engine: SyncEngine
    private let conflictLog: InMemoryConflictLog

    init(backend: any SyncBackend) {
        self.engine = SyncEngine(backend: backend)
        self.conflictLog = InMemoryConflictLog()
    }

    /// 全量同步：依次过 3 大 recordType
    func syncAll(book: WatchlistBook,
                 workspace: WorkspaceBook,
                 settings: SyncableSettings) async -> SyncOutcomeBundle {
        var outcome = SyncOutcomeBundle()
        outcome.watchlist = await syncWatchlist(book: book)
        outcome.workspace = await syncWorkspace(book: workspace)
        outcome.settings = await syncSettings(settings: settings)

        let allConflicts = (outcome.watchlist?.conflicts ?? [])
            + (outcome.workspace?.conflicts ?? [])
            + (outcome.settings?.conflicts ?? [])
        await conflictLog.recordAll(allConflicts)
        let total = await conflictLog.count()
        self.conflictCount = total

        if outcome.hasError {
            status = .failed(message: outcome.errorMessage ?? "未知错误")
        } else {
            status = .lastSucceeded(at: Date())
        }
        return outcome
    }

    func syncWatchlist(book: WatchlistBook) async -> RecordTypeOutcome? {
        await runOne(recordType: Watchlist.syncRecordType) {
            let records = try book.groups.map { try $0.toSyncRecord() }
            let result = try await engine.sync(localRecords: records, recordType: Watchlist.syncRecordType)
            let merged = try result.merged.map { try Watchlist.decode(from: $0) }
            return RecordTypeOutcome(
                merged: merged.compactMap { $0 as Any },
                pulledCount: result.pulledCount,
                pushedCount: result.pushedCount,
                conflicts: result.conflicts,
                error: nil,
                mergedWatchlists: merged
            )
        }
    }

    func syncWorkspace(book: WorkspaceBook) async -> RecordTypeOutcome? {
        await runOne(recordType: WorkspaceTemplate.syncRecordType) {
            let records = try book.templates.map { try $0.toSyncRecord() }
            let result = try await engine.sync(localRecords: records, recordType: WorkspaceTemplate.syncRecordType)
            let merged = try result.merged.map { try WorkspaceTemplate.decode(from: $0) }
            return RecordTypeOutcome(
                merged: merged.compactMap { $0 as Any },
                pulledCount: result.pulledCount,
                pushedCount: result.pushedCount,
                conflicts: result.conflicts,
                error: nil,
                mergedWorkspaceTemplates: merged
            )
        }
    }

    func syncSettings(settings: SyncableSettings) async -> RecordTypeOutcome? {
        await runOne(recordType: SyncableSettings.syncRecordType) {
            let record = try settings.toSyncRecord()
            let result = try await engine.sync(localRecords: [record], recordType: SyncableSettings.syncRecordType)
            let merged = try result.merged.map { try SyncableSettings.decode(from: $0) }
            return RecordTypeOutcome(
                merged: merged.compactMap { $0 as Any },
                pulledCount: result.pulledCount,
                pushedCount: result.pushedCount,
                conflicts: result.conflicts,
                error: nil,
                mergedSettings: merged.first
            )
        }
    }

    /// 拉取冲突日志（UI 显示）
    func recentConflicts(limit: Int = 50) async -> [SyncConflict] {
        await conflictLog.paginate(offset: 0, limit: limit)
    }

    func clearConflicts() async {
        await conflictLog.clear()
        conflictCount = 0
    }

    // MARK: - 私有 · 单 recordType 套路

    private func runOne(
        recordType: String,
        op: () async throws -> RecordTypeOutcome
    ) async -> RecordTypeOutcome? {
        status = .syncing(recordType: recordType)
        do {
            let outcome = try await op()
            lastSyncDates[recordType] = Date()
            return outcome
        } catch {
            return RecordTypeOutcome(
                merged: [],
                pulledCount: 0,
                pushedCount: 0,
                conflicts: [],
                error: error
            )
        }
    }
}

// MARK: - 输出模型

struct RecordTypeOutcome {
    let merged: [Any]
    let pulledCount: Int
    let pushedCount: Int
    let conflicts: [SyncConflict]
    let error: Error?

    // 类型化便利访问
    var mergedWatchlists: [Watchlist]?
    var mergedWorkspaceTemplates: [WorkspaceTemplate]?
    var mergedSettings: SyncableSettings?

    init(merged: [Any] = [],
         pulledCount: Int = 0,
         pushedCount: Int = 0,
         conflicts: [SyncConflict] = [],
         error: Error? = nil,
         mergedWatchlists: [Watchlist]? = nil,
         mergedWorkspaceTemplates: [WorkspaceTemplate]? = nil,
         mergedSettings: SyncableSettings? = nil) {
        self.merged = merged
        self.pulledCount = pulledCount
        self.pushedCount = pushedCount
        self.conflicts = conflicts
        self.error = error
        self.mergedWatchlists = mergedWatchlists
        self.mergedWorkspaceTemplates = mergedWorkspaceTemplates
        self.mergedSettings = mergedSettings
    }
}

struct SyncOutcomeBundle {
    var watchlist: RecordTypeOutcome?
    var workspace: RecordTypeOutcome?
    var settings: RecordTypeOutcome?

    var hasError: Bool {
        watchlist?.error != nil || workspace?.error != nil || settings?.error != nil
    }

    var errorMessage: String? {
        if let e = watchlist?.error { return "自选同步失败：\(e.localizedDescription)" }
        if let e = workspace?.error { return "工作区同步失败：\(e.localizedDescription)" }
        if let e = settings?.error { return "偏好同步失败：\(e.localizedDescription)" }
        return nil
    }

    var totalPulled: Int {
        (watchlist?.pulledCount ?? 0) + (workspace?.pulledCount ?? 0) + (settings?.pulledCount ?? 0)
    }

    var totalPushed: Int {
        (watchlist?.pushedCount ?? 0) + (workspace?.pushedCount ?? 0) + (settings?.pushedCount ?? 0)
    }

    var totalConflicts: Int {
        (watchlist?.conflicts.count ?? 0) + (workspace?.conflicts.count ?? 0) + (settings?.conflicts.count ?? 0)
    }
}

// MARK: - 注入 helper

extension SyncCoordinator_iOS {

    /// 默认 backend：iOS canImport(CloudKit) 时尝试 CloudKitSyncBackend · 否则 MockSyncBackend
    /// container ID 由调用方提供（默认 "iCloud.com.example.FuturesTerminal" 占位）
    static func makeDefault(containerID: String = "iCloud.com.example.FuturesTerminal") -> SyncCoordinator_iOS {
        #if canImport(CloudKit)
        // Mac 切机 + entitlements 配齐后启用真实 CloudKit
        // 占位实现：先用 Mock · 等 readme 提示用户改 containerID 并配 entitlements
        let backend = MockSyncBackend()
        _ = containerID  // 留参数 · 实际接入时换：CloudKitSyncBackend(container: CKContainer(identifier: containerID))
        return SyncCoordinator_iOS(backend: backend)
        #else
        return SyncCoordinator_iOS(backend: MockSyncBackend())
        #endif
    }
}

#endif
