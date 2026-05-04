// WP-19 · 内存 Keychain 实现（v15.18 · 测试 / Linux 占位）
//
// 设计取舍：
// - 测试用：单测 / SwiftUI Preview / Linux build 不调 macOS Security framework
// - actor 串行 · 不依赖系统服务 · 进程退出后数据丢（生产用 macOSKeychainService）

import Foundation

public actor InMemoryKeychainService: KeychainService {

    private var storage: [String: Data] = [:]

    public init() {}

    public func read(key: String) async throws -> Data {
        guard let data = storage[key] else { throw KeychainError.itemNotFound }
        return data
    }

    public func write(key: String, data: Data) async throws {
        storage[key] = data
    }

    public func delete(key: String) async throws {
        storage.removeValue(forKey: key)
    }

    /// 内省（测试用）
    public func count() -> Int { storage.count }
    public func keys() -> [String] { Array(storage.keys) }
}
