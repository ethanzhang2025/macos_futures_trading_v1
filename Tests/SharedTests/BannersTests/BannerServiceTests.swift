// WP-120 · Banner 服务测试（v15.18）

import Testing
import Foundation
@testable import Shared

@Suite("BannerService · 拉取 + dismiss + 过期")
struct BannerServiceTests {

    private func makeBanner(_ id: String, createdMsAgo: Int64 = 0, expiredAtMs: Int64? = nil, level: BannerLevel = .info) -> Banner {
        let now: Int64 = 1_700_000_000_000
        return Banner(
            id: id, title: "T-\(id)", body: "B-\(id)", level: level,
            createdAtMs: now - createdMsAgo,
            expiredAtMs: expiredAtMs
        )
    }

    @Test("refresh · 拉取 source 列表 · 全部未 dismissed → 全部展示（按 createdAt 倒序）")
    func refreshReturnsAll() async {
        let store = InMemoryBannerDismissalStore()
        let source = StubBannerSource(fixed: [
            makeBanner("a", createdMsAgo: 5000),
            makeBanner("b", createdMsAgo: 1000)
        ])
        let service = BannerService(store: store, source: source)
        let active = await service.refresh()
        #expect(active.count == 2)
        #expect(active[0].id == "b")    // 最新在前
        #expect(active[1].id == "a")
    }

    @Test("dismiss · 后续 active 不含 dismissed id")
    func dismissExcludes() async {
        let store = InMemoryBannerDismissalStore()
        let source = StubBannerSource(fixed: [makeBanner("x"), makeBanner("y")])
        let service = BannerService(store: store, source: source)
        _ = await service.refresh()
        await service.dismiss("x")
        let active = await service.active()
        #expect(active.count == 1)
        #expect(active[0].id == "y")
        #expect(await service.dismissedCount() == 1)
    }

    @Test("过期 banner · refresh 自动隐藏")
    func expiredBannersHidden() async {
        let store = InMemoryBannerDismissalStore()
        let nowDate = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs: Int64 = 1_700_000_000_000
        let source = StubBannerSource(fixed: [
            makeBanner("active", expiredAtMs: nowMs + 1000),     // 1s 后过期 → active
            makeBanner("expired", expiredAtMs: nowMs - 1000)     // 1s 前过期 → 隐藏
        ])
        let service = BannerService(store: store, source: source, now: { nowDate })
        let active = await service.refresh()
        #expect(active.count == 1)
        #expect(active[0].id == "active")
    }

    @Test("source fetch 失败 · 静默 fallback 上次 active（不阻塞 UI）")
    func sourceFailureKeepsCache() async throws {
        let store = InMemoryBannerDismissalStore()

        // 自定义 source · 第一次成功 · 第二次抛错
        actor FlakySource: BannerSource {
            private var calls = 0
            private let firstBatch: [Banner]
            init(firstBatch: [Banner]) { self.firstBatch = firstBatch }
            func fetchLatest() async throws -> [Banner] {
                calls += 1
                if calls == 1 { return firstBatch }
                throw NSError(domain: "test", code: 0)
            }
        }
        let source = FlakySource(firstBatch: [makeBanner("a")])
        let service = BannerService(store: store, source: source)
        let first = await service.refresh()
        #expect(first.count == 1)
        let second = await service.refresh()      // 抛错 · fallback 上次
        #expect(second.count == 1)
        #expect(second[0].id == "a")
    }

    @Test("Banner.isExpired · 边界精确 · nowMs >= expiredAtMs 判过期")
    func expiredBoundary() {
        let b = Banner(id: "x", title: "t", body: "b", level: .info, createdAtMs: 0, expiredAtMs: 1000)
        #expect(b.isExpired(nowMs: 999) == false)
        #expect(b.isExpired(nowMs: 1000) == true)
        #expect(b.isExpired(nowMs: 1001) == true)
    }

    @Test("BannerLevel 3 类 raw value 稳定（防 typo · 后端 JSON 依赖）")
    func levelRawValuesStable() {
        #expect(BannerLevel.info.rawValue == "info")
        #expect(BannerLevel.warning.rawValue == "warning")
        #expect(BannerLevel.critical.rawValue == "critical")
        #expect(BannerLevel.allCases.count == 3)
    }

    @Test("emitLocal · 客户端主动 push banner · 立即在 active 出现")
    func emitLocalAddsBanner() async {
        let store = InMemoryBannerDismissalStore()
        let source = StubBannerSource()
        let service = BannerService(store: store, source: source)
        _ = await service.refresh()    // empty
        await service.emitLocal(makeBanner("alert-1", level: .warning))
        let active = await service.active()
        #expect(active.count == 1)
        #expect(active[0].id == "alert-1")
    }

    @Test("emitLocal · 同 id 已存在则替换（防重复 emit）")
    func emitLocalReplacesById() async {
        let store = InMemoryBannerDismissalStore()
        let source = StubBannerSource()
        let service = BannerService(store: store, source: source)
        await service.emitLocal(makeBanner("x"))
        await service.emitLocal(Banner(
            id: "x", title: "新标题", body: "新内容", level: .critical,
            createdAtMs: 1_700_000_000_000
        ))
        let active = await service.active()
        #expect(active.count == 1)
        #expect(active[0].title == "新标题")
        #expect(active[0].level == .critical)
    }

    @Test("emitLocal · dismissed 后不再出现（dismiss 持久化优先）")
    func emitLocalRespectsDismissed() async {
        let store = InMemoryBannerDismissalStore()
        await store.markDismissed("x")
        let source = StubBannerSource()
        let service = BannerService(store: store, source: source)
        await service.emitLocal(makeBanner("x"))
        let active = await service.active()
        #expect(active.isEmpty)
    }

    @Test("active 排序 · critical > warning > info（同级按 createdAt 倒序）· v15.18")
    func severityRanksOrder() async {
        let store = InMemoryBannerDismissalStore()
        let nowMs: Int64 = 1_700_000_000_000
        let source = StubBannerSource(fixed: [
            Banner(id: "info-old",  title: "i", body: "", level: .info,     createdAtMs: nowMs - 1000),
            Banner(id: "warn-new",  title: "w", body: "", level: .warning,  createdAtMs: nowMs),
            Banner(id: "crit-old",  title: "c", body: "", level: .critical, createdAtMs: nowMs - 5000),
            Banner(id: "info-new",  title: "i", body: "", level: .info,     createdAtMs: nowMs)
        ])
        let service = BannerService(store: store, source: source)
        let active = await service.refresh()
        #expect(active[0].id == "crit-old")    // critical 最高优先
        #expect(active[1].id == "warn-new")    // warning 次之
        #expect(active[2].id == "info-new")    // info 同级 · 新在前
        #expect(active[3].id == "info-old")
    }
}

@Suite("BannerDismissalStore · 持久化")
struct BannerDismissalStoreTests {

    @Test("InMemory · markDismissed → isDismissed → allDismissed")
    func inMemoryRoundtrip() async {
        let store = InMemoryBannerDismissalStore()
        await store.markDismissed("a")
        await store.markDismissed("b")
        #expect(await store.isDismissed("a"))
        #expect(await store.isDismissed("c") == false)
        #expect(await store.allDismissed() == Set(["a", "b"]))
    }

    @Test("InMemory · retain · 仅保留传入 id")
    func inMemoryRetain() async {
        let store = InMemoryBannerDismissalStore()
        for id in ["a", "b", "c"] { await store.markDismissed(id) }
        await store.retain(only: Set(["b"]))
        #expect(await store.allDismissed() == Set(["b"]))
    }

    // 注：UserDefaults 跨实例持久测试需 macOS 集成测试（UserDefaults 不是 Sendable · 单测 Sendable 检查阻塞）
    // InMemory 已覆盖核心 retain / markDismissed 行为 · UserDefaults 实现仅是序列化层不同
}
