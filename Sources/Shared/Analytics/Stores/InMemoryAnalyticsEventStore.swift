// WP-133a · 内存版埋点 Store
// 用途：测试 + 单元集成 + Stage A 早期 production fallback
// id 从 1 起自增（与 SQLite AUTOINCREMENT 行为一致）

import Foundation

public actor InMemoryAnalyticsEventStore: AnalyticsEventStore {
    private var events: [AnalyticsEvent] = []
    private var nextID: Int64 = 1

    public init() {}

    public func append(_ event: AnalyticsEvent) async throws -> Int64 {
        let id = nextID
        nextID += 1
        events.append(event.withID(id))
        return id
    }

    public func appendBatch(_ events: [AnalyticsEvent]) async throws -> [Int64] {
        var ids: [Int64] = []
        ids.reserveCapacity(events.count)
        for event in events {
            ids.append(try await append(event))
        }
        return ids
    }

    public func queryPending(limit: Int) async throws -> [AnalyticsEvent] {
        let pending = events
            .filter { !$0.uploaded }
            .sorted { $0.eventTimestampMs < $1.eventTimestampMs }
        return limit > 0 ? Array(pending.prefix(limit)) : pending
    }

    public func markUploaded(ids: [Int64]) async throws {
        let idSet = Set(ids)
        events = events.map { event in
            idSet.contains(event.id) ? event.markedUploaded() : event
        }
    }

    @discardableResult
    public func cleanupUploaded(beforeTimestampMs: Int64) async throws -> Int {
        let before = events.count
        events.removeAll { $0.uploaded && $0.eventTimestampMs < beforeTimestampMs }
        return before - events.count
    }

    public func count() async throws -> Int { events.count }
}
