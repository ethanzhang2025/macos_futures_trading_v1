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

    // MARK: - v17.152 · 全工程批量管理（rename / merge / delete）

    @Test("v17.152 · renameTagGlobally · 多 instrument 上的标签全部重命名")
    func renameGlobally() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内"], for: "RB0")
        store.setTags(["主力", "波段"], for: "AU0")
        store.setTags(["对冲腿"],     for: "I0")   // 不含 oldTag
        let affected = store.renameTagGlobally(oldTag: "主力", newTag: "主力合约")
        #expect(affected == 2)
        #expect(store.tags(for: "RB0") == ["主力合约", "日内"])   // 顺序保留
        #expect(store.tags(for: "AU0") == ["主力合约", "波段"])
        #expect(store.tags(for: "I0") == ["对冲腿"])              // 未影响
    }

    @Test("v17.152 · renameTagGlobally · merge 语义（newTag 已存在 · 去重保留 newTag）")
    func renameMergesIntoExistingTag() {
        let (store, _) = makeStore()
        store.setTags(["波段", "长线"], for: "RB0")   // 同时含 oldTag(波段) 和 newTag(长线)
        let affected = store.renameTagGlobally(oldTag: "波段", newTag: "长线")
        #expect(affected == 1)
        #expect(store.tags(for: "RB0") == ["长线"])   // 去重 · 保留 newTag
    }

    @Test("v17.152 · renameTagGlobally · oldTag 不存在 → 0 affected · 数据不变")
    func renameUnknownTagReturnsZero() {
        let (store, _) = makeStore()
        store.setTags(["主力"], for: "RB0")
        let affected = store.renameTagGlobally(oldTag: "不存在", newTag: "新名")
        #expect(affected == 0)
        #expect(store.tags(for: "RB0") == ["主力"])
    }

    @Test("v17.152 · renameTagGlobally · oldTag == newTag 或空 · 0 affected 拒绝")
    func renameRejectsEmptyOrSame() {
        let (store, _) = makeStore()
        store.setTags(["主力"], for: "RB0")
        #expect(store.renameTagGlobally(oldTag: "", newTag: "新") == 0)
        #expect(store.renameTagGlobally(oldTag: "主力", newTag: "") == 0)
        #expect(store.renameTagGlobally(oldTag: "主力", newTag: "主力") == 0)
    }

    @Test("v17.152 · deleteTagGlobally · 多 instrument 上的标签全部移除 · 空 entry 紧凑")
    func deleteGlobally() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内"], for: "RB0")
        store.setTags(["主力"],         for: "AU0")   // 仅一个标签
        store.setTags(["对冲腿"],       for: "I0")
        let affected = store.deleteTagGlobally("主力")
        #expect(affected == 2)
        #expect(store.tags(for: "RB0") == ["日内"])
        #expect(store.tags(for: "AU0").isEmpty)        // 仅一个标签 → 空数组 · entry 移除
        #expect(store.tags(for: "I0") == ["对冲腿"])
        // 全局快照不再含 "主力"
        #expect(!store.allTagsAcrossInstruments().contains("主力"))
    }

    @Test("v17.152 · deleteTagGlobally · 不存在标签 → 0 affected")
    func deleteUnknownReturnsZero() {
        let (store, _) = makeStore()
        store.setTags(["主力"], for: "RB0")
        #expect(store.deleteTagGlobally("不存在") == 0)
        #expect(store.tags(for: "RB0") == ["主力"])
    }

    @Test("v17.152 · instrumentCountFor · rename/delete 前预览影响数")
    func instrumentCountPreview() {
        let (store, _) = makeStore()
        store.setTags(["主力", "日内"], for: "RB0")
        store.setTags(["主力"],         for: "AU0")
        store.setTags(["波段"],         for: "I0")
        #expect(store.instrumentCountFor(tag: "主力") == 2)
        #expect(store.instrumentCountFor(tag: "波段") == 1)
        #expect(store.instrumentCountFor(tag: "日内") == 1)
        #expect(store.instrumentCountFor(tag: "不存在") == 0)
        #expect(store.instrumentCountFor(tag: "") == 0)
    }
}
