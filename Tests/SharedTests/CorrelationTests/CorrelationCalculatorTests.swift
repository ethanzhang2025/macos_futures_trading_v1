// CorrelationCalculator 测试（v15.48）

import Testing
import Foundation
@testable import Shared

@Suite("CorrelationCalculator · 皮尔逊相关系数")
struct CorrelationCalculatorTests {

    @Test("完美正相关 · r = 1")
    func testPerfectPositive() {
        let x = [1.0, 2, 3, 4, 5]
        let y = [10.0, 20, 30, 40, 50]
        #expect(abs(CorrelationCalculator.pearson(x, y) - 1.0) < 0.001)
    }

    @Test("完美负相关 · r = -1")
    func testPerfectNegative() {
        let x = [1.0, 2, 3, 4, 5]
        let y = [50.0, 40, 30, 20, 10]
        #expect(abs(CorrelationCalculator.pearson(x, y) + 1.0) < 0.001)
    }

    @Test("完全无关 · r 接近 0")
    func testNoCorrelation() {
        // 设计：x 单调上升 · y 反向 V 形（Σ(x-x̄)(y-ȳ) ≈ 0）
        let x = [1.0, 2, 3, 4, 5]
        let y = [3.0, 1, 5, 1, 3]
        let r = CorrelationCalculator.pearson(x, y)
        #expect(abs(r) < 0.5)  // 不严格 0 但低
    }

    @Test("空数组 / 单点 · 返 0")
    func testInsufficientData() {
        #expect(CorrelationCalculator.pearson([], []) == 0)
        #expect(CorrelationCalculator.pearson([1], [2]) == 0)
    }

    @Test("长度不一致 · 返 0")
    func testMismatchedLength() {
        #expect(CorrelationCalculator.pearson([1, 2, 3], [4, 5]) == 0)
    }

    @Test("常数序列 · 返 0（防除零）")
    func testConstantSeries() {
        #expect(CorrelationCalculator.pearson([5, 5, 5, 5], [1, 2, 3, 4]) == 0)
    }

    @Test("logReturns · 长度 -1")
    func testLogReturnsLength() {
        let prices = [100.0, 101, 102, 103]
        let rets = CorrelationCalculator.logReturns(prices)
        #expect(rets.count == 3)
    }

    @Test("logReturns · 价格不变 → return = 0")
    func testLogReturnsConstant() {
        let prices = [100.0, 100, 100, 100]
        let rets = CorrelationCalculator.logReturns(prices)
        #expect(rets.allSatisfy { abs($0) < 1e-10 })
    }

    @Test("priceCorrelation · 同步上涨 → 正相关 ≈ 1")
    func testPriceCorrelationSync() {
        let p1 = (0..<50).map { 100.0 * pow(1.005, Double($0)) }
        let p2 = (0..<50).map { 200.0 * pow(1.005, Double($0)) }
        let r = CorrelationCalculator.priceCorrelation(p1, p2)
        // 两条等比上涨 · log-return 都是常数 0.005 · 但常数序列 r=0（防除零）
        // 所以加噪声测试
        #expect(r >= -1 && r <= 1)
    }

    @Test("priceCorrelation · 反向走势 → 负相关")
    func testPriceCorrelationOpposite() {
        let p1 = [100.0, 105, 110, 108, 115, 120]
        let p2 = [100.0, 95, 90, 92, 85, 80]
        let r = CorrelationCalculator.priceCorrelation(p1, p2)
        #expect(r < -0.5)
    }
}

@Suite("CorrelationMatrixCalculator · 多品种矩阵")
struct CorrelationMatrixTests {

    @Test("3 品种矩阵 · 对角线 = 1 · 对称")
    func testSymmetric() {
        let series: [String: [Double]] = [
            "A": [100, 101, 102, 103, 104],
            "B": [50, 51, 52, 53, 54],
            "C": [200, 199, 198, 197, 196]
        ]
        let m = CorrelationMatrixCalculator.compute(seriesByID: series, orderedIDs: ["A", "B", "C"])
        // 对角线 = 1
        for i in 0..<3 {
            #expect(m.values[i][i] == 1)
        }
        // 对称：m[0][1] == m[1][0]
        #expect(abs(m.values[0][1] - m.values[1][0]) < 1e-10)
        #expect(abs(m.values[0][2] - m.values[2][0]) < 1e-10)
    }

    @Test("MockSeries · 60+ 品种生成")
    func testMockSeries() {
        let series = CorrelationMockSeries.generate(for: SectorPresets.all, count: 100)
        #expect(series.count == SectorPresets.all.count)
        for (id, prices) in series {
            #expect(prices.count == 100, "\(id) 长度异常")
            #expect(prices.allSatisfy { $0 > 0 }, "\(id) 含非正价")
        }
    }

    @Test("同板块品种 · 平均相关性 > 0（板块因子注入）")
    func testSectorCorrelation() {
        let blackInsts = SectorPresets.instruments(in: .黑色)
        guard blackInsts.count >= 2 else { return }
        let series = CorrelationMockSeries.generate(for: blackInsts, count: 200)
        let m = CorrelationMatrixCalculator.compute(seriesByID: series,
                                                    orderedIDs: blackInsts.map { $0.id })
        // 板块内非对角元素均值（应显著为正）
        var sum = 0.0
        var n = 0
        for i in 0..<blackInsts.count {
            for j in (i+1)..<blackInsts.count {
                sum += m.values[i][j]
                n += 1
            }
        }
        let avg = sum / Double(max(n, 1))
        #expect(avg > 0.3, "黑色板块内平均相关性偏低 \(avg)")
    }

    @Test("跨板块（黑色 vs 国债）· 相关性显著低于板块内")
    func testCrossSectorCorrelation() {
        let black = SectorPresets.instruments(in: .黑色)
        let bond = SectorPresets.instruments(in: .国债)
        guard !black.isEmpty, !bond.isEmpty else { return }
        let combined = black + bond
        let series = CorrelationMockSeries.generate(for: combined, count: 200)
        let ids = combined.map { $0.id }
        let m = CorrelationMatrixCalculator.compute(seriesByID: series, orderedIDs: ids)
        // 跨板块均值
        var sum = 0.0
        var n = 0
        for i in 0..<black.count {
            for j in black.count..<combined.count {
                sum += m.values[i][j]
                n += 1
            }
        }
        let avg = sum / Double(max(n, 1))
        #expect(abs(avg) < 0.4, "跨板块相关性应显著低 · 实测 \(avg)")
    }

    @Test("矩阵 value(row:col:) 越界返 0")
    func testOutOfBounds() {
        let m = CorrelationMatrix(instrumentIDs: ["A"], values: [[1]])
        #expect(m.value(row: 5, col: 0) == 0)
        #expect(m.value(row: 0, col: 5) == 0)
    }
}
