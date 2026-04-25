// WP-43 · 自选管理 v1 测试
// 分组 CRUD · 合约 CRUD · 拖拽排序 · 同组去重 · 边界 · Codable 往返 · CloudKit 字段映射
//
// 注：Swift Testing 的 #expect 宏对 mutating 调用有限制（闭包内 self 是 immutable），
//     所有 mutating 方法的返回值必须先存临时变量再 #expect

import Testing
import Foundation
@testable import Shared

// MARK: - 测试辅助

private func makeBook(groupNames: [String] = []) -> WatchlistBook {
    var book = WatchlistBook()
    for name in groupNames { book.addGroup(name: name) }
    return book
}

// MARK: - 1. 分组级 CRUD

@Suite("WatchlistBook · 分组 CRUD")
struct WatchlistGroupCRUDTests {

    @Test("addGroup 自动分配 sortIndex 与 id")
    func addGroupAssignsSortIndex() {
        var book = WatchlistBook()
        let g1 = book.addGroup(name: "主力")
        let g2 = book.addGroup(name: "黑色")
        let g3 = book.addGroup(name: "化工")

        #expect(g1.sortIndex == 0)
        #expect(g2.sortIndex == 1)
        #expect(g3.sortIndex == 2)
        #expect(book.groups.count == 3)
        #expect(book.groups.map(\.name) == ["主力", "黑色", "化工"])
    }

    @Test("renameGroup 命中与不命中")
    func renameGroup() {
        var book = makeBook(groupNames: ["主力"])
        let id = book.groups[0].id

        let hit = book.renameGroup(id: id, to: "热门主力")
        #expect(hit)
        #expect(book.groups[0].name == "热门主力")

        let miss = book.renameGroup(id: UUID(), to: "X")
        #expect(!miss)
    }

    @Test("removeGroup 后 sortIndex 自动重排连续")
    func removeGroupNormalizesSortIndex() {
        var book = makeBook(groupNames: ["A", "B", "C", "D"])
        let bID = book.groups[1].id

        let hit = book.removeGroup(id: bID)
        #expect(hit)
        #expect(book.groups.map(\.name) == ["A", "C", "D"])
        #expect(book.groups.map(\.sortIndex) == [0, 1, 2])
    }

    @Test("removeGroup 不存在返回 false")
    func removeGroupMiss() {
        var book = makeBook(groupNames: ["A"])
        let miss = book.removeGroup(id: UUID())
        #expect(!miss)
        #expect(book.groups.count == 1)
    }
}

// MARK: - 2. 分组拖拽排序

@Suite("WatchlistBook · 分组拖拽排序")
struct WatchlistMoveGroupTests {

    @Test("moveGroup 向后移动")
    func moveGroupForward() {
        var book = makeBook(groupNames: ["A", "B", "C", "D"])
        let ok = book.moveGroup(from: 0, to: 3)
        #expect(ok)
        #expect(book.groups.map(\.name) == ["B", "C", "A", "D"])
        #expect(book.groups.map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test("moveGroup 向前移动")
    func moveGroupBackward() {
        var book = makeBook(groupNames: ["A", "B", "C", "D"])
        let ok = book.moveGroup(from: 3, to: 0)
        #expect(ok)
        #expect(book.groups.map(\.name) == ["D", "A", "B", "C"])
    }

    @Test("moveGroup 边界：from == to / 越界")
    func moveGroupEdgeCases() {
        var book = makeBook(groupNames: ["A", "B"])
        let same = book.moveGroup(from: 0, to: 0)
        let oobFrom = book.moveGroup(from: 5, to: 0)
        let oobTo = book.moveGroup(from: 0, to: -1)
        #expect(!same)
        #expect(!oobFrom)
        #expect(!oobTo)
        #expect(book.groups.map(\.name) == ["A", "B"])
    }
}

// MARK: - 3. 合约级 CRUD

@Suite("WatchlistBook · 合约 CRUD 与去重")
struct WatchlistInstrumentCRUDTests {

    @Test("addInstrument 同组去重")
    func addInstrumentDedup() {
        var book = makeBook(groupNames: ["主力"])
        let gid = book.groups[0].id

        let r1 = book.addInstrument("rb2510", to: gid)
        let r2 = book.addInstrument("hc2510", to: gid)
        let r3 = book.addInstrument("rb2510", to: gid)
        #expect(r1)
        #expect(r2)
        #expect(!r3)

        #expect(book.group(id: gid)?.instrumentIDs == ["rb2510", "hc2510"])
    }

    @Test("addInstrument 到不存在分组返回 false")
    func addInstrumentMissingGroup() {
        var book = WatchlistBook()
        let miss = book.addInstrument("rb2510", to: UUID())
        #expect(!miss)
    }

    @Test("removeInstrument 命中与不命中")
    func removeInstrument() {
        var book = makeBook(groupNames: ["主力"])
        let gid = book.groups[0].id
        book.addInstrument("rb2510", to: gid)
        book.addInstrument("hc2510", to: gid)

        let hit = book.removeInstrument("rb2510", from: gid)
        #expect(hit)
        #expect(book.group(id: gid)?.instrumentIDs == ["hc2510"])

        let missID = book.removeInstrument("rb2510", from: gid)
        let missGroup = book.removeInstrument("hc2510", from: UUID())
        #expect(!missID)
        #expect(!missGroup)
    }
}

// MARK: - 4. 合约拖拽排序

@Suite("WatchlistBook · 合约拖拽排序")
struct WatchlistMoveInstrumentTests {

    @Test("moveInstrument 同组内移动")
    func moveInstrumentInGroup() {
        var book = makeBook(groupNames: ["主力"])
        let gid = book.groups[0].id
        for s in ["rb2510", "hc2510", "i2509", "j2509"] {
            book.addInstrument(s, to: gid)
        }

        let f = book.moveInstrument(in: gid, from: 0, to: 4)
        #expect(f)
        #expect(book.group(id: gid)?.instrumentIDs == ["hc2510", "i2509", "j2509", "rb2510"])

        let b = book.moveInstrument(in: gid, from: 3, to: 0)
        #expect(b)
        #expect(book.group(id: gid)?.instrumentIDs == ["rb2510", "hc2510", "i2509", "j2509"])
    }

    @Test("moveInstrument 跨分组（目标无重复）")
    func moveInstrumentCrossGroup() {
        var book = makeBook(groupNames: ["主力", "黑色"])
        let g1 = book.groups[0].id
        let g2 = book.groups[1].id
        book.addInstrument("rb2510", to: g1)
        book.addInstrument("hc2510", to: g1)

        let ok = book.moveInstrument("rb2510", from: g1, to: g2)
        #expect(ok)
        #expect(book.group(id: g1)?.instrumentIDs == ["hc2510"])
        #expect(book.group(id: g2)?.instrumentIDs == ["rb2510"])
    }

    @Test("moveInstrument 跨分组（目标已有 → 仅从源移除以保持去重）")
    func moveInstrumentCrossGroupDedup() {
        var book = makeBook(groupNames: ["主力", "黑色"])
        let g1 = book.groups[0].id
        let g2 = book.groups[1].id
        book.addInstrument("rb2510", to: g1)
        book.addInstrument("rb2510", to: g2)

        let ok = book.moveInstrument("rb2510", from: g1, to: g2)
        #expect(ok)
        #expect(book.group(id: g1)?.instrumentIDs == [])
        #expect(book.group(id: g2)?.instrumentIDs == ["rb2510"])
    }

    @Test("moveInstrument 跨分组指定 targetIndex")
    func moveInstrumentCrossGroupAtIndex() {
        var book = makeBook(groupNames: ["主力", "黑色"])
        let g1 = book.groups[0].id
        let g2 = book.groups[1].id
        book.addInstrument("rb2510", to: g1)
        for s in ["i2509", "j2509"] { book.addInstrument(s, to: g2) }

        let ok = book.moveInstrument("rb2510", from: g1, to: g2, targetIndex: 1)
        #expect(ok)
        #expect(book.group(id: g2)?.instrumentIDs == ["i2509", "rb2510", "j2509"])
    }

    @Test("moveInstrument 边界：越界 / 不存在")
    func moveInstrumentEdgeCases() {
        var book = makeBook(groupNames: ["主力"])
        let gid = book.groups[0].id
        book.addInstrument("rb2510", to: gid)

        let same = book.moveInstrument(in: gid, from: 0, to: 0)
        let oob = book.moveInstrument(in: gid, from: 5, to: 0)
        let missGroup = book.moveInstrument(in: UUID(), from: 0, to: 1)
        let missInstr = book.moveInstrument("not-exist", from: gid, to: gid)
        #expect(!same)
        #expect(!oob)
        #expect(!missGroup)
        #expect(!missInstr)
    }
}

// MARK: - 5. 查询

@Suite("WatchlistBook · 查询")
struct WatchlistQueryTests {

    @Test("contains 与 group(id:)")
    func containsAndGroupLookup() {
        var book = makeBook(groupNames: ["主力"])
        let gid = book.groups[0].id
        book.addInstrument("rb2510", to: gid)

        #expect(book.contains("rb2510", in: gid))
        #expect(!book.contains("hc2510", in: gid))
        #expect(!book.contains("rb2510", in: UUID()))
        #expect(book.group(id: gid)?.name == "主力")
        #expect(book.group(id: UUID()) == nil)
    }

    @Test("groups(containing:) 跨分组聚合")
    func groupsContainingInstrument() {
        var book = makeBook(groupNames: ["主力", "黑色", "化工"])
        let g1 = book.groups[0].id
        let g2 = book.groups[1].id
        book.addInstrument("rb2510", to: g1)
        book.addInstrument("rb2510", to: g2)

        let result = book.groups(containing: "rb2510")
        #expect(result.count == 2)
        #expect(result.map(\.name) == ["主力", "黑色"])
    }
}

// MARK: - 6. Codable 往返

@Suite("WatchlistBook · Codable 往返")
struct WatchlistCodableTests {

    @Test("WatchlistBook JSON 编解码")
    func bookCodableRoundTrip() throws {
        var book = makeBook(groupNames: ["主力", "黑色"])
        let g1 = book.groups[0].id
        book.addInstrument("rb2510", to: g1)
        book.addInstrument("hc2510", to: g1)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(book)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchlistBook.self, from: data)

        #expect(decoded.groups.count == 2)
        #expect(decoded.groups[0].instrumentIDs == ["rb2510", "hc2510"])
        #expect(decoded.groups.map(\.sortIndex) == [0, 1])
    }

    @Test("init 时即使乱序传入也按 sortIndex 排序")
    func initSortsByIndex() {
        let now = Date()
        let g1 = Watchlist(name: "B", sortIndex: 1, createdAt: now, updatedAt: now)
        let g2 = Watchlist(name: "A", sortIndex: 0, createdAt: now, updatedAt: now)
        let book = WatchlistBook(groups: [g1, g2])
        #expect(book.groups.map(\.name) == ["A", "B"])
        #expect(book.groups.map(\.sortIndex) == [0, 1])
    }
}

// MARK: - 7. CloudKit 字段映射预埋

@Suite("Watchlist · CloudKit 字段映射")
struct WatchlistCloudKitTests {

    @Test("cloudKitRecordType 与字段名常量")
    func recordTypeAndFieldNames() {
        #expect(Watchlist.cloudKitRecordType == "Watchlist")
        #expect(Watchlist.CloudKitField.name == "name")
        #expect(Watchlist.CloudKitField.sortIndex == "sortIndex")
        #expect(Watchlist.CloudKitField.instrumentIDs == "instrumentIDs")
        #expect(Watchlist.CloudKitField.createdAt == "createdAt")
        #expect(Watchlist.CloudKitField.updatedAt == "updatedAt")
    }

    @Test("cloudKitFields 输出类型符合 CKRecord 规范")
    func cloudKitFieldsTypes() {
        let now = Date()
        let g = Watchlist(name: "主力", sortIndex: 2, instrumentIDs: ["rb2510", "hc2510"], createdAt: now, updatedAt: now)
        let fields = g.cloudKitFields()

        #expect(fields[Watchlist.CloudKitField.name] as? String == "主力")
        #expect(fields[Watchlist.CloudKitField.sortIndex] as? Int64 == 2)
        #expect(fields[Watchlist.CloudKitField.instrumentIDs] as? [String] == ["rb2510", "hc2510"])
        #expect(fields[Watchlist.CloudKitField.createdAt] as? Date == now)
        #expect(fields[Watchlist.CloudKitField.updatedAt] as? Date == now)
    }

    @Test("cloudKitFields → init?(cloudKitRecordName:fields:) 往返")
    func cloudKitRoundTrip() throws {
        let now = Date()
        let original = Watchlist(name: "黑色", sortIndex: 1, instrumentIDs: ["rb2510"], createdAt: now, updatedAt: now)
        let recordName = original.cloudKitRecordName
        let fields = original.cloudKitFields()

        let bridged: [String: Any] = fields.mapValues { $0 as Any }
        let restored = try #require(Watchlist(cloudKitRecordName: recordName, fields: bridged))

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.sortIndex == original.sortIndex)
        #expect(restored.instrumentIDs == original.instrumentIDs)
        #expect(restored.createdAt == original.createdAt)
        #expect(restored.updatedAt == original.updatedAt)
    }

    @Test("init? 兼容 Int 类型 sortIndex（CloudKit Int64 vs 本地 Int 兜底）")
    func cloudKitSortIndexIntFallback() throws {
        let now = Date()
        let id = UUID()
        let fields: [String: Any] = [
            Watchlist.CloudKitField.name: "主力",
            Watchlist.CloudKitField.sortIndex: 5,
            Watchlist.CloudKitField.instrumentIDs: ["rb2510"],
            Watchlist.CloudKitField.createdAt: now,
            Watchlist.CloudKitField.updatedAt: now,
        ]
        let g = try #require(Watchlist(cloudKitRecordName: id.uuidString, fields: fields))
        #expect(g.sortIndex == 5)
    }

    @Test("init? 必填字段缺失返回 nil")
    func cloudKitInitFailsOnMissingRequired() {
        let id = UUID().uuidString
        let now = Date()

        // 缺 name
        #expect(Watchlist(cloudKitRecordName: id, fields: [
            Watchlist.CloudKitField.createdAt: now,
            Watchlist.CloudKitField.updatedAt: now,
        ]) == nil)

        // recordName 非法
        #expect(Watchlist(cloudKitRecordName: "not-a-uuid", fields: [
            Watchlist.CloudKitField.name: "X",
            Watchlist.CloudKitField.createdAt: now,
            Watchlist.CloudKitField.updatedAt: now,
        ]) == nil)
    }

    @Test("init? instrumentIDs 缺失时回退空数组")
    func cloudKitInstrumentIDsFallback() throws {
        let now = Date()
        let id = UUID().uuidString
        let g = try #require(Watchlist(cloudKitRecordName: id, fields: [
            Watchlist.CloudKitField.name: "主力",
            Watchlist.CloudKitField.createdAt: now,
            Watchlist.CloudKitField.updatedAt: now,
        ]))
        #expect(g.instrumentIDs == [])
    }
}
