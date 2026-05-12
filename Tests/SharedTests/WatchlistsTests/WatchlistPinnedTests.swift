// v17.133 · Watchlist 置顶合约单测（pinnedInstrumentIDs · 每组 ≤ 3）

import Testing
import Foundation
@testable import Shared

@Suite("Watchlist · v17.133 置顶合约（pinnedInstrumentIDs）")
struct WatchlistPinnedTests {

    @Test("默认 pinnedInstrumentIDs 为 nil（向后兼容旧 JSON）")
    func defaultsToNil() {
        let g = Watchlist(name: "主力")
        #expect(g.pinnedInstrumentIDs == nil)
    }

    @Test("pinInstrument · 写入 + 读回 + isPinned")
    func pinAndRead() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "主力")
        _ = book.addInstrument("RB0", to: g.id)
        let ok = book.pinInstrument("RB0", in: g.id)
        #expect(ok)
        #expect(book.isPinned("RB0", in: g.id))
        #expect(book.group(id: g.id)?.pinnedInstrumentIDs == ["RB0"])
    }

    @Test("pinInstrument · 合约不在分组 → false")
    func pinUnknownInstrument() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        let ok = book.pinInstrument("不存在", in: g.id)
        #expect(!ok)
    }

    @Test("pinInstrument · 已置顶幂等 + version 不 bump")
    func pinIdempotent() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "主力")
        _ = book.addInstrument("RB0", to: g.id)
        _ = book.pinInstrument("RB0", in: g.id)
        let v1 = book.group(id: g.id)!.version
        let ok = book.pinInstrument("RB0", in: g.id)   // 再 pin 同一个
        #expect(!ok)
        #expect(book.group(id: g.id)!.version == v1)
    }

    @Test("pinInstrument · 上限 3 后拒绝")
    func pinMaxCap() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        for i in 0..<5 { _ = book.addInstrument("I\(i)", to: g.id) }
        let ok0 = book.pinInstrument("I0", in: g.id)
        let ok1 = book.pinInstrument("I1", in: g.id)
        let ok2 = book.pinInstrument("I2", in: g.id)
        let ok3 = book.pinInstrument("I3", in: g.id)
        #expect(ok0 && ok1 && ok2)
        #expect(!ok3)   // 第 4 个拒绝
        #expect(book.group(id: g.id)?.pinnedInstrumentIDs?.count == 3)
    }

    @Test("unpinInstrument · 移除 + 空数组写回 nil（紧凑）")
    func unpin() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB0", to: g.id)
        _ = book.pinInstrument("RB0", in: g.id)
        let ok = book.unpinInstrument("RB0", in: g.id)
        #expect(ok)
        #expect(book.group(id: g.id)?.pinnedInstrumentIDs == nil)   // 空 → nil
        let again = book.unpinInstrument("RB0", in: g.id)
        #expect(!again)   // 重复 unpin → false
    }

    @Test("removeInstrument · 同步清掉置顶引用（防 stale）")
    func removeInstrumentClearsPin() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组")
        _ = book.addInstrument("RB0", to: g.id)
        _ = book.addInstrument("AU0", to: g.id)
        _ = book.pinInstrument("RB0", in: g.id)
        _ = book.pinInstrument("AU0", in: g.id)
        _ = book.removeInstrument("RB0", from: g.id)
        #expect(book.group(id: g.id)?.pinnedInstrumentIDs == ["AU0"])
        #expect(!book.isPinned("RB0", in: g.id))
    }

    @Test("跨组 moveInstrument · 清源组置顶 · 目标组不带过去")
    func crossGroupMoveClearsPin() {
        var book = WatchlistBook()
        let a = book.addGroup(name: "A")
        let b = book.addGroup(name: "B")
        _ = book.addInstrument("RB0", to: a.id)
        _ = book.pinInstrument("RB0", in: a.id)
        _ = book.moveInstrument("RB0", from: a.id, to: b.id)
        #expect(book.group(id: a.id)?.pinnedInstrumentIDs == nil)
        #expect(book.group(id: b.id)?.pinnedInstrumentIDs == nil)   // 不携带
        #expect(book.group(id: b.id)?.instrumentIDs == ["RB0"])
    }

    @Test("Codable 往返保留 pinnedInstrumentIDs")
    func codableRoundTrip() throws {
        var book = WatchlistBook()
        let g = book.addGroup(name: "主力")
        _ = book.addInstrument("RB0", to: g.id)
        _ = book.addInstrument("AU0", to: g.id)
        _ = book.pinInstrument("RB0", in: g.id)
        _ = book.pinInstrument("AU0", in: g.id)
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(WatchlistBook.self, from: data)
        let dg = decoded.groups.first(where: { $0.id == g.id })
        #expect(dg?.pinnedInstrumentIDs == ["RB0", "AU0"])
    }

    @Test("旧 JSON（缺 pinnedInstrumentIDs）decode 兼容")
    func oldJSONCompat() throws {
        let oldJSON = """
        {
          "id": "\(UUID().uuidString)",
          "name": "主力",
          "sortIndex": 0,
          "instrumentIDs": ["RB0"],
          "createdAt": 0.0,
          "updatedAt": 0.0,
          "version": 1
        }
        """
        let g = try JSONDecoder().decode(Watchlist.self, from: oldJSON.data(using: .utf8)!)
        #expect(g.pinnedInstrumentIDs == nil)
    }
}
