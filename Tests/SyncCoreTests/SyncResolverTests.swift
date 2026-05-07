// SyncResolver LWW 算法测试 · WP-60 batch001
// 覆盖：lastModified 决胜 / version 决胜 / tombstone 优先 / identical / conflict 判定

import Testing
import Foundation
@testable import SyncCore

@Suite("SyncResolver · LWW 决胜")
struct SyncResolverTests {

    private let id = UUID()
    private let recordType = "test"
    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(version: Int = 1,
                        modifiedOffset: TimeInterval = 0,
                        deletedOffset: TimeInterval? = nil,
                        payload: String = "p") -> SyncRecord {
        SyncRecord(
            recordType: recordType,
            id: id,
            lastModified: baseTime.addingTimeInterval(modifiedOffset),
            version: version,
            deletedAt: deletedOffset.map { baseTime.addingTimeInterval($0) },
            payload: Data(payload.utf8)
        )
    }

    // MARK: - lastModified 主决胜

    @Test("local 时间晚 → local 胜")
    func localNewer() {
        let local = record(version: 2, modifiedOffset: 10, payload: "L")
        let remote = record(version: 5, modifiedOffset: 5, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.winner == local)
        #expect(outcome.resolution == .local)
    }

    @Test("remote 时间晚 → remote 胜")
    func remoteNewer() {
        let local = record(version: 5, modifiedOffset: 5, payload: "L")
        let remote = record(version: 2, modifiedOffset: 10, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.winner == remote)
        #expect(outcome.resolution == .remote)
    }

    // MARK: - version 副决胜

    @Test("同时间戳 · version 大者胜")
    func sameTimeVersionWins() {
        let local = record(version: 5, modifiedOffset: 0, payload: "L")
        let remote = record(version: 3, modifiedOffset: 0, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.winner == local)
        #expect(outcome.resolution == .local)
    }

    // MARK: - identical

    @Test("完全相等 → identical · 无冲突")
    func identical() {
        let r = record(version: 3, modifiedOffset: 5, payload: "same")
        let outcome = SyncResolver.merge(local: r, remote: r)
        #expect(outcome.resolution == .identical)
        #expect(outcome.conflict == nil)
        #expect(outcome.winner == r)
    }

    // MARK: - tombstone 行为

    @Test("local 是 tombstone · 时间晚 · local 胜")
    func tombstoneLocalWins() {
        let local = record(version: 3, modifiedOffset: 10, deletedOffset: 10, payload: "L")
        let remote = record(version: 2, modifiedOffset: 5, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.winner.isDeleted)
        #expect(outcome.resolution == .local)
    }

    @Test("remote 修改晚于 local 删除 · 复活")
    func remoteRevivesLocalTombstone() {
        let local = record(version: 3, modifiedOffset: 5, deletedOffset: 5, payload: "L")
        let remote = record(version: 4, modifiedOffset: 10, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(!outcome.winner.isDeleted)
        #expect(outcome.resolution == .remote)
    }

    @Test("双方都是 tombstone · 不算 conflict")
    func bothTombstonesNoConflict() {
        let local = record(version: 2, modifiedOffset: 10, deletedOffset: 10)
        let remote = record(version: 1, modifiedOffset: 5, deletedOffset: 5)
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.conflict == nil)
    }

    // MARK: - conflict 判定

    @Test("双方都被改过 · payload 不同 → 记录冲突")
    func realConflict() {
        let local = record(version: 3, modifiedOffset: 10, payload: "Lpay")
        let remote = record(version: 4, modifiedOffset: 5, payload: "Rpay")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.conflict != nil)
        #expect(outcome.conflict?.localVersion == 3)
        #expect(outcome.conflict?.remoteVersion == 4)
        #expect(outcome.conflict?.resolution == .local)  // local 时间晚胜
    }

    @Test("一方 version=0（新建未改过）· 不算冲突")
    func unilateralChangeNotConflict() {
        let local = record(version: 0, modifiedOffset: 10, payload: "L")
        let remote = record(version: 3, modifiedOffset: 5, payload: "R")
        let outcome = SyncResolver.merge(local: local, remote: remote)
        #expect(outcome.conflict == nil)
        #expect(outcome.resolution == .local)
    }
}
