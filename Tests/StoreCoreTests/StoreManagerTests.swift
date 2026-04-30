// WP-19a-7 · StoreManager 单元测试（WP-19a-8 起 7 store）
// 验证：路径自动创建 / 7 store 文件创建 / 加密 vs 明文 / close 后不可用 / 加密往返 / 错密钥拒绝

import Testing
import Foundation
import StoreCore
import Shared
import DataCore
import JournalCore
import AlertCore

private func tempRoot(_ tag: String = "wp19a7") -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(tag)_\(UUID().uuidString)", isDirectory: true)
}

private func makeEvent(_ tag: String = "x", ts: Int64 = 1_745_500_000_000) -> AnalyticsEvent {
    AnalyticsEvent(
        id: 0,
        userID: "u-test",
        deviceID: "d-test",
        sessionID: "s-test",
        eventName: .appLaunch,
        eventTimestampMs: ts,
        properties: ["tag": tag],
        appVersion: "0.0.1",
        uploaded: false
    )
}

private let sqliteMagic = Data([
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20,
    0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33
])

@Suite("WP-19a-7 · StoreManager · 7 store 统一管理器")
struct StoreManagerTests {

    @Test("init 自动创建根目录 · 7 个 .sqlite 文件全部就位")
    func initCreatesDirectoryAndAllFiles() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(FileManager.default.fileExists(atPath: dir.path) == false)

        let manager = try StoreManager(rootDirectory: dir)

        #expect(FileManager.default.fileExists(atPath: dir.path))
        for name in StoreManager.allFileNames {
            let p = dir.appendingPathComponent(name).path
            #expect(FileManager.default.fileExists(atPath: p), "\(name) not created")
        }

        await manager.close()
    }

    @Test("init(passphrase: nil) · isEncrypted=false · 文件头是明文 SQLite")
    func plaintextManagerHasSQLiteHeader() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = try StoreManager(rootDirectory: dir, passphrase: nil)
        #expect(manager.isEncrypted == false)

        _ = try await manager.analytics.append(makeEvent("p1"))
        await manager.close()

        let path = dir.appendingPathComponent(StoreManager.analyticsFileName).path
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(data.prefix(15) == sqliteMagic)
    }

    @Test("init(passphrase:) · isEncrypted=true · 文件头乱码（无 SQLite magic）")
    func encryptedManagerHidesHeader() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = try StoreManager(rootDirectory: dir, passphrase: "secret-001")
        #expect(manager.isEncrypted == true)

        _ = try await manager.analytics.append(makeEvent("e1"))
        await manager.close()

        let path = dir.appendingPathComponent(StoreManager.analyticsFileName).path
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(data.prefix(15) != sqliteMagic, "encrypted file should not start with SQLite magic")
    }

    @Test("空 passphrase 等价于 nil · 同一目录可被 nil manager 重新打开")
    func emptyPassphraseEquivalentToNil() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let m1 = try StoreManager(rootDirectory: dir, passphrase: "")
        #expect(m1.isEncrypted == false)
        _ = try await m1.analytics.append(makeEvent("a"))
        await m1.close()

        let m2 = try StoreManager(rootDirectory: dir, passphrase: nil)
        let count = try await m2.analytics.count()
        #expect(count == 1)
        await m2.close()
    }

    @Test("自动创建多级嵌套目录")
    func autoCreateNestedDirectory() async throws {
        let base = tempRoot()
        defer { try? FileManager.default.removeItem(at: base) }
        let nested = base
            .appendingPathComponent("alpha", isDirectory: true)
            .appendingPathComponent("beta", isDirectory: true)
            .appendingPathComponent("gamma", isDirectory: true)

        #expect(FileManager.default.fileExists(atPath: nested.path) == false)
        let manager = try StoreManager(rootDirectory: nested)
        #expect(FileManager.default.fileExists(atPath: nested.path))
        await manager.close()
    }

    @Test("加密 manager 写入 → 关闭 → 同密钥重开 → 数据可读")
    func encryptedRoundTrip() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let m1 = try StoreManager(rootDirectory: dir, passphrase: "key-A")
        _ = try await m1.analytics.append(makeEvent("seq-1"))
        _ = try await m1.analytics.append(makeEvent("seq-2"))
        let countBefore = try await m1.analytics.count()
        #expect(countBefore == 2)
        await m1.close()

        let m2 = try StoreManager(rootDirectory: dir, passphrase: "key-A")
        let countAfter = try await m2.analytics.count()
        #expect(countAfter == 2)
        await m2.close()
    }

    @Test("错误密钥打开已加密目录 → init 抛错")
    func wrongPassphraseRejected() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let m1 = try StoreManager(rootDirectory: dir, passphrase: "key-correct")
        _ = try await m1.analytics.append(makeEvent("c"))
        await m1.close()

        #expect(
            (try? StoreManager(rootDirectory: dir, passphrase: "key-WRONG")) == nil,
            "wrong passphrase should be rejected"
        )
    }

    @Test("close 后 store 写操作抛错")
    func closeReleasesStores() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = try StoreManager(rootDirectory: dir)
        await manager.close()

        let result = try? await manager.analytics.append(makeEvent("x"))
        #expect(result == nil, "operation after close should throw")
    }

    @Test("rootDirectory / isEncrypted 内省正确")
    func introspectionConsistent() async throws {
        let dir = tempRoot()
        defer { try? FileManager.default.removeItem(at: dir) }

        let m = try StoreManager(rootDirectory: dir, passphrase: "k")
        #expect(m.rootDirectory == dir)
        #expect(m.isEncrypted == true)
        await m.close()
    }

    @Test("allFileNames 与 8 个公开常量一致 · 无遗漏无重复（v13.2 加 drawings）")
    func allFileNamesMatchConstants() {
        let names = StoreManager.allFileNames
        #expect(names.count == 8)
        #expect(Set(names).count == 8)
        #expect(names.contains(StoreManager.analyticsFileName))
        #expect(names.contains(StoreManager.klineFileName))
        #expect(names.contains(StoreManager.journalFileName))
        #expect(names.contains(StoreManager.alertHistoryFileName))
        #expect(names.contains(StoreManager.alertConfigFileName))
        #expect(names.contains(StoreManager.watchlistFileName))
        #expect(names.contains(StoreManager.workspaceFileName))
        #expect(names.contains(StoreManager.drawingsFileName))
    }
}
