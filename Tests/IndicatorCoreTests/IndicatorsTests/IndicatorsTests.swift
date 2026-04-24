// WP-41 · 8 代表性指标基础测试
// 覆盖：MA / EMA / RSI / MACD / BOLL / ATR / OBV / OI + 边界 / 参数错误
// 对照值用简单已知序列手工推导（避免把实现错误和测试同步写错）

import Testing
import Foundation
@testable import IndicatorCore

// MARK: - 辅助

/// 用 closes 构造最简 KLineSeries（其他列用 closes 填占位，volumes/OI 给 0）
private func series(closes: [Int]) -> KLineSeries {
    let ds = closes.map { Decimal($0) }
    let zeros = [Int](repeating: 0, count: closes.count)
    return KLineSeries(opens: ds, highs: ds, lows: ds, closes: ds, volumes: zeros, openInterests: zeros)
}

/// 容忍 Double 转回 Decimal 的微小误差（stddev 类）
private func approx(_ lhs: Decimal?, _ rhs: Double, tol: Double = 0.001) -> Bool {
    guard let lhs else { return false }
    let l = NSDecimalNumber(decimal: lhs).doubleValue
    return (l - rhs).magnitude < tol
}

// MARK: - MA / EMA

@Suite("MA / EMA")
struct MAEMATests {
    @Test("MA(3) 对 [1,2,3,4,5]")
    func maBasic() throws {
        let r = try MA.calculate(kline: series(closes: [1, 2, 3, 4, 5]), params: [3])
        let v = r[0].values
        #expect(v[0] == nil && v[1] == nil)
        #expect(v[2] == 2)
        #expect(v[3] == 3)
        #expect(v[4] == 4)
        #expect(r[0].name == "MA(3)")
    }

    @Test("EMA 种子处为 SMA，后续按 α 更新")
    func emaBasic() throws {
        // EMA(3) 对 [10,20,30,40,50]：α = 2/4 = 0.5
        // 种子 i=2: SMA(10,20,30)=20
        // i=3: 0.5*40 + 0.5*20 = 30
        // i=4: 0.5*50 + 0.5*30 = 40
        let r = try EMA.calculate(kline: series(closes: [10, 20, 30, 40, 50]), params: [3])
        let v = r[0].values
        #expect(v[2] == 20)
        #expect(v[3] == 30)
        #expect(v[4] == 40)
    }

    @Test("周期不够时全 nil")
    func insufficientData() throws {
        let r = try MA.calculate(kline: series(closes: [1, 2]), params: [5])
        #expect(r[0].values.allSatisfy { $0 == nil })
    }

    @Test("period <= 0 抛参数错误")
    func invalidPeriod() {
        #expect(throws: IndicatorError.self) {
            _ = try MA.calculate(kline: series(closes: [1, 2, 3]), params: [0])
        }
    }
}

// MARK: - RSI

@Suite("RSI")
struct RSITests {
    @Test("RSI(2) 对 [10,11,10,11,12]")
    func rsiBasic() throws {
        let r = try RSI.calculate(kline: series(closes: [10, 11, 10, 11, 12]), params: [2])
        let v = r[0].values
        // 手工推导（详 RSI.swift 顶注 Wilder 公式）
        #expect(approx(v[1], 100.0))         // U=[0,1], D=[0,0], avgU=0.5, avgD=0
        #expect(approx(v[2], 33.333, tol: 0.01))   // U=0, D=1 => avgU=0.25, avgD=0.5
        #expect(approx(v[3], 71.428, tol: 0.01))
        #expect(approx(v[4], 86.666, tol: 0.01))
    }

    @Test("全部不动时 RSI = 50（U=D=0 特判）")
    func flatPrice() throws {
        let r = try RSI.calculate(kline: series(closes: [10, 10, 10, 10]), params: [2])
        #expect(r[0].values[1] == 50)
    }
}

// MARK: - MACD

@Suite("MACD")
struct MACDTests {
    @Test("MACD 返回 3 条序列")
    func threeSeries() throws {
        let closes = Array(1...50).map { Decimal($0) }
        let zeros = [Int](repeating: 0, count: closes.count)
        let k = KLineSeries(opens: closes, highs: closes, lows: closes, closes: closes, volumes: zeros, openInterests: zeros)
        let r = try MACD.calculate(kline: k, params: [12, 26, 9])
        #expect(r.count == 3)
        #expect(r.map { $0.name } == ["DIF", "DEA", "MACD"])
        // 趋势上涨中 DIF > 0（应能算出）
        #expect(r[0].values.last! != nil)
    }

    @Test("参数不足抛错")
    func insufficientParams() {
        #expect(throws: IndicatorError.self) {
            _ = try MACD.calculate(kline: series(closes: [1, 2, 3]), params: [12, 26])
        }
    }
}

// MARK: - BOLL

@Suite("BOLL")
struct BOLLTests {
    @Test("BOLL 三轨关系（UPPER > MID > LOWER）")
    func threeBands() throws {
        let r = try BOLL.calculate(kline: series(closes: [10, 12, 14, 12, 10]), params: [3, 2])
        #expect(r.count == 3)
        let mid = r[0].values[2]!
        let upper = r[1].values[2]!
        let lower = r[2].values[2]!
        #expect(upper > mid)
        #expect(mid > lower)
        #expect(mid == 12)  // (10+12+14)/3
    }
}

// MARK: - ATR

@Suite("ATR")
struct ATRTests {
    @Test("ATR(2) TR 计算正确")
    func atrBasic() throws {
        // highs=[10,12,11] lows=[9,10,9] closes=[9.5,11,10]
        // TR = [1, 2.5, 2]；Wilder(2) 种子=1.75, i=2: (1.75+2)/2 = 1.875
        let opens: [Decimal] = [10, 12, 11]
        let highs: [Decimal] = [10, 12, 11]
        let lows: [Decimal] = [9, 10, 9]
        let closes: [Decimal] = [Decimal(string: "9.5")!, 11, 10]
        let k = KLineSeries(opens: opens, highs: highs, lows: lows, closes: closes, volumes: [0, 0, 0], openInterests: [0, 0, 0])
        let r = try ATR.calculate(kline: k, params: [2])
        #expect(approx(r[0].values[1], 1.75))
        #expect(approx(r[0].values[2], 1.875))
    }
}

// MARK: - OBV

@Suite("OBV")
struct OBVTests {
    @Test("OBV 累积随 close 方向")
    func obvAccumulation() throws {
        // closes=[10,11,10,12] volumes=[100,200,150,300]
        // OBV = [100, 300 (up +200), 150 (down -150), 450 (up +300)]
        let closes: [Decimal] = [10, 11, 10, 12]
        let k = KLineSeries(
            opens: closes, highs: closes, lows: closes, closes: closes,
            volumes: [100, 200, 150, 300],
            openInterests: [0, 0, 0, 0]
        )
        let r = try OBV.calculate(kline: k, params: [])
        #expect(r[0].values[0] == 100)
        #expect(r[0].values[1] == 300)
        #expect(r[0].values[2] == 150)
        #expect(r[0].values[3] == 450)
    }
}

// MARK: - OpenInterest（期货特有）

@Suite("OpenInterest")
struct OpenInterestTests {
    @Test("OI 直通 openInterests 列")
    func oiPassthrough() throws {
        let closes: [Decimal] = [10, 11, 12]
        let k = KLineSeries(
            opens: closes, highs: closes, lows: closes, closes: closes,
            volumes: [0, 0, 0],
            openInterests: [1000, 1050, 1080]
        )
        let r = try OpenInterest.calculate(kline: k, params: [])
        #expect(r[0].values[0] == 1000)
        #expect(r[0].values[1] == 1050)
        #expect(r[0].values[2] == 1080)
        #expect(OpenInterest.category == .futures)
    }
}
