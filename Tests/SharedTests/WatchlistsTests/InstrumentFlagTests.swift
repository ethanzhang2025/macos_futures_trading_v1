// v17.34 C5 · InstrumentFlag + InstrumentFlagStore 单测

import Testing
import Foundation
@testable import Shared

@Suite("InstrumentFlag · 枚举属性")
struct InstrumentFlagEnumTests {

    @Test(".none 是 emoji 空串 · 其他都有 emoji")
    func emojiPresence() {
        #expect(InstrumentFlag.none.emoji.isEmpty)
        #expect(!InstrumentFlag.watch.emoji.isEmpty)
        #expect(!InstrumentFlag.star.emoji.isEmpty)
        #expect(!InstrumentFlag.strong.emoji.isEmpty)
        #expect(!InstrumentFlag.avoid.emoji.isEmpty)
    }

    @Test("displayName 全 5 类中文化")
    func displayNames() {
        #expect(InstrumentFlag.none.displayName == "无旗标")
        #expect(InstrumentFlag.watch.displayName == "观察")
        #expect(InstrumentFlag.star.displayName == "重点关注")
        #expect(InstrumentFlag.strong.displayName == "强烈看好")
        #expect(InstrumentFlag.avoid.displayName == "回避")
    }

    @Test("sortRank · strong < star < watch < none < avoid")
    func sortOrdering() {
        let flags: [InstrumentFlag] = [.avoid, .none, .strong, .watch, .star]
        let sorted = flags.sorted { $0.sortRank < $1.sortRank }
        #expect(sorted == [.strong, .star, .watch, .none, .avoid])
    }

    @Test("Codable rawValue stable（向后兼容）")
    func rawValuesStable() {
        #expect(InstrumentFlag.star.rawValue == "star")
        #expect(InstrumentFlag.strong.rawValue == "strong")
        #expect(InstrumentFlag(rawValue: "watch") == .watch)
        #expect(InstrumentFlag(rawValue: "unknown") == nil)
    }
}

@Suite("InstrumentFlagStore · UserDefaults 持久化")
struct InstrumentFlagStoreTests {

    /// 测试用独立 suite UserDefaults · 避免污染 .standard
    private func makeStore(_ suiteName: String = "test.flag.\(UUID().uuidString)") -> (InstrumentFlagStore, UserDefaults) {
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return (InstrumentFlagStore(defaults: ud), ud)
    }

    @Test("默认无旗标")
    func defaultsToNone() {
        let (store, _) = makeStore()
        #expect(store.flag(for: "RB0") == .none)
    }

    @Test("setFlag / flag(for:) 往返")
    func roundTrip() {
        let (store, _) = makeStore()
        store.setFlag(.star, for: "RB0")
        store.setFlag(.strong, for: "AU0")
        #expect(store.flag(for: "RB0") == .star)
        #expect(store.flag(for: "AU0") == .strong)
        #expect(store.flag(for: "CU0") == .none)
    }

    @Test("setFlag(.none) 从 store 移除（保持 dict 紧凑）")
    func setNoneRemovesEntry() {
        let (store, ud) = makeStore()
        store.setFlag(.star, for: "RB0")
        store.setFlag(.none, for: "RB0")
        #expect(store.flag(for: "RB0") == .none)
        let dict = ud.dictionary(forKey: InstrumentFlagStore.defaultsKey) as? [String: String]
        #expect(dict?["RB0"] == nil)
    }

    @Test("allFlags 全量快照")
    func allFlagsSnapshot() {
        let (store, _) = makeStore()
        store.setFlag(.star, for: "RB0")
        store.setFlag(.avoid, for: "I0")
        let all = store.allFlags()
        #expect(all["RB0"] == .star)
        #expect(all["I0"] == .avoid)
        #expect(all.count == 2)
    }

    @Test("clearAll 抹掉全部旗标")
    func clearAll() {
        let (store, _) = makeStore()
        store.setFlag(.star, for: "RB0")
        store.setFlag(.strong, for: "AU0")
        store.clearAll()
        #expect(store.allFlags().isEmpty)
    }

    @Test("跨 store 实例 · 同 UserDefaults 共享数据")
    func sharedAcrossInstances() {
        let suite = "test.shared.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        let writer = InstrumentFlagStore(defaults: ud)
        writer.setFlag(.star, for: "RB0")
        let reader = InstrumentFlagStore(defaults: ud)
        #expect(reader.flag(for: "RB0") == .star)
    }
}
