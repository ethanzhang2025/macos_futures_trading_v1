// v17.42 C1 · WatchlistColumn + WatchlistColumnPreferences 单测

import Testing
import Foundation
@testable import Shared

@Suite("WatchlistColumn · 枚举属性")
struct WatchlistColumnEnumTests {

    @Test("allCases · 3 列（持仓 / 成交量 / 价差%）")
    func allCases() {
        #expect(WatchlistColumn.allCases.count == 3)
        #expect(WatchlistColumn.allCases.contains(.openInterest))
        #expect(WatchlistColumn.allCases.contains(.volume))
        #expect(WatchlistColumn.allCases.contains(.spread))
    }

    @Test("displayName 中文化")
    func displayNames() {
        #expect(WatchlistColumn.openInterest.displayName == "持仓量")
        #expect(WatchlistColumn.volume.displayName == "成交量")
        #expect(WatchlistColumn.spread.displayName == "买卖价差%")
    }

    @Test("rawValue stable（持久化键稳定 · 不允许改动）")
    func rawValuesStable() {
        #expect(WatchlistColumn.openInterest.rawValue == "openInterest")
        #expect(WatchlistColumn.volume.rawValue == "volume")
        #expect(WatchlistColumn.spread.rawValue == "spread")
        #expect(WatchlistColumn(rawValue: "spread") == .spread)
        #expect(WatchlistColumn(rawValue: "unknown") == nil)
    }

    @Test("width · spread 比另两个宽 10px（容纳 %.3f%%）")
    func widths() {
        #expect(WatchlistColumn.openInterest.width == 80)
        #expect(WatchlistColumn.volume.width == 80)
        #expect(WatchlistColumn.spread.width == 90)
    }
}

@Suite("WatchlistColumnPreferences · UserDefaults 持久化")
struct WatchlistColumnPreferencesTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.column.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        return ud
    }

    @Test("load · 空 UserDefaults 返默认 [.openInterest]")
    func loadDefault() {
        let ud = makeDefaults()
        let visible = WatchlistColumnPreferences.load(ud)
        #expect(visible == [.openInterest])
    }

    @Test("save + load round-trip · 完整 3 列")
    func saveLoadRoundTrip() {
        let ud = makeDefaults()
        let full: Set<WatchlistColumn> = [.openInterest, .volume, .spread]
        WatchlistColumnPreferences.save(full, to: ud)
        #expect(WatchlistColumnPreferences.load(ud) == full)
    }

    @Test("save 空集合 · load 返空（覆盖默认值）")
    func saveEmpty() {
        let ud = makeDefaults()
        WatchlistColumnPreferences.save([], to: ud)
        #expect(WatchlistColumnPreferences.load(ud).isEmpty)
    }

    @Test("toggle · 加入未选列 · 移除已选列")
    func toggleAddRemove() {
        let ud = makeDefaults()
        // 初始 [.openInterest] · toggle .volume → 加入
        var result = WatchlistColumnPreferences.toggle(.volume, in: ud)
        #expect(result.contains(.volume))
        #expect(result.contains(.openInterest))
        #expect(result.count == 2)
        // 再 toggle .volume → 移除
        result = WatchlistColumnPreferences.toggle(.volume, in: ud)
        #expect(!result.contains(.volume))
        #expect(result.contains(.openInterest))
    }

    @Test("toggle · 持久化写入立即生效")
    func togglePersisted() {
        let ud = makeDefaults()
        _ = WatchlistColumnPreferences.toggle(.spread, in: ud)
        #expect(WatchlistColumnPreferences.load(ud).contains(.spread))
    }
}
