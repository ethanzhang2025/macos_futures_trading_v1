// 相关性矩阵 mock 时序生成（v15.48）
//
// 设计：
//   - 同板块品种共享一个"板块因子"（注入相关性）
//   - 每品种独立扰动（idiosyncratic noise）
//   - 价格 = 同板块因子 × ratio + 独立扰动 × (1-ratio)
//   - 默认 ratio=0.65 → 同板块预期 r ≈ 0.6-0.8 · 跨板块 r ≈ 0-0.3
//
// 使用：
//   let series = CorrelationMockSeries.generate(for: SectorPresets.all, count: 200)
//   let matrix = CorrelationMatrixCalculator.compute(seriesByID: series, orderedIDs: SectorPresets.all.map { $0.id })
//
// v2 接 CTP 真历史 K 线后 · 整段废弃 · API 不变（只换数据来源）

import Foundation

public enum CorrelationMockSeries {

    /// 为指定品种生成 mock 价格时序（跨板块自然产生差异化相关）
    /// - Parameter instruments: 品种列表
    /// - Parameter count: 时序长度（默认 200 ≈ 1 月日线）
    /// - Parameter sectorRatio: 板块因子权重（[0, 1] · 默认 0.65）
    /// - Returns: [id: [price]] 字典（每品种 count 个价格点）
    public static func generate(
        for instruments: [SectorInstrument],
        count: Int = 200,
        sectorRatio: Double = 0.65
    ) -> [String: [Double]] {
        // 1. 每板块预生成"板块基础因子"（log-return 时序）
        var sectorFactors: [Sector: [Double]] = [:]
        for sec in Sector.allCases {
            sectorFactors[sec] = generateLogReturnSeries(seed: UInt64(bitPattern: Int64(sec.rawValue.hashValue)),
                                                         count: count - 1)
        }

        // 2. 每品种 = 板块因子 × ratio + 独立扰动 × (1 - ratio)
        var result: [String: [Double]] = [:]
        for inst in instruments {
            let basePrice = NSDecimalNumber(decimal: inst.lastPrice).doubleValue
            let sectorFactor = sectorFactors[inst.sector] ?? []
            let idiosyncratic = generateLogReturnSeries(
                seed: UInt64(bitPattern: Int64(inst.id.hashValue) &* 0x9E37 &+ 0xBEEF),
                count: count - 1
            )
            var price = basePrice
            var prices: [Double] = [basePrice]
            for i in 0..<(count - 1) {
                let secR = sectorFactor[i]
                let indR = idiosyncratic[i]
                let r = secR * sectorRatio + indR * (1 - sectorRatio)
                price *= exp(r)
                prices.append(price)
            }
            result[inst.id] = prices
        }
        return result
    }

    /// 生成长度 n 的 mock log-return 时序（均值 0 · σ ≈ 0.012 · 类似日线波动率）
    private static func generateLogReturnSeries(seed: UInt64, count: Int) -> [Double] {
        var rng = SeededRNG(seed: seed)
        var rets: [Double] = []
        rets.reserveCapacity(count)
        for _ in 0..<count {
            // Box-Muller 正态分布 · σ = 0.012（≈ 1.2% 日波动）
            rets.append(rng.nextGaussian() * 0.012)
        }
        return rets
    }
}

// MARK: - 简易 SeededRNG（XorShift64 + Box-Muller · 不依赖外部库）

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xCAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }

    mutating func nextDouble() -> Double {
        Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
    }

    mutating func nextGaussian() -> Double {
        let u1 = max(1e-10, nextDouble())
        let u2 = max(1e-10, nextDouble())
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
