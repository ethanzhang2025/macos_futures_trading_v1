// v17.131 · Watchlist group 独立排序规则单测（sortFieldRaw + sortAscending）

import Testing
import Foundation
@testable import Shared

@Suite("Watchlist · v17.131 group 独立排序")
struct WatchlistGroupSortTests {

    @Test("默认 sortFieldRaw + sortAscending 为 nil（向后兼容旧 JSON）")
    func defaultsToNil() {
        let g = Watchlist(name: "主力")
        #expect(g.sortFieldRaw == nil)
        #expect(g.sortAscending == nil)
    }

    @Test("setGroupSort · 写入 + 读回")
    func setAndRead() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "龙虎榜")
        let ok = book.setGroupSort(id: g.id, sortFieldRaw: "changePct", sortAscending: false)
        #expect(ok)
        #expect(book.group(id: g.id)?.sortFieldRaw == "changePct")
        #expect(book.group(id: g.id)?.sortAscending == false)
    }

    @Test("setGroupSort · 不存在的 group → false")
    func notFound() {
        var book = WatchlistBook()
        let ok = book.setGroupSort(id: UUID(), sortFieldRaw: "volume", sortAscending: true)
        #expect(!ok)
    }

    @Test("setGroupSort · 相同值幂等 · 不改 version")
    func idempotent() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组 1")
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "changePct", sortAscending: false)
        let v1 = book.group(id: g.id)!.version
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "changePct", sortAscending: false)   // 相同
        let v2 = book.group(id: g.id)!.version
        #expect(v1 == v2)
    }

    @Test("setGroupSort · 改字段 version +1")
    func changeBumpsVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组 1")
        let v1 = book.group(id: g.id)!.version
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "volume", sortAscending: true)
        #expect(book.group(id: g.id)!.version == v1 + 1)
    }

    @Test("setGroupSort · 改升降序 version +1")
    func changeAscendingBumpsVersion() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组 1")
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "volume", sortAscending: false)
        let v1 = book.group(id: g.id)!.version
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "volume", sortAscending: true)
        #expect(book.group(id: g.id)!.version == v1 + 1)
    }

    @Test("setGroupSort · nil 恢复默认")
    func nilResetsToDefault() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组 1")
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "volume", sortAscending: true)
        _ = book.setGroupSort(id: g.id, sortFieldRaw: nil, sortAscending: nil)
        #expect(book.group(id: g.id)?.sortFieldRaw == nil)
        #expect(book.group(id: g.id)?.sortAscending == nil)
    }

    @Test("Codable 往返保留 sortFieldRaw + sortAscending")
    func codableRoundTrip() throws {
        var book = WatchlistBook()
        let g = book.addGroup(name: "组 1")
        _ = book.setGroupSort(id: g.id, sortFieldRaw: "volume", sortAscending: true)
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(WatchlistBook.self, from: data)
        let decodedG = decoded.groups.first(where: { $0.id == g.id })
        #expect(decodedG?.sortFieldRaw == "volume")
        #expect(decodedG?.sortAscending == true)
    }

    @Test("旧 JSON（缺 sortFieldRaw / sortAscending）decode 兼容")
    func oldJSONCompat() throws {
        // 模拟 v17.130 前 JSON（无 sortFieldRaw / sortAscending 字段）
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
        #expect(g.sortFieldRaw == nil)
        #expect(g.sortAscending == nil)
    }
}
