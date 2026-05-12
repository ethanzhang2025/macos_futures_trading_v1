// v17.132 · InstrumentTagStore 单测

import Testing
import Foundation
@testable import Shared

@Suite("InstrumentTagStore · UserDefaults 持久化")
struct InstrumentTagStoreTests {

    private func makeStore(_ suiteName: String = "test.tag.\(UUID().uuidString)") -> (InstrumentTagStore, UserDefaults) {
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return (InstrumentTagStore(defaults: ud), ud)
    }

    @Test("默认无标签 → 空数组")
    func defaultsToEmpty() {
        let (store, _) = makeStore()
        #expect(store.tags(for: "RB0").isEmpty)
        #expect(!store.hasTags(for: "RB0"))
        #expect(!store.hasTag("主力", for: "RB0"))
    }

    @Test("setTags / tags(for:) 往返 · 空数组移除")
    func setAndGet() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内"], for: "RB0")
        #expect(store.tags(for: "RB0") == ["主力", "日内"])
        #expect(store.hasTags(for: "RB0"))
        store.setTags([], for: "RB0")
        #expect(store.tags(for: "RB0").isEmpty)
        #expect(store.allInstrumentTags()["RB0"] == nil)  // 紧凑存储 · 完全移除
    }

    @Test("addTag 去重 + 返回是否新增")
    func addTagDedupes() {
        let (store, _) = makeStore()
        #expect(store.addTag("主力", to: "RB0") == true)
        #expect(store.addTag("主力", to: "RB0") == false)  // 重复
        #expect(store.addTag("日内", to: "RB0") == true)
        #expect(store.tags(for: "RB0") == ["主力", "日内"])
        #expect(store.addTag("   ", to: "RB0") == false)  // 空白
        #expect(store.addTag("", to: "RB0") == false)
    }

    @Test("removeTag · 返回是否实际移除")
    func removeTag() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内", "波段"], for: "RB0")
        #expect(store.removeTag("日内", from: "RB0") == true)
        #expect(store.tags(for: "RB0") == ["主力", "波段"])
        #expect(store.removeTag("不存在", from: "RB0") == false)
        #expect(store.removeTag("  主力  ", from: "RB0") == true)  // trim 后匹配
        #expect(store.tags(for: "RB0") == ["波段"])
    }

    @Test("setTags trim + 截断 + 去重")
    func sanitize() {
        let (store, _) = makeStore()
        // 含空白 · 重复 · 超长
        let longTag = String(repeating: "长", count: 30)
        store.setTags(["  主力  ", "主力", "", "   ", "日内", longTag], for: "RB0")
        let stored = store.tags(for: "RB0")
        #expect(stored.count == 3)  // 主力 · 日内 · 截断后的长标签
        #expect(stored[0] == "主力")
        #expect(stored[1] == "日内")
        #expect(stored[2].count == InstrumentTagStore.maxTagLength)  // 截到 20
    }

    @Test("多 instrument 独立")
    func multipleInstruments() {
        let (store, _) = makeStore()
        store.setTags(["主力", "黑色"], for: "RB0")
        store.setTags(["套利腿"], for: "AU0")
        #expect(store.tags(for: "RB0") == ["主力", "黑色"])
        #expect(store.tags(for: "AU0") == ["套利腿"])
        #expect(store.tags(for: "IF0").isEmpty)
    }

    @Test("allTagsAcrossInstruments 去重 + 排序")
    func allTagsAggregation() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内"], for: "RB0")
        store.setTags(["主力", "波段"], for: "AU0")
        store.setTags(["套利腿"], for: "IF0")
        let all = store.allTagsAcrossInstruments()
        #expect(all == ["主力", "套利腿", "日内", "波段"])  // 去重 + 排序
    }

    @Test("单合约标签数上限保护")
    func maxTagsCap() {
        let (store, _) = makeStore()
        // addTag 上限
        for i in 0..<InstrumentTagStore.maxTagsPerInstrument {
            #expect(store.addTag("tag\(i)", to: "RB0") == true)
        }
        #expect(store.addTag("tagOverflow", to: "RB0") == false)
        #expect(store.tags(for: "RB0").count == InstrumentTagStore.maxTagsPerInstrument)
        // setTags 截断
        let manyTags = (0..<20).map { "T\($0)" }
        store.setTags(manyTags, for: "AU0")
        #expect(store.tags(for: "AU0").count == InstrumentTagStore.maxTagsPerInstrument)
    }

    @Test("clearAll + 跨 Store 实例共享")
    func clearAllAndSharing() {
        let suiteName = "test.tag.shared.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let a = InstrumentTagStore(defaults: ud)
        let b = InstrumentTagStore(defaults: ud)
        a.setTags(["主力"], for: "RB0")
        #expect(b.tags(for: "RB0") == ["主力"])  // 另一实例可读
        a.clearAll()
        #expect(b.tags(for: "RB0").isEmpty)
        #expect(b.allInstrumentTags().isEmpty)
    }
}
