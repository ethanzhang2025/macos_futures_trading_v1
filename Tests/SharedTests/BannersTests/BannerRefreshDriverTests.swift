// WP-120 · BannerRefreshDriver 测试（v15.18）

import Testing
import Foundation
@testable import Shared

@Suite("BannerRefreshDriver · 周期刷新")
struct BannerRefreshDriverTests {

    @Test("start · 立即拉一次 + 后续 sleep")
    func startTriggersImmediateRefresh() async {
        let store = InMemoryBannerDismissalStore()
        let nowMs: Int64 = 1_700_000_000_000
        let source = StubBannerSource(fixed: [
            Banner(id: "a", title: "T", body: "B", level: .info, createdAtMs: nowMs)
        ])
        let service = BannerService(store: store, source: source)

        // 用极短 sleep 避免测试卡顿（1ms · 实际生产 5min）
        let driver = BannerRefreshDriver(
            service: service,
            pollIntervalSec: 1,
            sleep: { _ in /* 模拟 sleep · 实际不睡 · 立即返回 */ }
        )
        await driver.start()
        // 给 task 几毫秒启动
        try? await Task.sleep(nanoseconds: 50_000_000)
        let active = await service.active()
        #expect(active.count >= 1)
        await driver.stop()
    }

    @Test("多次 start · 旧 task cancel + await · 防双 task")
    func reentrantStartCancelsOld() async {
        let store = InMemoryBannerDismissalStore()
        let source = StubBannerSource()
        let service = BannerService(store: store, source: source)
        let driver = BannerRefreshDriver(
            service: service,
            pollIntervalSec: 1,
            sleep: { _ in }
        )
        await driver.start()
        await driver.start()      // 第二次：cancel 旧 + 启新 · 不抛
        await driver.stop()
    }

    @Test("stop · 未 start 也不抛 · idempotent")
    func stopIdempotent() async {
        let store = InMemoryBannerDismissalStore()
        let service = BannerService(store: store, source: StubBannerSource())
        let driver = BannerRefreshDriver(service: service)
        await driver.stop()
        await driver.start()
        await driver.stop()
        await driver.stop()
    }
}
