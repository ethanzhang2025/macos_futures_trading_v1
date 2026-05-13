// v17.157 · OverlayIncrementalStates 性能 baseline
//
// 用途：
// - 防回归：step×500 with 9 overlays 不能慢于阈值（增量化失效 / 算法误改成全量重算等）
// - 对照 v17.139 全量重算 ~50ms/根 · v17.156 增量化目标 ~5ms/根（Mac）/ ~30ms/根（Linux Decimal 软算）
// - 阈值留 Linux Decimal × 2 safety factor

import Testing
import Foundation
import Shared
import IndicatorCore
@testable import MainApp

@Suite("v17.157 · OverlayIncrementalStates 性能 baseline（防回归）")
struct OverlayIncrementalPerfTests {

    static let history: [KLine] = makePerfBars(count: 5000)
    static let steps: [KLine] = makePerfBars(count: 500, baseDate: 5000)

    static func medianMs(iterations: Int = 3, _ block: () throws -> Void) rethrows -> Double {
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = Date()
            try block()
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        times.sort()
        return times[times.count / 2]
    }

    @Test("9 overlay 全开 · prime 5000 history + step 500 · 总时间 < 60000ms（Linux Decimal 软算上限）")
    func nineOverlaysFullBenchmark() throws {
        let kline = makeSeries(from: Self.history)
        var book = MainChartOverlayBook()
        for kind in MainChartOverlayKind.allCases { book.setEnabled(kind, true) }

        let ms = Self.medianMs {
            var states = OverlayIncrementalStates(history: kline, book: book)
            for newBar in Self.steps {
                _ = states.step(newBar: newBar)
            }
        }
        // 实测 Linux Decimal soft: ~30s 左右 prime(5000)+step(500) · 阈值 60s × 2 safety
        // Mac native Decimal arm64 预期 5-10× 快 → ~3-6s · 阈值仍宽松
        #expect(ms < 60_000, "OverlayIncrementalStates 9 全开 prime 5000 + step 500 慢了：\(ms)ms · 阈值 60000ms · 检查是否回归到 v17.139 全量重算路径")
    }

    @Test("step 单根成本 · 9 overlay 全开 · 单 step < 100ms（Linux 上限）")
    func singleStepCostBenchmark() throws {
        let kline = makeSeries(from: Self.history)
        var book = MainChartOverlayBook()
        for kind in MainChartOverlayKind.allCases { book.setEnabled(kind, true) }
        var states = OverlayIncrementalStates(history: kline, book: book)
        // 单根 step 时间（避免初始化噪声 · prime 已分摊）
        let ms = Self.medianMs(iterations: 5) {
            _ = states.step(newBar: Self.steps[0])
        }
        // v17.139 全量重算 5000 bars · 9 overlay ~50ms+ (Mac) / 几百 ms (Linux 软算)
        // v17.156 增量化 9 overlay 单根 ~5ms (Mac) / ~30ms (Linux) 期望
        // 阈值 100ms · 留 Linux 软算余地
        #expect(ms < 100, "单 step × 9 overlay 慢了：\(ms)ms · 阈值 100ms · v17.139 全量重算 50ms+ 性能等级")
    }
}

// MARK: - helper（perf 专用 · 大序列）

fileprivate func makePerfBars(count: Int, baseDate: Int = 0) -> [KLine] {
    var rng = SystemRandomNumberGenerator()
    var price = 3500.0
    return (0..<count).map { i in
        let drift = Double.random(in: -5...5, using: &rng)
        let open = price
        let close = max(100, price + drift)
        let high = max(open, close) + Double.random(in: 0...3, using: &rng)
        let low = min(open, close) - Double.random(in: 0...3, using: &rng)
        defer { price = close }
        return KLine(
            instrumentID: "PERF",
            period: .minute1,
            openTime: Date(timeIntervalSinceReferenceDate: TimeInterval((baseDate + i) * 60)),
            open: Decimal(open),
            high: Decimal(high),
            low: Decimal(low),
            close: Decimal(close),
            volume: Int.random(in: 800...4000, using: &rng),
            openInterest: 0,
            turnover: 0
        )
    }
}

fileprivate func makeSeries(from bars: [KLine]) -> KLineSeries {
    KLineSeries(
        opens: bars.map(\.open),
        highs: bars.map(\.high),
        lows: bars.map(\.low),
        closes: bars.map(\.close),
        volumes: bars.map(\.volume),
        openInterests: bars.map { _ in 0 }
    )
}
