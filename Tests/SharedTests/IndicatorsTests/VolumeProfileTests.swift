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
}
