// WP-19 · SQLCipher passphrase 提供者（v15.18 · Keychain 持久 · Stage A 准备）
//
// 设计取舍（D2 §2 分级加密）：
// - 首启时生成 256 位随机 passphrase · 写 Keychain · 后续启动直接读
// - 失败（Keychain 不可用 / 系统拒绝）throws · 调用方决定 fallback（明文 / 拒启动）
// - Stage A 不主动启用：bootStoreManager 暂保留 passphrase=nil 路径（不破坏现有明文数据）
// - Stage B 切换时机：用户主动"启用加密" UI → 重新生成 passphrase + 重建数据库 + 启用此 Provider
// - 此 Provider 独立可测 · 与 StoreManager 解耦

import Foundation

public actor KeychainPassphraseProvider {

    private let keychain: any KeychainService
    private let key: String
    private let entropyBytes: Int
    private let randomGenerator: @Sendable (Int) -> Data

    public init(
        keychain: any KeychainService,
        key: String = "sqlcipher.passphrase.v1",
        entropyBytes: Int = 32,
        randomGenerator: @escaping @Sendable (Int) -> Data = KeychainPassphraseProvider.defaultRandom
    ) {
        self.keychain = keychain
        self.key = key
        self.entropyBytes = entropyBytes
        self.randomGenerator = randomGenerator
    }

    /// 拿 passphrase · 不存在则生成 + 写入 Keychain · 返回 hex 字符串（SQLCipher 接受 hex 或 raw）
    public func loadOrCreate() async throws -> String {
        do {
            let data = try await keychain.read(key: key)
            return data.hexString
        } catch KeychainError.itemNotFound {
            let fresh = randomGenerator(entropyBytes)
            try await keychain.write(key: key, data: fresh)
            return fresh.hexString
        }
    }

    /// 重置 passphrase（用户主动 "重置加密"· 删 Keychain 项 · 下次 loadOrCreate 重新生成）
    /// 注：调用前业务侧应导出 / 备份现有数据 · 否则 SQLCipher 重新创建后旧数据不可读
    public func reset() async throws {
        try await keychain.delete(key: key)
    }

    // MARK: - 默认随机源

    public static let defaultRandom: @Sendable (Int) -> Data = { count in
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }
}

// MARK: - Data hex 编码（SQLCipher passphrase 友好格式）

extension Data {
    /// 字节转小写 hex 字符串（"0a1b..." · SQLCipher PRAGMA key 接受）
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
