// WP-19 · InMemoryKeychainService 测试（v15.18）
//
// 覆盖：read/write/delete/覆盖/便利字符串方法/不存在/idempotent

import Testing
import Foundation
@testable import Shared

@Suite("InMemoryKeychainService · 协议实现")
struct InMemoryKeychainServiceTests {

    @Test("write → read · 数据往返")
    func roundtripData() async throws {
        let kc = InMemoryKeychainService()
        let payload = "secret-123".data(using: .utf8)!
        try await kc.write(key: "passphrase", data: payload)
        let got = try await kc.read(key: "passphrase")
        #expect(got == payload)
        #expect(await kc.count() == 1)
    }

    @Test("write 同 key 二次 · 覆盖（不抛 duplicateItem · InMemory 简化语义）")
    func writeOverwrites() async throws {
        let kc = InMemoryKeychainService()
        try await kc.write(key: "k", data: Data([1, 2, 3]))
        try await kc.write(key: "k", data: Data([9, 9]))
        let got = try await kc.read(key: "k")
        #expect(got == Data([9, 9]))
    }

    @Test("read 不存在 · 抛 itemNotFound")
    func readMissingThrows() async {
        let kc = InMemoryKeychainService()
        await #expect(throws: KeychainError.itemNotFound) {
            try await kc.read(key: "missing")
        }
    }

    @Test("delete · 不存在 idempotent 不抛")
    func deleteMissingIdempotent() async throws {
        let kc = InMemoryKeychainService()
        try await kc.delete(key: "never-existed")
    }

    @Test("delete · 存在则移除")
    func deleteRemoves() async throws {
        let kc = InMemoryKeychainService()
        try await kc.write(key: "x", data: Data([0xFF]))
        try await kc.delete(key: "x")
        await #expect(throws: KeychainError.itemNotFound) {
            try await kc.read(key: "x")
        }
        #expect(await kc.count() == 0)
    }

    @Test("writeString / readString · UTF-8 便利方法")
    func stringConvenience() async throws {
        let kc = InMemoryKeychainService()
        try await kc.writeString(key: "user_token", value: "你好-🔐-token-中")
        let got = try await kc.readString(key: "user_token")
        #expect(got == "你好-🔐-token-中")
    }

    @Test("KeychainError · 4 case 描述非空（防国际化漏字段）")
    func errorDescriptionsNonEmpty() {
        let cases: [KeychainError] = [
            .itemNotFound, .duplicateItem, .ioFailed("x")
        ]
        for c in cases {
            #expect(!c.description.isEmpty)
        }
    }
}
