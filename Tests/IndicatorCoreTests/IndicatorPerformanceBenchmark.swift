// WP-96 v15.23 batch57 · 指标计算性能 baseline benchmark
//
// 用途：
// - 建立 Linux CI 上 MA/EMA/BOLL/MACD/KDJ 在 10K 根 K 线上的计算时间 baseline
// - 防回归：单次 calculate 超过阈值 (毫秒) 测试失败
// - 阈值放宽（10×）确保 CI 不同硬件不会随机红
//
// 用 Date() 计时（不依赖 ContinuousClock · 兼容老 Swift）
// 多次跑取 median 减少抖动
// 阈值参考本机基线 + 10× safety factor

import Testing
import Foundation
@testable import IndicatorCore

@Suite("IndicatorCore · 性能 baseline（防回归 · WP-96 v15.23 batch57）")
struct IndicatorPerformanceBenchmark {

    /// 生成 10000 根 mock K 线（一次性 · 共享）
    static let mockBars: KLineSeries = {
        var rng = SystemRandomNumberGenerator()
        var price = 3500.0
        var opens: [Decimal] = []
        var highs: [Decimal] = []
        var lows: [Decimal] = []
        var closes: [Decimal] = []
        var volumes: [Int] = []
        var ois: [Int] = []
        opens.reserveCapacity(10000)
        highs.reserveCapacity(10000)
        lows.reserveCapacity(10000)
        closes.reserveCapacity(10000)
        volumes.reserveCapacity(10000)
        ois.reserveCapacity(10000)
        for _ in 0..<10000 {
            let drift = Double.random(in: -5...5, using: &rng)
            let open = price
            let close = max(100, price + drift)
            let high = max(open, close) + Double.random(in: 0...3, using: &rng)
            let low = min(open, close) - Double.random(in: 0...3, using: &rng)
            opens.append(Decimal(open))
            highs.append(Decimal(high))
            lows.append(Decimal(low))
            closes.append(Decimal(close))
            volumes.append(Int.random(in: 800...4000, using: &rng))
            ois.append(0)
            price = close
        }
        return KLineSeries(opens: opens, highs: highs, lows: lows, closes: closes,
                           volumes: volumes, openInterests: ois)
    }()

    // MARK: - Helpers

    /// 跑 N 次取毫秒中位数（减少抖动）
    static func medianMs(iterations: Int = 5, _ block: () throws -> Void) rethrows -> Double {
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = Date()
            try block()
            let elapsed = Date().timeIntervalSince(start) * 1000
            times.append(elapsed)
        }
        times.sort()
        return times[times.count / 2]
    }

    // MARK: - 单指标 baseline

    // Baseline 阈值（基于本机 Linux Decimal 软件运算实测 × 2.5 safety factor · 不同机器跑 CI 也能过）
    // 本机实测：MA(60)~616ms · BOLL~1181ms · 综合 5~2588ms
    // Decimal 在 Linux 上为软件实现 · 比 macOS native arm64 慢 5-10× · 阈值已留充分余地

    @Test("MA(60) on 10K bars · < 1500ms baseline（防回归）")
    func benchmarkMA() throws {
        let ms = try Self.medianMs {
            _ = try MA.calculate(kline: Self.mockBars, params: [Decimal(60)])
        }
        #expect(ms < 1500, "MA(60) 10K 慢了：\(ms)ms（baseline ~616ms · 上限 1500ms）")
    }

    @Test("EMA(60) on 10K bars · < 500ms baseline")
    func benchmarkEMA() throws {
        let ms = try Self.medianMs {
            _ = try EMA.calculate(kline: Self.mockBars, params: [Decimal(60)])
        }
        #expect(ms < 500, "EMA(60) 10K 慢了：\(ms)ms（baseline < 200ms）")
    }

    @Test("BOLL(20, 2) on 10K bars · < 3000ms baseline")
    func benchmarkBOLL() throws {
        let ms = try Self.medianMs {
            _ = try BOLL.calculate(kline: Self.mockBars, params: [Decimal(20), Decimal(2)])
        }
        // BOLL 含 STD 计算 · 比 MA 慢
        #expect(ms < 3000, "BOLL(20,2) 10K 慢了：\(ms)ms（baseline ~1181ms）")
    }

    @Test("MACD(12,26,9) on 10K bars · < 1500ms baseline")
    func benchmarkMACD() throws {
        let ms = try Self.medianMs {
            _ = try MACD.calculate(kline: Self.mockBars,
                                   params: [Decimal(12), Decimal(26), Decimal(9)])
        }
        #expect(ms < 1500, "MACD(12,26,9) 10K 慢了：\(ms)ms")
    }

    @Test("KDJ(9,3,3) on 10K bars · < 1500ms baseline")
    func benchmarkKDJ() throws {
        let ms = try Self.medianMs {
            _ = try KDJ.calculate(kline: Self.mockBars,
                                  params: [Decimal(9), Decimal(3), Decimal(3)])
        }
        #expect(ms < 1500, "KDJ(9,3,3) 10K 慢了：\(ms)ms")
    }

    /// 综合：5 指标连跑（trader 切合约 / 周期典型流量）
    @Test("综合：5 指标全跑一遍 on 10K bars · < 6500ms 综合 baseline")
    func benchmarkAllIndicators() throws {
        let ms = try Self.medianMs {
            _ = try MA.calculate(kline: Self.mockBars, params: [Decimal(60)])
            _ = try EMA.calculate(kline: Self.mockBars, params: [Decimal(60)])
            _ = try BOLL.calculate(kline: Self.mockBars, params: [Decimal(20), Decimal(2)])
            _ = try MACD.calculate(kline: Self.mockBars,
                                   params: [Decimal(12), Decimal(26), Decimal(9)])
            _ = try KDJ.calculate(kline: Self.mockBars,
                                  params: [Decimal(9), Decimal(3), Decimal(3)])
        }
        #expect(ms < 6500, "5 指标综合 10K 慢了：\(ms)ms（baseline ~2588ms · 每指标平均 \(ms/5)ms）")
    }
}
