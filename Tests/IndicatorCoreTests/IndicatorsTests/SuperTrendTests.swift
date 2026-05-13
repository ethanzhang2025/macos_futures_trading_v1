// v17.139 · SuperTrend 单测
// 算法对齐麦语言 SUPERTREND() · rolling lock + prev close vs prev ST 翻转

import Testing
import Foundation
@testable import IndicatorCore
import Shared

@Suite("SuperTrend · ATR 趋势止损线")
struct SuperTrendTests {

    private func makeSeries(opens: [Double], highs: [Double], lows: [Double], closes: [Double]) -> KLineSeries {
        let n = closes.count
        return KLineSeries(
            opens:  opens.map  { Decimal($0) },
            highs:  highs.map  { Decimal($0) },
            lows:   lows.map   { Decimal($0) },
            closes: closes.map { Decimal($0) },
            volumes: Array(repeating: 100, count: n),
            openInterests: Array(repeating: 0, count: n)
        )
    }

    private func makeOHLC(_ ohlc: [(Double, Double, Double, Double)]) -> KLineSeries {
        makeSeries(
            opens:  ohlc.map(\.0),
            highs:  ohlc.map(\.1),
            lows:   ohlc.map(\.2),
            closes: ohlc.map(\.3)
        )
    }

    @Test("warm-up 期 (i < period) · ST 与 DIR 全 nil")
    func warmupNils() throws {
        // period=10 · 给 5 根 · ATR warm-up 不够 → 全 nil
        let ohlc = (1...5).map { i -> (Double, Double, Double, Double) in
            let p = Double(i) * 10
            return (p, p + 1, p - 1, p + 0.5)
        }
        let series = makeOHLC(ohlc)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        #expect(result.count == 2)
        #expect(result[0].name == "SUPERTREND")
        #expect(result[1].name == "SUPERTREND-DIR")
        for v in result[0].values { #expect(v == nil) }
        for v in result[1].values { #expect(v == nil) }
    }

    @Test("持续单调上涨 · 多头 · DIR=+1 · ST 在价格下方 · rolling lock 只升不降")
    func upTrendMonotonicLong() throws {
        // 14 根稳健上涨 · period=10
        let ohlc = (1...14).map { i -> (Double, Double, Double, Double) in
            let base = Double(i) * 5
            return (base, base + 1, base - 0.5, base + 0.8)   // close 略高 · 强多头
        }
        let series = makeOHLC(ohlc)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        let st = result[0].values
        let dir = result[1].values

        // 第 9 根（idx 9）为 ATR 第一个有效点 · 之后多头持续
        #expect(st[9] != nil)
        #expect(dir[9] == Decimal(1))
        // 后续 ST 单调非递减（rolling lock · long 时只升）
        var prev = st[9]!
        for i in 10..<14 {
            #expect(dir[i] == Decimal(1))
            #expect(st[i]! >= prev)
            prev = st[i]!
        }
    }

    @Test("ST 永远位于 close 之下（多头）或之上（空头）")
    func stRespectsTrendSide() throws {
        let ohlc = (1...20).map { i -> (Double, Double, Double, Double) in
            let base = Double(i) * 4
            return (base, base + 1.5, base - 1.5, base + 1)
        }
        let series = makeOHLC(ohlc)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        let st = result[0].values
        let dir = result[1].values
        let closes = ohlc.map(\.3)
        for i in 0..<closes.count {
            guard let s = st[i], let d = dir[i] else { continue }
            let c = Decimal(closes[i])
            if d == Decimal(1) {
                #expect(s <= c, "多头时 ST 应 ≤ close · idx=\(i) ST=\(s) close=\(c)")
            } else {
                #expect(s >= c, "空头时 ST 应 ≥ close · idx=\(i) ST=\(s) close=\(c)")
            }
        }
    }

    @Test("先涨后跌 · trend flip 多 → 空 · DIR 切换")
    func trendFlipFromLongToShort() throws {
        // 前 14 根上涨 · 后 6 根急跌穿越 ST → 翻空
        var ohlc: [(Double, Double, Double, Double)] = (1...14).map { i in
            let base = Double(i) * 5
            return (base, base + 1, base - 0.5, base + 0.8)
        }
        // 急跌：close 暴跌穿过 ST
        for i in 0..<6 {
            let drop = Double(80 - i * 15)
            ohlc.append((drop + 1, drop + 2, drop - 5, drop))
        }
        let series = makeOHLC(ohlc)
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        let dir = result[1].values

        // 前 14 根末（idx 13）应仍为多
        #expect(dir[13] == Decimal(1))
        // 后 6 根有至少 1 根翻空（DIR == -1）
        let backDirs = dir[14..<20].compactMap { $0 }
        let hasShort = backDirs.contains { $0 == Decimal(-1) }
        #expect(hasShort, "急跌后应至少出现一次空头方向标记 · backDirs=\(backDirs)")
    }

    @Test("自定义 multiplier 越大 · ST 与 close 距离越远")
    func multiplierWidensBands() throws {
        let ohlc = (1...20).map { i -> (Double, Double, Double, Double) in
            let base = Double(i) * 5
            return (base, base + 2, base - 2, base + 1)
        }
        let series = makeOHLC(ohlc)
        let r1 = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(2)])
        let r3 = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(5)])
        // 选末根 · 多头时 mult=5 的 ST 应比 mult=2 离 close 更远（更低）
        let last = ohlc.count - 1
        guard let st1 = r1[0].values[last], let st3 = r3[0].values[last] else {
            Issue.record("末根 ST 应有值"); return
        }
        let close = Decimal(ohlc[last].3)
        let dist1 = close - st1   // 多头时 close > ST · 距离 = close - st
        let dist3 = close - st3
        #expect(dist3 > dist1, "mult=5 距离应 > mult=2 · dist1=\(dist1) dist3=\(dist3)")
    }

    @Test("非法 period · 抛 invalidParameter")
    func invalidPeriod() {
        let ohlc: [(Double, Double, Double, Double)] = (1...5).map { i in
            let d = Double(i)
            return (d, d + 1, d - 1, d)
        }
        let series = makeOHLC(ohlc)
        do {
            _ = try SuperTrend.calculate(kline: series, params: [Decimal(0), Decimal(3)])
            Issue.record("period=0 应抛错")
        } catch {}
        do {
            _ = try SuperTrend.calculate(kline: series, params: [Decimal(10)])   // 缺 mult
            Issue.record("缺 multiplier 应抛错")
        } catch {}
        do {
            _ = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(0)])
            Issue.record("mult=0 应抛错")
        } catch {}
    }

    @Test("空序列 · 输出空 series 数组（2 列长度 0）")
    func emptySeries() throws {
        let series = KLineSeries(
            opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: []
        )
        let result = try SuperTrend.calculate(kline: series, params: [Decimal(10), Decimal(3)])
        #expect(result.count == 2)
        #expect(result[0].values.isEmpty)
        #expect(result[1].values.isEmpty)
    }

    @Test("identifier + category + parameters · 默认 10/3")
    func metadata() {
        #expect(SuperTrend.identifier == "SUPERTREND")
        #expect(SuperTrend.category == .trend)
        #expect(SuperTrend.parameters.count == 2)
        #expect(SuperTrend.parameters[0].name == "period")
        #expect(SuperTrend.parameters[0].defaultValue == 10)
        #expect(SuperTrend.parameters[1].name == "multiplier")
        #expect(SuperTrend.parameters[1].defaultValue == 3)
    }
}
