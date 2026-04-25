// WP-21a · K 线缓存的 JSON 文件实现
// 文件路径：{rootDirectory}/{sanitized-instrumentID}_{period.rawValue}.json
// 序列化：iso8601 日期 + 排序 keys（diff 友好 + 缓存击穿可观察）
// 并发：actor 隔离 + FileManager 操作走 actor 线程

import Foundation
import Shared

/// JSON 文件 K 线缓存 · production 实现
/// 数据规模：单合约单周期 ≤ 数千根 K 线（启动加速用，全量历史走 HistoricalKLineProvider）
public actor JSONFileKLineCacheStore: KLineCacheStore {

    public let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - rootDirectory: 缓存根目录（不存在则在首次写入时创建）
    ///   - fileManager: 注入便于测试
    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - KLineCacheStore

    public func load(instrumentID: String, period: KLinePeriod) async throws -> [KLine] {
        let url = cacheFile(instrumentID: instrumentID, period: period)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([KLine].self, from: data)
    }

    public func save(_ klines: [KLine], instrumentID: String, period: KLinePeriod) async throws {
        try ensureRootExists()
        let url = cacheFile(instrumentID: instrumentID, period: period)
        let sorted = klines.sorted { $0.openTime < $1.openTime }
        let data = try encoder.encode(sorted)
        try data.write(to: url, options: .atomic)
    }

    public func append(_ klines: [KLine], instrumentID: String, period: KLinePeriod, maxBars: Int) async throws {
        let existing = try await load(instrumentID: instrumentID, period: period)
        let merged = InMemoryKLineCacheStore.merged(existing: existing, incoming: klines, maxBars: maxBars)
        try await save(merged, instrumentID: instrumentID, period: period)
    }

    public func clear(instrumentID: String, period: KLinePeriod) async throws {
        let url = cacheFile(instrumentID: instrumentID, period: period)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func clearAll() async throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.removeItem(at: rootDirectory)
    }

    // MARK: - 私有

    private func cacheFile(instrumentID: String, period: KLinePeriod) -> URL {
        let safeID = Self.sanitize(instrumentID)
        return rootDirectory.appendingPathComponent("\(safeID)_\(period.rawValue).json")
    }

    private func ensureRootExists() throws {
        guard !fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// 把 instrumentID 中可能影响文件路径的字符替换为 _
    /// 期货合约 ID 通常是字母 + 数字（rb2510 / IF2510），少数交易所可能用点号（IF.CFFEX.2510）
    static func sanitize(_ id: String) -> String {
        String(id.unicodeScalars.map { allowedFileNameChars.contains($0) ? Character($0) : "_" })
    }

    private static let allowedFileNameChars: CharacterSet = .alphanumerics.union(CharacterSet(charactersIn: "-"))
}
