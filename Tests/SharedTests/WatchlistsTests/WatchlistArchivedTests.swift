// v17.145 · Watchlist 存档合约单测（archivedInstrumentIDs · 已平仓 / 历史合约不显示但不删）
// 与 v17.133 pinnedInstrumentIDs 同模式 · pin/archive 互斥（archive 时同步 unpin · 已 archived 不可 pin）

import Testing
import Foundation
@testable import Shared

@Suite("Watchlist · v17.145 存档合约（archivedInstrumentIDs）")
struct WatchlistArchivedTests {

    @Test("默认 archivedInstrumentIDs 为 nil（向后兼容旧 JSON）")
    func defaultsToNil() {
        let g = Watchlist(name: "主力")
        #expect(g.archivedInstrumentIDs == nil)
    }

    @Test("archiveInstrument · 写入 + 读回 + isArchived")
    func archiveAndRead() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        let ok = book.archiveInstrument("RB2401", in: g.id)
        #expect(ok)
        #expect(book.isArchived("RB2401", in: g.id))
        #expect(book.group(id: g.id)?.archivedInstrumentIDs == ["RB2401"])
    }

    @Test("archiveInstrument · 合约不在分组 → false")
    func archiveUnknownInstrument() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        let ok = book.archiveInstrument("不存在", in: g.id)
        #expect(!ok)
    }

    @Test("archiveInstrument · 已存档幂等 + version 不 bump")
    func archiveIdempotent() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.archiveInstrument("RB2401", in: g.id)
        let v1 = book.group(id: g.id)!.version
        let ok = book.archiveInstrument("RB2401", in: g.id)
        #expect(!ok)
        #expect(book.group(id: g.id)!.version == v1)
    }

    @Test("unarchiveInstrument · 移除 + 空数组写回 nil（紧凑）")
    func unarchive() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.archiveInstrument("RB2401", in: g.id)
        let ok = book.unarchiveInstrument("RB2401", in: g.id)
        #expect(ok)
        #expect(book.group(id: g.id)?.archivedInstrumentIDs == nil)
        let again = book.unarchiveInstrument("RB2401", in: g.id)
        #expect(!again)
    }

    @Test("archive 与 pin 互斥 · archive 时同步 unpin（archive 优先级高）")
    func archiveClearsPin() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "主力")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.pinInstrument("RB2401", in: g.id)
        #expect(book.isPinned("RB2401", in: g.id))
        let ok = book.archiveInstrument("RB2401", in: g.id)
        #expect(ok)
        #expect(book.isArchived("RB2401", in: g.id))
        #expect(!book.isPinned("RB2401", in: g.id))   // 同步 unpin
        #expect(book.group(id: g.id)?.pinnedInstrumentIDs == nil)
    }

    @Test("已 archived 合约不可 pin（pinInstrument 返回 false）")
    func archivedCannotPin() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.archiveInstrument("RB2401", in: g.id)
        let ok = book.pinInstrument("RB2401", in: g.id)
        #expect(!ok)
        #expect(!book.isPinned("RB2401", in: g.id))
    }

    @Test("removeInstrument · 同步清掉存档引用（防 stale）")
    func removeInstrumentClearsArchive() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.addInstrument("AU2401", to: g.id)
        _ = book.archiveInstrument("RB2401", in: g.id)
        _ = book.archiveInstrument("AU2401", in: g.id)
        _ = book.removeInstrument("RB2401", from: g.id)
        #expect(book.group(id: g.id)?.archivedInstrumentIDs == ["AU2401"])
        #expect(!book.isArchived("RB2401", in: g.id))
    }

    @Test("跨组 moveInstrument · 清源组存档 · 目标组不带过去")
    func crossGroupMoveClearsArchive() {
        var book = WatchlistBook()
        let a = book.addGroup(name: "A")
        let b = book.addGroup(name: "B")
        _ = book.addInstrument("RB2401", to: a.id)
        _ = book.archiveInstrument("RB2401", in: a.id)
        _ = book.moveInstrument("RB2401", from: a.id, to: b.id)
        #expect(book.group(id: a.id)?.archivedInstrumentIDs == nil)
        #expect(book.group(id: b.id)?.archivedInstrumentIDs == nil)   // 不携带（trader 重新决策）
        #expect(book.group(id: b.id)?.instrumentIDs == ["RB2401"])
    }

    @Test("Codable 往返保留 archivedInstrumentIDs")
    func codableRoundTrip() throws {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB2401", to: g.id)
        _ = book.addInstrument("AU2401", to: g.id)
        _ = book.archiveInstrument("RB2401", in: g.id)
        _ = book.archiveInstrument("AU2401", in: g.id)
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(WatchlistBook.self, from: data)
        let dg = decoded.groups.first(where: { $0.id == g.id })
        #expect(dg?.archivedInstrumentIDs == ["RB2401", "AU2401"])
    }

    @Test("旧 JSON（缺 archivedInstrumentIDs）decode 兼容 · v17.144 之前 JSON 全字段保留")
    func oldJSONCompat() throws {
        // v17.144 之前 JSON 含 pinnedInstrumentIDs 但无 archivedInstrumentIDs
        let oldJSON = """
        {
          "id": "\(UUID().uuidString)",
          "name": "主力",
          "sortIndex": 0,
          "instrumentIDs": ["RB0", "AU0"],
          "createdAt": 0.0,
          "updatedAt": 0.0,
          "version": 1,
          "pinnedInstrumentIDs": ["RB0"]
        }
        """
        let g = try JSONDecoder().decode(Watchlist.self, from: oldJSON.data(using: .utf8)!)
        #expect(g.archivedInstrumentIDs == nil)
        #expect(g.pinnedInstrumentIDs == ["RB0"])   // 已有字段保留
    }
}
