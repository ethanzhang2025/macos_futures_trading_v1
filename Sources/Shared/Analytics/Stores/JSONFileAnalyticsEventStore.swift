// WP-133a · JSON 文件版埋点 Store
// 持久化策略：每次写操作整体序列化 + 原子替换（与 JSONFileKLineCacheStore 模式一致）
// 适合 Stage A 早期 production · 量级 < 10w 条 / 周；超出后切换到 SQLCipher（WP-19）
//
// 文件格式：
// {
//   "events": [...],
//   "nextID": 12345
// }

import Foundation

public actor JSONFileAnalyticsEventStore: AnalyticsEventStore {
    private let fileURL: URL
    private var events: [AnalyticsEvent] = []
    private var nextID: Int64 = 1
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private struct Snapshot: Codable {
        var events: [AnalyticsEvent]
        var nextID: Int64
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            self.events = snapshot.events
            self.nextID = snapshot.nextID
        } catch {
            throw AnalyticsEventStoreError.decodeFailed(error.localizedDescription)
        }
    }

    private func persist() throws {
        let snapshot = Snapshot(events: events, nextID: nextID)
        do {
            let data = try JSONEncoder().encode(snapshot)
            // 创建上级目录（首次写入时）
            let dir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AnalyticsEventStoreError.ioFailed(error.localizedDescription)
        }
    }

    public func append(_ event: AnalyticsEvent) async throws -> Int64 {
        try loadIfNeeded()
        let id = nextID
        nextID += 1
        events.append(event.withID(id))
        try persist()
        return id
    }

    public func appendBatch(_ events: [AnalyticsEvent]) async throws -> [Int64] {
        try loadIfNeeded()
        var ids: [Int64] = []
        ids.reserveCapacity(events.count)
        for event in events {
            let id = nextID
            nextID += 1
            self.events.append(event.withID(id))
            ids.append(id)
        }
        try persist()
        return ids
    }

    public func queryPending(limit: Int) async throws -> [AnalyticsEvent] {
        try loadIfNeeded()
        let pending = events
            .filter { !$0.uploaded }
            .sorted { $0.eventTimestampMs < $1.eventTimestampMs }
        return limit > 0 ? Array(pending.prefix(limit)) : pending
    }

    public func markUploaded(ids: [Int64]) async throws {
        try loadIfNeeded()
        let idSet = Set(ids)
        events = events.map { event in
            idSet.contains(event.id) ? event.markedUploaded() : event
        }
        try persist()
    }

    @discardableResult
    public func cleanupUploaded(beforeTimestampMs: Int64) async throws -> Int {
        try loadIfNeeded()
        let before = events.count
        events.removeAll { $0.uploaded && $0.eventTimestampMs < beforeTimestampMs }
        let removed = before - events.count
        if removed > 0 { try persist() }
        return removed
    }

    public func count() async throws -> Int {
        try loadIfNeeded()
        return events.count
    }
}
