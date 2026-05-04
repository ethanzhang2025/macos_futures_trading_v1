// WP-19 · KeychainPassphraseProvider 测试（v15.18）

import Testing
import Foundation
@testable import Shared

@Suite("KeychainPassphraseProvider · loadOrCreate")
struct KeychainPassphraseProviderTests {

    @Test("首次调 · 生成 + 写 Keychain · 返回 hex")
    func firstCallGeneratesAndWrites() async throws {
        let kc = InMemoryKeychainService()
        // 注入固定随机序列 · 验证 hex 输出可预测
        let fixedRandom: @Sendable (Int) -> Data = { count in
            Data(repeating: 0xAB, count: count)
        }
        let provider = KeychainPassphraseProvider(keychain: kc, entropyBytes: 4, randomGenerator: fixedRandom)
        let pw = try await provider.loadOrCreate()
        #expect(pw == "abababab")    // 4 字节 0xAB → "abababab"
        // Keychain 中已写
        let stored = try await kc.read(key: "sqlcipher.passphrase.v1")
        #expect(stored == Data(repeating: 0xAB, count: 4))
    }

    @Test("第二次调 · 读 Keychain 返回相同 hex（不重新生成）")
    func secondCallReadsExisting() async throws {
        let kc = InMemoryKeychainService()
        let fixedRandom: @Sendable (Int) -> Data = { _ in Data([0x12, 0x34, 0x56, 0x78]) }
        let provider = KeychainPassphraseProvider(keychain: kc, entropyBytes: 4, randomGenerator: fixedRandom)
        let first = try await provider.loadOrCreate()
        let second = try await provider.loadOrCreate()
        #expect(first == second)
        #expect(first == "12345678")
    }

    @Test("reset · 删 Keychain · 下次 loadOrCreate 重新生成（不同种子 = 不同结果）")
    func resetRegenerates() async throws {
        let kc = InMemoryKeychainService()
        // 第一次：用 0xAA 种子 · loadOrCreate 写入 0xAA*4
        let provider1 = KeychainPassphraseProvider(
            keychain: kc, entropyBytes: 4,
            randomGenerator: { Data(repeating: 0xAA, count: $0) }
        )
        let pw1 = try await provider1.loadOrCreate()
        #expect(pw1 == "aaaaaaaa")

        // reset 删 Keychain · 验证已清
        try await provider1.reset()
        await #expect(throws: KeychainError.itemNotFound) {
            try await kc.read(key: "sqlcipher.passphrase.v1")
        }

        // 用新种子的 provider2 重新 loadOrCreate · 应生成新 passphrase
        let provider2 = KeychainPassphraseProvider(
            keychain: kc, entropyBytes: 4,
            randomGenerator: { Data(repeating: 0xBB, count: $0) }
        )
        let pw2 = try await provider2.loadOrCreate()
        #expect(pw2 == "bbbbbbbb")
        #expect(pw1 != pw2)
    }

    @Test("默认 randomGenerator · 32 字节 = 64 hex 字符（SQLCipher 256 位）")
    func defaultRandomLength() async throws {
        let kc = InMemoryKeychainService()
        let provider = KeychainPassphraseProvider(keychain: kc)
        let pw = try await provider.loadOrCreate()
        #expect(pw.count == 64)   // 32 bytes × 2 hex chars
        // 验证全 hex 字符（不含换行 / 控制字符）
        let validHex = pw.allSatisfy { "0123456789abcdef".contains($0) }
        #expect(validHex)
    }

    @Test("Data.hexString · 边界 · 0x00 / 0xFF / 空")
    func hexStringEncodings() {
        #expect(Data().hexString == "")
        #expect(Data([0x00]).hexString == "00")
        #expect(Data([0xFF]).hexString == "ff")
        #expect(Data([0x00, 0x0F, 0xF0, 0xFF]).hexString == "000ff0ff")
    }
}
