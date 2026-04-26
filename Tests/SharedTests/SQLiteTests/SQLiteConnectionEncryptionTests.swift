// WP-19b · SQLiteConnection 加密层单元测试
// SQLCipher 接口验证：加密往返 / 错误密钥拒绝 / 非加密文件用密钥拒绝 / 加密文件不传密钥拒绝 / 空密码等价非加密

import Testing
import Foundation
@testable import Shared

private func tempPath(_ tag: String = "wp19b") -> String {
    NSTemporaryDirectory().appending("\(tag)_\(UUID().uuidString).sqlite")
}

@Suite("SQLiteConnection · WP-19b 加密层")
struct SQLiteConnectionEncryptionTests {

    @Test("加密往返：写入 → 关闭 → 用同密钥重开 → 读回原数据")
    func encryptedRoundTrip() async throws {
        let path = tempPath("encrypted")
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let conn = try SQLiteConnection(path: path, passphrase: "secret-key-001")
            try await conn.exec("CREATE TABLE t (id INTEGER, name TEXT);")
            _ = try await conn.executeReturningChanges("INSERT INTO t VALUES (?, ?);",
                                                         bind: [.integer(1), .text("hello")])
            await conn.close()
        }

        let conn2 = try SQLiteConnection(path: path, passphrase: "secret-key-001")
        let rows: [(Int64, String)] = try await conn2.query(
            "SELECT id, name FROM t;"
        ) { stmt in (stmt.int64(at: 0), stmt.string(at: 1) ?? "") }
        #expect(rows.count == 1)
        #expect(rows[0].0 == 1)
        #expect(rows[0].1 == "hello")
        await conn2.close()
    }

    @Test("错误密钥拒绝：用错误密码打开加密文件 → 抛 execFailed（SQLITE_NOTADB）")
    func wrongPassphraseRejected() async throws {
        let path = tempPath("encrypted")
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let conn = try SQLiteConnection(path: path, passphrase: "correct-key")
            try await conn.exec("CREATE TABLE t (id INTEGER);")
            _ = try await conn.executeReturningChanges("INSERT INTO t VALUES (1);")
            await conn.close()
        }

        var didThrow = false
        do {
            _ = try SQLiteConnection(path: path, passphrase: "wrong-key")
        } catch {
            didThrow = true
        }
        #expect(didThrow == true)
    }

    @Test("非加密文件用密钥打开：拒绝（execFailed · 现有明文不识别为加密）")
    func plaintextWithKeyRejected() async throws {
        let path = tempPath("plaintext")
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let conn = try SQLiteConnection(path: path)
            try await conn.exec("CREATE TABLE t (id INTEGER);")
            await conn.close()
        }

        var didThrow = false
        do {
            _ = try SQLiteConnection(path: path, passphrase: "key")
        } catch {
            didThrow = true
        }
        #expect(didThrow == true)
    }

    @Test("加密文件不传密钥：拒绝（execFailed · 验证 sqlite_master 失败）")
    func encryptedWithoutKeyRejected() async throws {
        let path = tempPath("encrypted")
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let conn = try SQLiteConnection(path: path, passphrase: "secret")
            try await conn.exec("CREATE TABLE t (id INTEGER);")
            await conn.close()
        }

        // 不传密钥打开，sqlite3_open 本身会成功（懒加载），但首次访问 sqlite_master 抛错
        let conn = try SQLiteConnection(path: path)  // open 成功
        var didThrow = false
        do {
            _ = try await conn.query("SELECT count(*) FROM sqlite_master;") { _ in 0 }
        } catch {
            didThrow = true
        }
        #expect(didThrow == true)
        await conn.close()
    }

    @Test("空密码等价非加密：passphrase: \"\" 不调 sqlite3_key · 文件可被原生 SQLite 读取")
    func emptyPassphraseEquivalentToNoEncryption() async throws {
        let path = tempPath("emptypass")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // 空字符串密码 → 不加密路径
        let conn = try SQLiteConnection(path: path, passphrase: "")
        try await conn.exec("CREATE TABLE t (id INTEGER, name TEXT);")
        _ = try await conn.executeReturningChanges("INSERT INTO t VALUES (?, ?);",
                                                     bind: [.integer(42), .text("ok")])
        await conn.close()

        // 用纯非加密 init 打开（同文件） → 应能读
        let conn2 = try SQLiteConnection(path: path)
        let rows: [Int64] = try await conn2.query("SELECT id FROM t;") { stmt in stmt.int64(at: 0) }
        #expect(rows == [42])
        await conn2.close()
    }

    @Test("nil passphrase 等价旧 init(path:) · 现有 6 store 行为不变")
    func nilPassphraseBackwardCompatible() async throws {
        let path = tempPath("nilpass")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let conn = try SQLiteConnection(path: path, passphrase: nil)
        try await conn.exec("CREATE TABLE t (id INTEGER);")
        _ = try await conn.executeReturningChanges("INSERT INTO t VALUES (?);", bind: [.integer(7)])
        await conn.close()

        let conn2 = try SQLiteConnection(path: path)
        let rows: [Int64] = try await conn2.query("SELECT id FROM t;") { stmt in stmt.int64(at: 0) }
        #expect(rows == [7])
        await conn2.close()
    }
}
