// v15.19 batch25 · VolumeProfile 单测

import Testing
import Foundation
@testable import Shared

@Suite("VolumeProfile · 价格分桶累计 v15.19 batch25")
struct VolumeProfileTests {

    private func bar(low: Decimal, high: Decimal, volume: Int) -> KLine {
        KLine(
            instrumentID: "RB0", period: .minute15,
            openTime: Date(),
            open: low, high: high, low: low, close: high,
            volume: volume, openInterest: 0, turnover: 0
        )
    }

    @Test("空 bars · 返回 []")
    func emptyBars() {
        let bins = VolumeProfile.compute(bars: [])
        #expect(bins.isEmpty)
    }

    @Test("单一价格（high == low）· 返回单个 bin · 全部 volume")
    func singlePrice() {
        let bars = [bar(low: 100, high: 100, volume: 50)]
        let bins = VolumeProfile.compute(bars: bars, binCount: 24)
        #expect(bins.count == 1)
        #expect(bins[0].volume == 50)
    }

    @Test("binCount 默认 24 · 价格区间均分")
    func defaultBinCount() {
        let bars = [bar(low: 100, high: 124, volume: 240)]
        let bins = VolumeProfile.compute(bars: bars)
        #expect(bins.count == 24)
        // 单根 K 线覆盖全部 24 bin · 平均分配 240/24 = 10
        for bin in bins {
            #expect(bin.volume == 10)
        }
    }

    @Test("binCount clamp · 范围 [4, 200]")
    func binCountClamp() {
        let bars = [bar(low: 100, high: 124, volume: 100)]
        let tooSmall = VolumeProfile.compute(bars: bars, binCount: 1)
        #expect(tooSmall.count == 4)
        let tooLarge = VolumeProfile.compute(bars: bars, binCount: 1000)
        #expect(tooLarge.count == 200)
    }

    @Test("多根 K 线 · 价格集中区累积 volume 高")
    func concentratedZone() {
        // 3 根集中在 [105, 110] · 1 根分布在 [100, 120]
        let bars = [
            bar(low: 105, high: 110, volume: 60),
            bar(low: 105, high: 110, volume: 60),
            bar(low: 105, high: 110, volume: 60),
            bar(low: 100, high: 120, volume: 20)
        ]
        let bins = VolumeProfile.compute(bars: bars, binCount: 20)
        // 价格区间 [100, 120] · binWidth = 1 · 105-110 这 5 桶应该 volume 高
        let peakIdx = bins.indices.max(by: { bins[$0].volume < bins[$1].volume }) ?? 0
        let peakBin = bins[peakIdx]
        let peakLow = NSDecimalNumber(decimal: peakBin.priceLow).doubleValue
        // 峰值落在 [105, 110] 区间内
        #expect(peakLow >= 105 && peakLow < 110)
    }

    @Test("Bin priceCenter = (low + high) / 2")
    func priceCenter() {
        let bin = VolumeProfile.Bin(priceLow: 100, priceHigh: 110, volume: 50)
        #expect(bin.priceCenter == 105)
    }

    @Test("bins 按价格升序")
    func binsAscendingOrder() {
        let bars = [bar(low: 100, high: 200, volume: 100)]
        let bins = VolumeProfile.compute(bars: bars, binCount: 10)
        for i in 1..<bins.count {
            #expect(bins[i].priceLow >= bins[i-1].priceLow)
        }
    }

    // v17.30 B2 · Value Area
    @Test("valueArea · 空 bins / 全 0 volume / percent ≤ 0 返回 nil")
    func valueAreaEdgeCases() {
        #expect(VolumeProfile.valueArea(bins: []) == nil)
        let zeroBins = [VolumeProfile.Bin(priceLow: 100, priceHigh: 101, volume: 0)]
        #expect(VolumeProfile.valueArea(bins: zeroBins) == nil)
        let okBins = [VolumeProfile.Bin(priceLow: 100, priceHigh: 101, volume: 10)]
        #expect(VolumeProfile.valueArea(bins: okBins, percent: 0) == nil)
    }

    @Test("valueArea · POC 在峰值 bin · VA 覆盖 ≥ 70%")
    func valueAreaCoversAtLeastSeventy() throws {
        // 5 个 bin 总 volume 100 · 峰值在 index=2 (40) · 阈值 70 → 至少含 2/3/1 三个 bin
        let bins = [
            VolumeProfile.Bin(priceLow: 100, priceHigh: 101, volume: 5),
            VolumeProfile.Bin(priceLow: 101, priceHigh: 102, volume: 25),
            VolumeProfile.Bin(priceLow: 102, priceHigh: 103, volume: 40),
            VolumeProfile.Bin(priceLow: 103, priceHigh: 104, volume: 20),
            VolumeProfile.Bin(priceLow: 104, priceHigh: 105, volume: 10),
        ]
        let va = try #require(VolumeProfile.valueArea(bins: bins, percent: 0.7))
        #expect(va.pocIndex == 2)
        #expect(va.coveredVolume >= 70)
        #expect(va.totalVolume == 100)
        // POC 一定在 VA 内
        #expect(va.valIndex <= va.pocIndex && va.pocIndex <= va.vahIndex)
        // VAH 价 > POC 价 > VAL 价
        #expect(va.vahPrice >= va.pocPrice && va.pocPrice >= va.valPrice)
    }

    @Test("valueArea · 单 bin 即覆盖全部 · VA 退化为该 bin")
    func valueAreaSingleBin() throws {
        let bins = [VolumeProfile.Bin(priceLow: 100, priceHigh: 101, volume: 50)]
        let va = try #require(VolumeProfile.valueArea(bins: bins))
        #expect(va.pocIndex == 0)
        #expect(va.vahIndex == 0 && va.valIndex == 0)
        #expect(va.coveredVolume == 50)
    }

    @Test("valueArea · 贪心方向：上侧 volume 更大优先扩展上")
    func valueAreaGreedyExpansion() throws {
        // POC=2(30)·两侧候选：上 3(25) vs 下 1(10) → 优先扩上
        let bins = [
            VolumeProfile.Bin(priceLow: 100, priceHigh: 101, volume: 5),
            VolumeProfile.Bin(priceLow: 101, priceHigh: 102, volume: 10),
            VolumeProfile.Bin(priceLow: 102, priceHigh: 103, volume: 30),
            VolumeProfile.Bin(priceLow: 103, priceHigh: 104, volume: 25),
            VolumeProfile.Bin(priceLow: 104, priceHigh: 105, volume: 5),
        ]
        let va = try #require(VolumeProfile.valueArea(bins: bins, percent: 0.7))
        // 总 75 · 阈值 52.5 · POC 30 + 上 25 = 55 ≥ 52.5 → vah=3, val=2
        #expect(va.pocIndex == 2)
        #expect(va.vahIndex == 3)
        #expect(va.valIndex == 2)
    }
}
