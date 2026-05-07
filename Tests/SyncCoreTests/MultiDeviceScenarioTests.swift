// 多设备并发场景测试 · WP-60 batch002
//
// 覆盖：
//   1. 设备 A → B ping-pong 双向修改
//   2. A 删 vs B 改竞争
//   3. 三设备并发新增 → 全收敛
//   4. 离线累积修改后重连 sync
//   5. version 跳变（同 lastModified）
//   6. 同一 recordType 多设备 baseline 隔离
//   7. ConflictLog + Engine 集成
//
// 测试时间约定：
//   - 所有 record.lastModified ∈ [baseTime + 1, baseTime + 100]
//   - 每个 engine 注入 now = { baseTime } · baseline 落在 baseTime
//   - 这样 fetch since = baseTime · 仅返回 lastModified > baseTime 的记录
//
// 模型：共享同一个 MockSyncBackend · 多个 SyncEngine 代表不同设备

import Testing
import Foundation
@testable import SyncCore

@Suite("多设备并发场景 · 共享 MockSyncBackend")
struct MultiDeviceScenarioTests {

    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    private let recordType = "watchlist"

    private func makeEngine(_ backend: MockSyncBackend) -> SyncEngine {
        SyncEngine(backend: backend, now: { [baseTime] in baseTime })
    }

    private func record(id: UUID,
                        modifiedOffset: TimeInterval,
                        version: Int,
                        deletedOffset: TimeInterval? = nil,
                        payload: String) -> SyncRecord {
        SyncRecord(
            recordType: recordType,
            id: id,
            lastModified: baseTime.addingTimeInterval(modifiedOffset),
            version: version,
            deletedAt: deletedOffset.map { baseTime.addingTimeInterval($0) },
            payload: Data(payload.utf8)
        )
    }

    // MARK: - 场景 1：A↔B ping-pong（单边修改 · 不算冲突）

    @Test("A 改 push → B 拉 → B 改 push → A 拉 · 双方收敛 · 单边修改无冲突")
    func pingPong() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let engineB = makeEngine(backend)

        let id = UUID()

        // 1. A 新增 v1 并 push
        var localA: [SyncRecord] = [record(id: id, modifiedOffset: 5, version: 1, payload: "A1")]
        let r1 = try await engineA.sync(localRecords: localA, recordType: recordType)
        #expect(r1.pushedCount == 1)
        localA = r1.merged

        // 2. B 同步拉到
        let r2 = try await engineB.sync(localRecords: [], recordType: recordType)
        #expect(r2.pulledCount == 1)
        var localB = r2.merged

        // 3. B 改 → v2
        guard let bRecord = localB.first(where: { $0.id == id }) else {
            Issue.record("B 端应有该记录"); return
        }
        let bModified = SyncRecord(
            recordType: bRecord.recordType,
            id: bRecord.id,
            lastModified: baseTime.addingTimeInterval(15),
            version: bRecord.version + 1,
            payload: Data("B2".utf8)
        )
        localB = [bModified]
        let r3 = try await engineB.sync(localRecords: localB, recordType: recordType)
        #expect(r3.pushedCount == 1)
        #expect(r3.conflicts.isEmpty)  // B 单边改 · 不冲突

        // 4. A 同步拉 B 的修改
        let r4 = try await engineA.sync(localRecords: localA, recordType: recordType)
        #expect(r4.pulledCount == 1)
        let aFinal = r4.merged.first { $0.id == id }
        #expect(aFinal?.payload == Data("B2".utf8))
        #expect(aFinal?.version == 2)
        #expect(r4.conflicts.isEmpty)  // A 端 local v1 · remote v2 → 单边修改 · 不冲突

        // 双方收敛
        let stored = await backend.snapshot(recordType: recordType)
        #expect(stored.first?.payload == Data("B2".utf8))
    }

    // MARK: - 场景 2：A 删除 vs B 修改（双方都改 v>1 · 算冲突）

    @Test("A 删除时间晚于 B 修改 → 删除胜 · 算冲突")
    func deleteWinsOverEarlierEdit() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let engineB = makeEngine(backend)

        let id = UUID()
        // 初始 v1 已落 backend
        let initial = record(id: id, modifiedOffset: 5, version: 1, payload: "init")
        try await backend.push([initial])
        _ = try await engineA.sync(localRecords: [initial], recordType: recordType)
        _ = try await engineB.sync(localRecords: [initial], recordType: recordType)

        // A 删除 v2 offset=20
        let aDeleted = record(id: id, modifiedOffset: 20, version: 2, deletedOffset: 20, payload: "init")
        let rA = try await engineA.sync(localRecords: [aDeleted], recordType: recordType)
        #expect(rA.pushedCount == 1)

        // B 修改 v2 offset=10（早于删除）
        let bModified = record(id: id, modifiedOffset: 10, version: 2, payload: "B-edit")
        let rB = try await engineB.sync(localRecords: [bModified], recordType: recordType)

        // B 端应收到 A 删除（lastModified 20 > 10）
        let bFinal = rB.merged.first { $0.id == id }
        #expect(bFinal?.isDeleted == true)
        // 双方都 v>1 · 一方 deleted 一方非 → 算冲突
        #expect(rB.conflicts.count == 1)
        #expect(rB.conflicts.first?.resolution == .remote)
    }

    @Test("A 删除时间早于 B 修改 → B 修改胜（复活）· 双方 v>1 算冲突")
    func laterEditRevivesEarlierDelete() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let engineB = makeEngine(backend)

        let id = UUID()
        let initial = record(id: id, modifiedOffset: 5, version: 1, payload: "init")
        try await backend.push([initial])
        _ = try await engineA.sync(localRecords: [initial], recordType: recordType)
        _ = try await engineB.sync(localRecords: [initial], recordType: recordType)

        // A 删除 v2 offset=10
        let aDeleted = record(id: id, modifiedOffset: 10, version: 2, deletedOffset: 10, payload: "init")
        _ = try await engineA.sync(localRecords: [aDeleted], recordType: recordType)

        // B 改 v2 offset=20 · 晚于删除
        let bRevived = record(id: id, modifiedOffset: 20, version: 2, payload: "B-revive")
        let rB = try await engineB.sync(localRecords: [bRevived], recordType: recordType)

        let bFinal = rB.merged.first { $0.id == id }
        #expect(bFinal?.isDeleted == false)
        #expect(bFinal?.payload == Data("B-revive".utf8))
        #expect(rB.conflicts.count == 1)  // 双方 v>1 一删一改 · 算冲突
    }

    // MARK: - 场景 3：三设备并发新增（不同 id · 全部 v=1 · 不冲突）

    @Test("三设备各自新增 → 全收敛 · 不丢")
    func threeDevicesAddIndependently() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let engineB = makeEngine(backend)
        let engineC = makeEngine(backend)

        let aLocal = [record(id: UUID(), modifiedOffset: 5, version: 1, payload: "A")]
        let bLocal = [record(id: UUID(), modifiedOffset: 6, version: 1, payload: "B")]
        let cLocal = [record(id: UUID(), modifiedOffset: 7, version: 1, payload: "C")]

        _ = try await engineA.sync(localRecords: aLocal, recordType: recordType)
        _ = try await engineB.sync(localRecords: bLocal, recordType: recordType)
        _ = try await engineC.sync(localRecords: cLocal, recordType: recordType)

        // 各自再 sync 一轮 → 都看到 3 条
        let rA = try await engineA.sync(localRecords: aLocal, recordType: recordType)
        let rB = try await engineB.sync(localRecords: bLocal, recordType: recordType)
        let rC = try await engineC.sync(localRecords: cLocal, recordType: recordType)

        #expect(rA.merged.count == 3)
        #expect(rB.merged.count == 3)
        #expect(rC.merged.count == 3)
        #expect(rA.conflicts.isEmpty)
        #expect(rB.conflicts.isEmpty)
        #expect(rC.conflicts.isEmpty)
    }

    // MARK: - 场景 4：离线累积 + 重连

    @Test("离线累积 5 个新增 · 重连 sync · 全部 push")
    func offlineThenReconnect() async throws {
        let backend = MockSyncBackend()
        let engine = makeEngine(backend)

        let localRecords = (0..<5).map { i in
            record(id: UUID(), modifiedOffset: TimeInterval(i + 1), version: 1, payload: "off-\(i)")
        }

        let result = try await engine.sync(localRecords: localRecords, recordType: recordType)
        #expect(result.pushedCount == 5)
        #expect(result.merged.count == 5)

        let stored = await backend.snapshot(recordType: recordType)
        #expect(stored.count == 5)
    }

    @Test("离线时 backend 也有别人的更新 · 重连合并不丢")
    func offlineRemoteAlsoChanges() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let engineB = makeEngine(backend)

        // A 基线（先空 sync 设 baseline）
        _ = try await engineA.sync(localRecords: [], recordType: recordType)

        // B push 2 条（A 离线）
        let bRecords = [
            record(id: UUID(), modifiedOffset: 5, version: 1, payload: "B1"),
            record(id: UUID(), modifiedOffset: 6, version: 1, payload: "B2")
        ]
        _ = try await engineB.sync(localRecords: bRecords, recordType: recordType)

        // A 重连 + 本地新增 1 条 → 总 3
        let aLocal = [record(id: UUID(), modifiedOffset: 7, version: 1, payload: "A1")]
        let result = try await engineA.sync(localRecords: aLocal, recordType: recordType)
        #expect(result.merged.count == 3)
        #expect(result.pulledCount == 2)
        #expect(result.pushedCount == 1)
    }

    // MARK: - 场景 5：同 lastModified version 决胜

    @Test("两端同时间戳 · version 大者胜")
    func sameTimestampVersionTiebreaker() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)

        let id = UUID()
        let remote = record(id: id, modifiedOffset: 5, version: 2, payload: "R")
        try await backend.push([remote])

        let local = record(id: id, modifiedOffset: 5, version: 5, payload: "L")
        let result = try await engineA.sync(localRecords: [local], recordType: recordType)

        #expect(result.merged.first?.payload == Data("L".utf8))
        #expect(result.pushedCount == 1)
        // 双方 v>1 · payload 不同 → 算冲突
        #expect(result.conflicts.count == 1)
    }

    // MARK: - 场景 6：baseline 按 recordType 隔离

    @Test("两个 recordType 的 baseline 互不影响")
    func baselineIsolated() async throws {
        let backend = MockSyncBackend()
        let engine = makeEngine(backend)

        let r1 = SyncRecord(
            recordType: "watchlist",
            id: UUID(),
            lastModified: baseTime.addingTimeInterval(5),
            version: 1,
            payload: Data("w".utf8)
        )
        let r2 = SyncRecord(
            recordType: "workspace",
            id: UUID(),
            lastModified: baseTime.addingTimeInterval(5),
            version: 1,
            payload: Data("ws".utf8)
        )
        try await backend.push([r1, r2])

        _ = try await engine.sync(localRecords: [], recordType: "watchlist")
        let watchlistBaseline = await engine.lastSync(for: "watchlist")
        let workspaceBaseline = await engine.lastSync(for: "workspace")
        #expect(watchlistBaseline != nil)
        #expect(workspaceBaseline == nil)

        _ = try await engine.sync(localRecords: [], recordType: "workspace")
        let workspaceBaselineAfter = await engine.lastSync(for: "workspace")
        #expect(workspaceBaselineAfter != nil)
    }

    // MARK: - 场景 7：ConflictLog 集成

    @Test("Engine 多轮 sync · ConflictLog 累计冲突 · 双方 v>1 才记")
    func conflictLogIntegration() async throws {
        let backend = MockSyncBackend()
        let engineA = makeEngine(backend)
        let log = InMemoryConflictLog()

        // 两轮独立冲突 · 双方 version 都 > 1
        let id1 = UUID()
        let r1Remote = record(id: id1, modifiedOffset: 5, version: 2, payload: "R1")
        try await backend.push([r1Remote])
        let r1Local = record(id: id1, modifiedOffset: 10, version: 3, payload: "L1")
        let res1 = try await engineA.sync(localRecords: [r1Local], recordType: recordType)
        await log.recordAll(res1.conflicts)

        let id2 = UUID()
        let r2Remote = record(id: id2, modifiedOffset: 15, version: 2, payload: "R2")
        try await backend.push([r2Remote])
        let r2Local = record(id: id2, modifiedOffset: 20, version: 3, payload: "L2")
        let res2 = try await engineA.sync(localRecords: [r2Local], recordType: recordType)
        await log.recordAll(res2.conflicts)

        let count = await log.count()
        #expect(count == 2)

        let watchlistConflicts = await log.filter(recordType: recordType)
        #expect(watchlistConflicts.count == 2)
    }
}
