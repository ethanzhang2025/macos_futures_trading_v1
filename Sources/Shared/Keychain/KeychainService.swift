// WP-19 · Keychain 服务协议（v15.18 · 基础设施预埋）
//
// 设计取舍（D2 §2 分级加密）：
// - 协议先行 · 多实现：InMemory（测试 / Linux）+ macOS Security framework（生产）
// - 仅暴露三方法 read / write / delete · 满足 SQLCipher passphrase / IAP receipt / Apple ID token 等场景
// - 失败用 KeychainError 显式区分（itemNotFound / unhandledError）· 调用方决定 fallback
// - Stage A 先用于 SQLCipher passphrase（避免明文 UserDefaults）· Stage B IAP 接入扩展

import Foundation

public enum KeychainError: Error, CustomStringConvertible, Equatable {
    case itemNotFound
    case duplicateItem
    case ioFailed(String)

    public var description: String {
        switch self {
        case .itemNotFound:        return "Keychain 项不存在"
        case .duplicateItem:       return "Keychain 项已存在"
        case .ioFailed(let m):     return "Keychain IO 失败: \(m)"
        }
    }
}

public protocol KeychainService: Sendable {
    /// 读取 · 不存在抛 itemNotFound
    func read(key: String) async throws -> Data

    /// 写入 · 已存在则覆盖
    func write(key: String, data: Data) async throws

    /// 删除 · 不存在静默成功（idempotent · 与 SQL DELETE 语义一致）
    func delete(key: String) async throws
}

public extension KeychainService {

    /// String 读取便利方法
    func readString(key: String) async throws -> String {
        let data = try await read(key: key)
        guard let s = String(data: data, encoding: .utf8) else {
            throw KeychainError.ioFailed("UTF-8 解码失败")
        }
        return s
    }

    /// String 写入便利方法
    func writeString(key: String, value: String) async throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.ioFailed("UTF-8 编码失败")
        }
        try await write(key: key, data: data)
    }
}
