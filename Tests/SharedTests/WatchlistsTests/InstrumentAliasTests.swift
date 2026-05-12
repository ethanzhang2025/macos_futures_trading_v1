// v17.134 · InstrumentAliasStore 单测

import Testing
import Foundation
@testable import Shared

@Suite("InstrumentAliasStore · UserDefaults 持久化")
struct InstrumentAliasStoreTests {

    private func makeStore(_ suiteName: String = "test.alias.\(UUID().uuidString)") -> (InstrumentAliasStore, UserDefaults) {
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return (InstrumentAliasStore(defaults: ud), ud)
    }

    @Test("默认无别名 → nil")
    func defaultsToNil() {
        let (store, _) = makeStore()
        #expect(store.alias(for: "RB0") == nil)
        #expect(!store.hasAlias(for: "RB0"))
    }

    @Test("setAlias / alias(for:) 往返")
    func setAndGet() {
        let (store, _) = makeStore()
        store.setAlias("豆粕 0509", for: "m2509")
        #expect(store.alias(for: "m2509") == "豆粕 0509")
        #expect(store.hasAlias(for: "m2509"))
    }

    @Test("空字符串 / 全空白 / nil → 移除")
    func emptyOrNilRemoves() {
        let (store, _) = makeStore()
        store.setAlias("螺纹主力", for: "RB0")
        store.setAlias("", for: "RB0")
        #expect(store.alias(for: "RB0") == nil)
        store.setAlias("test", for: "AU0")
        store.setAlias("   \t\n  ", for: "AU0")
        #expect(store.alias(for: "AU0") == nil)
        store.setAlias("test", for: "IF0")
        store.setAlias(nil, for: "IF0")
        #expect(store.alias(for: "IF0") == nil)
    }

    @Test("trim 周围空白")
    func trimsWhitespace() {
        let (store, _) = makeStore()
        store.setAlias("  豆粕主力  \n", for: "m2509")
        #expect(store.alias(for: "m2509") == "豆粕主力")
    }

    @Test("超长截断到 maxAliasLength")
    func clipsLongAlias() {
        let (store, _) = makeStore()
        let long = String(repeating: "长", count: 30)
        store.setAlias(long, for: "RB0")
        #expect(store.alias(for: "RB0")?.count == InstrumentAliasStore.maxAliasLength)
    }

    @Test("displayName · 有别名 'alias (id)' · 无别名 id")
    func displayNameFormatting() {
        let (store, _) = makeStore()
        #expect(store.displayName(for: "RB0") == "RB0")
        store.setAlias("螺纹主力", for: "RB0")
        #expect(store.displayName(for: "RB0") == "螺纹主力 (RB0)")
    }

    @Test("多 instrument 独立")
    func multipleInstruments() {
        let (store, _) = makeStore()
        store.setAlias("螺纹主力", for: "RB0")
        store.setAlias("黄金主力", for: "AU0")
        #expect(store.alias(for: "RB0") == "螺纹主力")
        #expect(store.alias(for: "AU0") == "黄金主力")
        #expect(store.alias(for: "IF0") == nil)
    }

    @Test("allAliases + clearAll")
    func snapshotAndClear() {
        let (store, _) = makeStore()
        store.setAlias("A", for: "RB0")
        store.setAlias("B", for: "AU0")
        #expect(store.allAliases().count == 2)
        store.clearAll()
        #expect(store.allAliases().isEmpty)
        #expect(store.alias(for: "RB0") == nil)
    }

    @Test("跨 Store 实例共享同 UserDefaults")
    func sharedDefaults() {
        let suiteName = "test.alias.shared.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let a = InstrumentAliasStore(defaults: ud)
        let b = InstrumentAliasStore(defaults: ud)
        a.setAlias("from A", for: "RB0")
        #expect(b.alias(for: "RB0") == "from A")
    }
}
