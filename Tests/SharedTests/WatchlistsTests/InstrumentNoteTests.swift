// v17.129 · InstrumentNoteStore 单测

import Testing
import Foundation
@testable import Shared

@Suite("InstrumentNoteStore · UserDefaults 持久化")
struct InstrumentNoteStoreTests {

    /// 测试用独立 suite UserDefaults · 避免污染 .standard
    private func makeStore(_ suiteName: String = "test.note.\(UUID().uuidString)") -> (InstrumentNoteStore, UserDefaults) {
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return (InstrumentNoteStore(defaults: ud), ud)
    }

    @Test("默认无备注 → nil")
    func defaultsToNil() {
        let (store, _) = makeStore()
        #expect(store.note(for: "RB0") == nil)
        #expect(!store.hasNote(for: "RB0"))
    }

    @Test("setNote / note(for:) 往返")
    func setAndGet() {
        let (store, _) = makeStore()
        store.setNote("等回 3540 入场", for: "RB0")
        #expect(store.note(for: "RB0") == "等回 3540 入场")
        #expect(store.hasNote(for: "RB0"))
    }

    @Test("空字符串 / 全空白 → 移除")
    func emptyOrWhitespaceRemoves() {
        let (store, _) = makeStore()
        store.setNote("test", for: "RB0")
        #expect(store.hasNote(for: "RB0"))
        store.setNote("", for: "RB0")
        #expect(store.note(for: "RB0") == nil)
        store.setNote("non-empty", for: "AU0")
        store.setNote("   \t\n  ", for: "AU0")  // 全空白
        #expect(store.note(for: "AU0") == nil)
    }

    @Test("nil → 移除")
    func nilRemoves() {
        let (store, _) = makeStore()
        store.setNote("test", for: "RB0")
        store.setNote(nil, for: "RB0")
        #expect(store.note(for: "RB0") == nil)
    }

    @Test("trim 周围空白")
    func trimsWhitespace() {
        let (store, _) = makeStore()
        store.setNote("  RB0 主力支撑 3540  \n", for: "RB0")
        #expect(store.note(for: "RB0") == "RB0 主力支撑 3540")
    }

    @Test("多 instrument 独立")
    func multipleInstruments() {
        let (store, _) = makeStore()
        store.setNote("note A", for: "RB0")
        store.setNote("note B", for: "AU0")
        #expect(store.note(for: "RB0") == "note A")
        #expect(store.note(for: "AU0") == "note B")
        #expect(store.note(for: "IF0") == nil)
    }

    @Test("allNotes 全量快照")
    func allNotes() {
        let (store, _) = makeStore()
        store.setNote("A", for: "RB0")
        store.setNote("B", for: "AU0")
        let all = store.allNotes()
        #expect(all.count == 2)
        #expect(all["RB0"] == "A")
        #expect(all["AU0"] == "B")
    }

    @Test("clearAll 清空")
    func clearAll() {
        let (store, _) = makeStore()
        store.setNote("A", for: "RB0")
        store.setNote("B", for: "AU0")
        store.clearAll()
        #expect(store.allNotes().isEmpty)
        #expect(store.note(for: "RB0") == nil)
    }

    @Test("跨 Store 实例共享同 UserDefaults")
    func sharedDefaults() {
        let suiteName = "test.note.shared.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        let a = InstrumentNoteStore(defaults: ud)
        let b = InstrumentNoteStore(defaults: ud)
        a.setNote("from A", for: "RB0")
        #expect(b.note(for: "RB0") == "from A")  // 另一实例可读
    }
}
