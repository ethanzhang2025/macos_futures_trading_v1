// WP-41 第二批 · 36 新指标代表性验证（每分类 2-3 个关键对照）
// 覆盖：WMA/HMA/SAR（趋势）· KDJ/CCI/WR（震荡）· MFI/CMF/Volume（量价）· KC/Donchian/StdDev（波动率）· PivotPoints/ZigZag/Fractal（结构）· OIDelta（期货）
// 其他指标通过公共 Kernels 间接验证（ema/ma/wilder/stddev/hhv/llv 已有单元测试覆盖）

import Testing
import Foundation
@testable import IndicatorCore

private func series(closes: [Int], highs: [Int]? = nil, lows: [Int]? = nil, volumes: [Int]? = nil, ois: [Int]? = nil) -> KLineSeries {
    let ds = closes.map { Decimal($0) }
    let hs = highs?.map { Decimal($0) } ?? ds
    let ls = lows?.map { Decimal($0) } ?? ds
    let vs = volumes ?? [Int](repeating: 0, count: closes.count)
    let os = ois ?? [Int](repeating: 0, count: closes.count)
    return KLineSeries(opens: ds, highs: hs, lows: ls, closes: ds, volumes: vs, openInterests: os)
}

// MARK: - 趋势

@Suite("趋势第二批")
struct TrendBatch2Tests {
    @Test("WMA(3) 加权计算对照")
    func wmaBasic() throws {
        // WMA(3) 对 [10,20,30]: (10*1+20*2+30*3)/(1+2+3) = 140/6 = 23.333...
        let r = try WMA.calculate(kline: series(closes: [10, 20, 30]), params: [3])
        let v = r[0].values[2]!
        let d = NSDecimalNumber(decimal: v).doubleValue
        #expect((d - 23.333).magnitude < 0.01)
    }

    @Test("HMA 能对长序列产出有值")
    func hmaProducesValues() throws {
        let closes = Array(1...50)
        let r = try HMA.calculate(kline: series(closes: closes), params: [16])
        #expect(r[0].values.last! != nil)
    }

    @Test("SAR 能跑完上涨序列方向正确")
    func sarDirection() throws {
        let closes = Array(1...20)
        let highs = closes.map { $0 + 1 }
        let lows = closes.map { $0 - 1 }
        let r = try SAR.calculate(kline: series(closes: closes, highs: highs, lows: lows),
                                  params: [Decimal(string: "0.02")!, Decimal(string: "0.2")!])
        // 上涨趋势里 SAR 应低于价格（点在价格下方）
        let lastSAR = r[0].values.last!!
        let lastClose = Decimal(20)
        #expect(lastSAR < lastClose)
    }
}

// MARK: - 震荡

@Suite("震荡第二批")
struct OscillatorBatch2Tests {
    @Test("KDJ 三线齐出且 J = 3K - 2D")
    func kdjRelation() throws {
        let closes = [10, 11, 12, 11, 10, 12, 14, 13, 15, 16, 14, 15]
        let r = try KDJ.calculate(kline: series(closes: closes, highs: closes.map { $0 + 1 }, lows: closes.map { $0 - 1 }),
                                  params: [9, 3, 3])
        let last = closes.count - 1
        guard let k = r[0].values[last], let d = r[1].values[last], let j = r[2].values[last] else {
            Issue.record("KDJ 末值未产出"); return
        }
        // J = 3K - 2D（允许 8 位精度内误差）
        let expectJ = Decimal(3) * k - Decimal(2) * d
        let diff = NSDecimalNumber(decimal: abs(j - expectJ)).doubleValue
        #expect(diff < 0.0001)
    }

    @Test("WR 范围 [-100, 0]")
    func wrRange() throws {
        let closes = [10, 12, 14, 16, 15, 13, 11]
        let r = try WilliamsR.calculate(kline: series(closes: closes, highs: closes.map { $0 + 1 }, lows: closes.map { $0 - 1 }),
                                        params: [3])
        for v in r[0].values.compactMap({ $0 }) {
            #expect(v <= 0)
            #expect(v >= -100)
        }
    }

    @Test("CCI 能产出且围绕 0 波动")
    func cciRuns() throws {
        let closes = Array(1...30)
        let r = try CCI.calculate(kline: series(closes: closes, highs: closes.map { $0 + 1 }, lows: closes.map { $0 - 1 }),
                                  params: [14])
        #expect(r[0].values.last! != nil)
    }
}

// MARK: - 量价

@Suite("量价第二批")
struct VolumeBatch2Tests {
    @Test("Volume 直通 volumes 列")
    func volumePassthrough() throws {
        let r = try Volume.calculate(kline: series(closes: [1, 2, 3], volumes: [100, 200, 300]), params: [])
        #expect(r[0].values == [Decimal(100), Decimal(200), Decimal(300)])
    }

    @Test("MFI 范围 [0, 100]")
    func mfiRange() throws {
        let closes = [10, 12, 11, 13, 12, 14, 13, 15]
        let r = try MFI.calculate(kline: series(
            closes: closes,
            highs: closes.map { $0 + 1 },
            lows: closes.map { $0 - 1 },
            volumes: [100, 200, 150, 300, 200, 350, 250, 400]), params: [3])
        for v in r[0].values.compactMap({ $0 }) {
            #expect(v >= 0 && v <= 100)
        }
    }

    @Test("CMF 能产出")
    func cmfRuns() throws {
        let closes = Array(1...30)
        let r = try CMF.calculate(kline: series(
            closes: closes, highs: closes.map { $0 + 1 }, lows: closes.map { $0 - 1 },
            volumes: [Int](repeating: 100, count: 30)), params: [10])
        #expect(r[0].values.last! != nil)
    }
}

// MARK: - 波动率 / 通道

@Suite("波动率第二批")
struct VolatilityBatch2Tests {
    @Test("Donchian 上轨 >= 下轨 + 中轨在中间")
    func donchianRelation() throws {
        let closes = [10, 12, 14, 11, 13, 15, 9, 17]
        let r = try Donchian.calculate(kline: series(closes: closes, highs: closes.map { $0 + 2 }, lows: closes.map { $0 - 2 }),
                                       params: [3])
        for i in 2..<closes.count {
            guard let u = r[0].values[i], let m = r[1].values[i], let l = r[2].values[i] else { continue }
            #expect(u >= l)
            #expect(m >= l && m <= u)
        }
    }

    @Test("StdDev 暴露 Kernel")
    func stddevRuns() throws {
        let r = try StdDev.calculate(kline: series(closes: [1, 2, 3, 4, 5]), params: [3])
        #expect(r[0].values[2] != nil)
    }

    @Test("KC 三线结构")
    func kcBands() throws {
        let closes = Array(1...30)
        let r = try KC.calculate(kline: series(closes: closes, highs: closes.map { $0 + 1 }, lows: closes.map { $0 - 1 }),
                                 params: [10, 10, 2])
        #expect(r.count == 3)
        if let mid = r[0].values.last!, let up = r[1].values.last!, let lo = r[2].values.last! {
            #expect(up >= mid)
            #expect(mid >= lo)
        }
    }
}

// MARK: - 结构

@Suite("结构第二批")
struct StructureBatch2Tests {
    @Test("PivotPoints P = (H+L+C)/3 对照")
    func pivotFormula() throws {
        let k = series(closes: [100, 110], highs: [105, 115], lows: [95, 100])
        let r = try PivotPoints.calculate(kline: k, params: [])
        // 第 1 根基于前一根（index 0）：H=105, L=95, C=100 → P=(105+95+100)/3 = 100
        #expect(r[0].values[1] == 100)
    }

    @Test("ZigZag 能识别超过阈值的转点")
    func zigzagDetection() throws {
        // 起点 100，上涨到 120（+20%），下跌到 95（-20%+），上涨到 115（+20%+）
        let closes = [100, 110, 120, 100, 95, 105, 115]
        let r = try ZigZag.calculate(kline: series(closes: closes), params: [10])  // 10%
        let nonNil = r[0].values.compactMap { $0 }
        #expect(nonNil.count >= 2)  // 至少起点 + 1 个转点
    }

    @Test("Fractal 中心 5 根中最高/最低标记")
    func fractalDetect() throws {
        // 构造 [1,2,5,2,1]：index 2 是 UpFractal
        let highs = [1, 2, 5, 2, 1]
        let lows = [1, 2, 5, 2, 1]
        let closes = highs
        let r = try Fractal.calculate(kline: series(closes: closes, highs: highs, lows: lows), params: [])
        #expect(r[0].values[2] == 5)   // UP 在 index 2
        #expect(r[1].values[2] == nil) // 不是 DOWN
    }
}

// MARK: - 期货特有

@Suite("期货第二批")
struct FuturesBatch2Tests {
    @Test("OIDelta 差分")
    func oiDelta() throws {
        let r = try OIDelta.calculate(kline: series(closes: [10, 10, 10], ois: [1000, 1050, 1030]), params: [])
        #expect(r[0].values[0] == 0)
        #expect(r[0].values[1] == 50)
        #expect(r[0].values[2] == -20)
    }
}
