// v15.20 batch61 · WatchlistBook.allInstrumentIDsDeduped 单测

import Testing
@testable import Shared

@Suite("WatchlistBook · 跨分组合约去重聚合")
struct AllInstrumentIDsDedupedTests {

    @Test("空 book → 空数组")
    func empty() {
        let book = WatchlistBook()
        #expect(book.allInstrumentIDsDeduped == [])
    }

    @Test("单分组 → 原序保留")
    func singleGroup() {
        var book = WatchlistBook()
        let g = book.addGroup(name: "贵金属")
        _ = book.addInstrument("AU0", to: g.id)
        _ = book.addInstrument("AG0", to: g.id)
        #expect(book.allInstrumentIDsDeduped == ["AU0", "AG0"])
    }

    @Test("多分组无重复 → 顺序按分组顺序拼接")
    func multipleGroupsDistinct() {
        var book = WatchlistBook()
        let g1 = book.addGroup(name: "贵金属")
        let g2 = book.addGroup(name: "黑色")
        _ = book.addInstrument("AU0", to: g1.id)
        _ = book.addInstrument("AG0", to: g1.id)
        _ = book.addInstrument("RB0", to: g2.id)
        _ = book.addInstrument("HC0", to: g2.id)
        #expect(book.allInstrumentIDsDeduped == ["AU0", "AG0", "RB0", "HC0"])
    }

    @Test("跨分组重复 → 仅保留首次出现")
    func crossGroupDedup() {
        var book = WatchlistBook()
        let g1 = book.addGroup(name: "主力")
        let g2 = book.addGroup(name: "活跃")
        _ = book.addInstrument("RB0", to: g1.id)
        _ = book.addInstrument("IF0", to: g1.id)
        _ = book.addInstrument("RB0", to: g2.id)        // 重复 · 跳过
        _ = book.addInstrument("AU0", to: g2.id)
        _ = book.addInstrument("IF0", to: g2.id)        // 重复 · 跳过
        #expect(book.allInstrumentIDsDeduped == ["RB0", "IF0", "AU0"])
    }

    @Test("空分组不影响（连续空 + 非空交错）")
    func emptyGroupsInterleaved() {
        var book = WatchlistBook()
        _ = book.addGroup(name: "空1")
        let g2 = book.addGroup(name: "有内容")
        _ = book.addGroup(name: "空2")
        _ = book.addInstrument("RB0", to: g2.id)
        #expect(book.allInstrumentIDsDeduped == ["RB0"])
    }
}
