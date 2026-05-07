// CloudKitSyncBackend · macOS-only CloudKit backend 实现（WP-60 · v15.24 batch008）
//
// 全文 #if canImport(CloudKit) 隔离 · Linux 不编译
// 容器 ID 由调用方注入（CKContainer(identifier:)）· 实际 entitlement 配置见 Sources/SyncCore/CloudKit/README.md
//
// 范围（Stage A）：
//   ✅ fetch / push / delete 三方法实现
//   ✅ 错误映射（CloudKit error → SyncBackendError）
//   ✅ 字段编解码（SyncRecord ↔ CKRecord）
//   ⏳ Mac 切机时联调（容器创建 / Schema deploy / 真实账号同步）
//
// 不在范围：
//   ❌ Subscription（推送变更通知）· 留 WP-61 / 后续 polish
//   ❌ Asset 大文件（payload 用普通字段 · KB 级足够）
//   ❌ Encrypted CKRecord（CloudKit 默认 in-transit 加密 · at-rest 由 Apple 管）
//
// CKRecord 字段约定（与 SyncRecord 对应）：
//   recordType  = SyncRecord.recordType（"watchlist" 等）
//   recordName  = SyncRecord.id.uuidString
//   "lastModified" : Date（业务侧时间戳 · 不与 CK 内置 modificationDate 混用）
//   "version"      : Int64
//   "deletedAt"    : Date?（tombstone）
//   "payload"      : Data（业务侧 JSON 字节）

#if canImport(CloudKit)

import Foundation
import CloudKit

/// CloudKit-backed SyncBackend
///
/// 用法（Mac 端）：
/// ```swift
/// let container = CKContainer(identifier: "iCloud.com.yourcompany.FuturesTerminal")
/// let backend = CloudKitSyncBackend(container: container, scope: .private)
/// let engine = SyncEngine(backend: backend)
/// ```
public actor CloudKitSyncBackend: SyncBackend {

    public enum DatabaseScope: Sendable {
        case `private`
        case `public`
        case shared
    }

    public enum CKField {
        public static let lastModified = "lastModified"
        public static let version = "version"
        public static let deletedAt = "deletedAt"
        public static let payload = "payload"
    }

    private let container: CKContainer
    private let scope: DatabaseScope

    public init(container: CKContainer, scope: DatabaseScope = .private) {
        self.container = container
        self.scope = scope
    }

    // MARK: - SyncBackend

    public func fetch(recordType: String, since: Date?) async throws -> [SyncRecord] {
        let predicate: NSPredicate
        if let since {
            predicate = NSPredicate(format: "%K > %@", CKField.lastModified, since as NSDate)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CKField.lastModified, ascending: true)]

        let database = self.database
        do {
            let (matchResults, _) = try await database.records(matching: query)
            var out: [SyncRecord] = []
            out.reserveCapacity(matchResults.count)
            for (_, result) in matchResults {
                switch result {
                case .success(let ckRecord):
                    if let record = Self.decode(ckRecord) {
                        out.append(record)
                    }
                case .failure(let error):
                    throw Self.mapError(error)
                }
            }
            return out
        } catch let error as SyncBackendError {
            throw error
        } catch {
            throw Self.mapError(error)
        }
    }

    public func push(_ records: [SyncRecord]) async throws {
        guard !records.isEmpty else { return }
        let ckRecords = records.map { Self.encode($0) }
        let database = self.database
        do {
            let (_, _) = try await database.modifyRecords(saving: ckRecords, deleting: [])
        } catch {
            throw Self.mapError(error)
        }
    }

    public func delete(recordType: String, ids: [UUID], deletedAt: Date) async throws {
        guard !ids.isEmpty else { return }
        // tombstone via push（保留 deletedAt 字段）· 而非 CK 物理删除
        // 让对端拉到 tombstone 后本地软删 · 物理 GC 由后续 batch 实现
        let database = self.database
        var existing: [CKRecord] = []
        for id in ids {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            do {
                let r = try await database.record(for: recordID)
                r[CKField.deletedAt] = deletedAt as CKRecordValue
                r[CKField.lastModified] = deletedAt as CKRecordValue
                if let v = r[CKField.version] as? Int {
                    r[CKField.version] = (v + 1) as CKRecordValue
                } else {
                    r[CKField.version] = 1 as CKRecordValue
                }
                existing.append(r)
            } catch {
                if case CKError.unknownItem = error {
                    let r = CKRecord(recordType: recordType, recordID: recordID)
                    r[CKField.deletedAt] = deletedAt as CKRecordValue
                    r[CKField.lastModified] = deletedAt as CKRecordValue
                    r[CKField.version] = 1 as CKRecordValue
                    r[CKField.payload] = Data() as CKRecordValue
                    existing.append(r)
                } else {
                    throw Self.mapError(error)
                }
            }
        }
        do {
            let (_, _) = try await database.modifyRecords(saving: existing, deleting: [])
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - 私有

    private var database: CKDatabase {
        switch scope {
        case .private: return container.privateCloudDatabase
        case .public: return container.publicCloudDatabase
        case .shared: return container.sharedCloudDatabase
        }
    }

    private static func encode(_ record: SyncRecord) -> CKRecord {
        let recordID = CKRecord.ID(recordName: record.id.uuidString)
        let ck = CKRecord(recordType: record.recordType, recordID: recordID)
        ck[CKField.lastModified] = record.lastModified as CKRecordValue
        ck[CKField.version] = record.version as CKRecordValue
        ck[CKField.payload] = record.payload as CKRecordValue
        if let deletedAt = record.deletedAt {
            ck[CKField.deletedAt] = deletedAt as CKRecordValue
        }
        return ck
    }

    private static func decode(_ ck: CKRecord) -> SyncRecord? {
        guard let id = UUID(uuidString: ck.recordID.recordName),
              let lastModified = ck[CKField.lastModified] as? Date,
              let version = ck[CKField.version] as? Int,
              let payload = ck[CKField.payload] as? Data
        else { return nil }
        let deletedAt = ck[CKField.deletedAt] as? Date
        return SyncRecord(
            recordType: ck.recordType,
            id: id,
            lastModified: lastModified,
            version: version,
            deletedAt: deletedAt,
            payload: payload
        )
    }

    private static func mapError(_ error: Error) -> SyncBackendError {
        guard let ckError = error as? CKError else {
            return .unknown(String(describing: error))
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated, .permissionFailure:
            return .authenticationRequired
        case .quotaExceeded:
            return .quotaExceeded
        case .requestRateLimited, .limitExceeded:
            return .rateLimited
        case .unknownItem:
            return .recordNotFound(UUID())  // CK 不携带 record id 在错误里 · 用 0 占位
        case .invalidArguments, .incompatibleVersion, .badContainer, .badDatabase:
            return .schemaMismatch(ckError.localizedDescription)
        default:
            return .unknown(ckError.localizedDescription)
        }
    }
}

#endif
