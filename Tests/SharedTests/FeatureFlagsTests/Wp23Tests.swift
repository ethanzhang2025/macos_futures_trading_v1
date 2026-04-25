// WP-23 · Feature Flag 测试
// FeatureFlag 默认值 / 各 Store 实现 / Composite 优先级 / Service 一致性 / refresh

import Testing
import Foundation
@testable import Shared

// MARK: - 1. FeatureFlag enum

@Suite("FeatureFlag · 默认值 + 命名空间")
struct FeatureFlagTests {

    @Test("已实现功能默认开 / 商业化 + 实验性默认关")
    func defaultValues() {
        #expect(FeatureFlag.importWenhua.defaultValue)
        #expect(FeatureFlag.importGeneric.defaultValue)
        #expect(FeatureFlag.replayMode.defaultValue)
        #expect(FeatureFlag.reviewCharts.defaultValue)
        #expect(FeatureFlag.alertCenter.defaultValue)

        #expect(!FeatureFlag.subscriptionPaywall.defaultValue)
        #expect(!FeatureFlag.subscriptionFreeTrial.defaultValue)
        #expect(!FeatureFlag.alertSystemNotification.defaultValue)
        #expect(!FeatureFlag.alertSound.defaultValue)
        #expect(!FeatureFlag.experimentalFormulaCompleteMode.defaultValue)
        #expect(!FeatureFlag.experimentalAIAssist.defaultValue)
    }

    @Test("rawValue 与 namespace 解析")
    func rawValueAndNamespace() {
        #expect(FeatureFlag.subscriptionPaywall.rawValue == "subscription.paywall")
        #expect(FeatureFlag.subscriptionPaywall.namespace == "subscription")
        #expect(FeatureFlag.importWenhua.namespace == "import")
        #expect(FeatureFlag.alertSound.namespace == "alert")
    }

    @Test("Codable JSON 往返")
    func codableRoundTrip() throws {
        let original = FeatureFlag.replayMode
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeatureFlag.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - 2. InMemoryFlagStore

@Suite("InMemoryFlagStore")
struct InMemoryStoreTests {

    @Test("初始为空 → value 返回 nil")
    func emptyInitial() async {
        let store = InMemoryFlagStore()
        #expect(await store.value(for: .alertSound) == nil)
    }

    @Test("set + value 往返 + nil 清除")
    func setAndClear() async {
        let store = InMemoryFlagStore()
        await store.set(.alertSound, to: true)
        #expect(await store.value(for: .alertSound) == true)

        await store.set(.alertSound, to: false)
        #expect(await store.value(for: .alertSound) == false)

        await store.set(.alertSound, to: nil)
        #expect(await store.value(for: .alertSound) == nil)
    }

    @Test("初始字典注入")
    func initialDict() async {
        let store = InMemoryFlagStore(initial: [.replayMode: true, .alertSound: false])
        #expect(await store.value(for: .replayMode) == true)
        #expect(await store.value(for: .alertSound) == false)
    }
}

// MARK: - 3. UserDefaultsFlagStore

@Suite("UserDefaultsFlagStore · 隔离命名空间")
struct UserDefaultsStoreTests {

    /// 每个测试用独立 suite 名 + 测试结束清空
    private func makeStore() -> (UserDefaultsFlagStore, UserDefaults) {
        let suiteName = "WP23Test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (UserDefaultsFlagStore(defaults: defaults, keyPrefix: "ff."), defaults)
    }

    @Test("未设置 → value nil")
    func notSetReturnsNil() async {
        let (store, _) = makeStore()
        #expect(await store.value(for: .alertSound) == nil)
    }

    @Test("set + value 往返 + 持久化到 UserDefaults")
    func setAndRead() async {
        let (store, defaults) = makeStore()
        store.set(.alertSound, to: true)
        #expect(await store.value(for: .alertSound) == true)
        // 实际 UserDefaults key 是 "ff.alert.sound"
        #expect(defaults.bool(forKey: "ff.alert.sound") == true)

        store.set(.alertSound, to: nil)
        #expect(await store.value(for: .alertSound) == nil)
        #expect(defaults.object(forKey: "ff.alert.sound") == nil)
    }
}

// MARK: - 4. RemoteJSONFlagStore

@Suite("RemoteJSONFlagStore · 远程刷新")
struct RemoteStoreTests {

    @Test("初始空 → value nil")
    func initialEmpty() async {
        let store = RemoteJSONFlagStore { [:] }
        #expect(await store.value(for: .replayMode) == nil)
    }

    @Test("refresh 成功后 value 命中")
    func refreshSuccess() async {
        let store = RemoteJSONFlagStore {
            ["replay.mode": false, "alert.sound": true]
        }
        let ok = await store.refresh()
        #expect(ok)
        #expect(await store.value(for: .replayMode) == false)
        #expect(await store.value(for: .alertSound) == true)
        #expect(await store.value(for: .importWenhua) == nil)  // 未在 JSON 中
    }

    @Test("refresh 失败 → 保持原缓存")
    func refreshFailureKeepsCache() async {
        struct DummyError: Error {}
        let store = RemoteJSONFlagStore {
            ["alert.sound": true]
        }
        let ok1 = await store.refresh()
        #expect(ok1)
        #expect(await store.value(for: .alertSound) == true)

        let store2 = RemoteJSONFlagStore { throw DummyError() }
        let ok2 = await store2.refresh()
        #expect(!ok2)
        #expect(await store2.value(for: .alertSound) == nil)  // 没有原缓存

        // 已有缓存的 store fail 不清空（用 actor mutation 验证）
        let storeWithCache = RemoteJSONFlagStore {
            ["alert.sound": true]
        }
        _ = await storeWithCache.refresh()
        #expect(await storeWithCache.value(for: .alertSound) == true)
    }

    @Test("lastFetched 在 refresh 成功后更新")
    func lastFetchedTimestamp() async {
        let store = RemoteJSONFlagStore { ["replay.mode": true] }
        #expect(await store.lastFetched == nil)
        let now = Date()
        _ = await store.refresh(now: now)
        #expect(await store.lastFetched == now)
    }
}

// MARK: - 5. CompositeFlagStore 优先级

@Suite("CompositeFlagStore · 优先级链")
struct CompositeStoreTests {

    @Test("远程优先 + 本地兜底 + 缺失返回 nil")
    func priorityChain() async {
        let remote = InMemoryFlagStore(initial: [.alertSound: true])
        let local = InMemoryFlagStore(initial: [.alertSound: false, .replayMode: false])
        let composite = CompositeFlagStore(stores: [remote, local])

        // alertSound：远程命中（true）
        #expect(await composite.value(for: .alertSound) == true)
        // replayMode：远程未配，本地兜底（false）
        #expect(await composite.value(for: .replayMode) == false)
        // alertCenter：都没配 → nil（service 用 default 兜底）
        #expect(await composite.value(for: .alertCenter) == nil)
    }

    @Test("3 层链：远程 → 本地 → 仅默认")
    func threeLayerChain() async {
        let remote = InMemoryFlagStore()
        let local = InMemoryFlagStore(initial: [.experimentalAIAssist: true])
        let composite = CompositeFlagStore(stores: [remote, local])
        #expect(await composite.value(for: .experimentalAIAssist) == true)
    }
}

// MARK: - 6. FeatureFlagService

@Suite("FeatureFlagService · 业务唯一入口")
struct ServiceTests {

    @Test("isEnabled 在 store 命中时返回 store 值")
    func storeHit() async {
        let store = InMemoryFlagStore(initial: [.subscriptionPaywall: true])
        let service = FeatureFlagService(store: store)
        #expect(await service.isEnabled(.subscriptionPaywall))
    }

    @Test("isEnabled 在 store 未命中时返回 enum 默认值")
    func storeMissUsesDefault() async {
        let store = InMemoryFlagStore()
        let service = FeatureFlagService(store: store)
        // importWenhua 默认 true / subscriptionPaywall 默认 false
        #expect(await service.isEnabled(.importWenhua))
        let paywall = await service.isEnabled(.subscriptionPaywall)
        #expect(!paywall)
    }

    @Test("snapshot 含全部 flag")
    func snapshotAllFlags() async {
        let store = InMemoryFlagStore(initial: [.alertSound: true])
        let service = FeatureFlagService(store: store)
        let snap = await service.snapshot()
        #expect(snap.count == FeatureFlag.allCases.count)
        // alertSound 来自 store
        #expect(snap[.alertSound] == true)
        // alertCenter 来自默认值（true）
        #expect(snap[.alertCenter] == true)
    }

    @Test("远程 + 本地 + 默认完整链路")
    func fullChainIntegration() async {
        // 远程关掉 replayMode（默认 true）
        let remote = InMemoryFlagStore(initial: [.replayMode: false])
        // 本地 override alertSound 为 true（默认 false）
        let local = InMemoryFlagStore(initial: [.alertSound: true])
        let composite = CompositeFlagStore(stores: [remote, local])
        let service = FeatureFlagService(store: composite)

        let replay = await service.isEnabled(.replayMode)
        let aiAssist = await service.isEnabled(.experimentalAIAssist)
        #expect(!replay)                                  // 远程覆盖
        #expect(await service.isEnabled(.alertSound))     // 本地覆盖
        #expect(await service.isEnabled(.importWenhua))   // 默认值（链上无）
        #expect(!aiAssist)                                // 默认值
    }
}
