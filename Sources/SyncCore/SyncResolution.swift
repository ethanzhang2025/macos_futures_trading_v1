// SyncResolution · LWW 合并算法（WP-60）
//
// 决胜规则（自上而下）：
//   1. tombstone 优先：任意一方 deletedAt 非 nil 且 lastModified ≥ 对方 → 删除胜
//      （即对端"修改"晚于"删除"才能复活；防止一方"删了"的记录又被对方旧编辑覆盖）
//   2. lastModified 大者胜
//   3. 同 lastModified · version 大者胜
//   4. 完全相等 · 取本地（确定性 · 不抖动）
//
// 冲突判定（写入 SyncConflictLog）：
//   - 双方都非 tombstone + payload 不同 + 双方 version 都 > 1（都被实质修改过 · 而非仅初始 v=1）→ 记录冲突
//   - 否则视为自然演进（单边修改不报冲突）
//   约定：新建 record version=1 · 每次 mutating 字段时 version += 1
//   所以 version > 1 即"被实质改过至少一次"
//
// 这套规则覆盖：
//   - A 改后 B 改：lastModified 决胜 · 后改方赢 · 记录冲突
//   - A 删 B 改：删除时间晚 → 删 · 改时间晚 → 复活
//   - 单边修改：直接采用 · 不算冲突

import Foundation

public enum SyncResolution: String, Sendable, Codable {
    case local
    case remote
    /// 完全相等 · 不需任何动作
    case identical
}

public struct SyncMergeOutcome: Sendable {
    public let winner: SyncRecord
    public let resolution: SyncResolution
    public let conflict: SyncConflict?

    public init(winner: SyncRecord, resolution: SyncResolution, conflict: SyncConflict?) {
        self.winner = winner
        self.resolution = resolution
        self.conflict = conflict
    }
}

public enum SyncResolver {

    /// LWW 合并 · 见文件头规则
    public static func merge(local: SyncRecord, remote: SyncRecord) -> SyncMergeOutcome {
        precondition(local.id == remote.id, "merge 仅适用于同一 id 的两条记录")
        precondition(local.recordType == remote.recordType, "merge 仅适用于同 recordType")

        // 完全相等
        if local == remote {
            return SyncMergeOutcome(winner: local, resolution: .identical, conflict: nil)
        }

        let winner = pickWinner(local: local, remote: remote)
        let resolution: SyncResolution = (winner == local) ? .local : .remote

        let conflict: SyncConflict? = isContentConflict(local: local, remote: remote)
            ? SyncConflict(
                recordType: local.recordType,
                recordID: local.id,
                localVersion: local.version,
                remoteVersion: remote.version,
                localModified: local.lastModified,
                remoteModified: remote.lastModified,
                resolution: resolution,
                resolvedAt: Date()
            )
            : nil

        return SyncMergeOutcome(winner: winner, resolution: resolution, conflict: conflict)
    }

    private static func pickWinner(local: SyncRecord, remote: SyncRecord) -> SyncRecord {
        if local.lastModified > remote.lastModified { return local }
        if local.lastModified < remote.lastModified { return remote }
        if local.version > remote.version { return local }
        if local.version < remote.version { return remote }
        return local
    }

    /// 仅当双方都"被实质修改过"（version > 1 · 即至少一次 mutate）且内容不同 · 才算冲突
    /// 单边修改（一方 version=1 仍是初始）不报冲突 · 视为正常增量同步
    private static func isContentConflict(local: SyncRecord, remote: SyncRecord) -> Bool {
        guard local != remote else { return false }
        guard local.version > 1, remote.version > 1 else { return false }
        if local.isDeleted && remote.isDeleted { return false }
        return true
    }
}
