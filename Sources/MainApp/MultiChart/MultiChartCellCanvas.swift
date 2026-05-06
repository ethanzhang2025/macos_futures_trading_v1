// WP-44 v15.23 batch51 · 多图表 cell 简化 K 线 mini-view（Canvas 直接画蜡烛）
//
// 设计要点：
// - 不接 ChartCore Metal · 自画 SwiftUI Canvas（轻量 · 多 cell 同屏不卡）
// - 不接 SinaMarketDataProvider 真数据（异步、网络复杂）· 用 mock 演示数据
// - 后续 batch 可接 MarketDataPipeline · 当前重点是 UI 框架闭环
//
// 渲染：
// - 主图蜡烛（OHLC）· 涨绿跌红 · 实体 + 上下影线
// - 底部成交量柱（showVolume 开关 · 占 25% 高度）
// - 网格背景（5 条横线 + 边框）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared

struct MultiChartCellCanvas: View {

    let bars: [KLine]
    let showVolume: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty else { return }

            let volumeHeight: CGFloat = showVolume ? size.height * 0.25 : 0
            let priceHeight = size.height - volumeHeight - 4
            let priceRect = CGRect(x: 0, y: 0, width: size.width, height: priceHeight)
            let volumeRect = CGRect(x: 0, y: priceHeight + 4, width: size.width, height: volumeHeight)

            drawGrid(in: ctx, rect: priceRect)
            drawCandles(in: ctx, rect: priceRect)
            if showVolume, volumeHeight > 8 {
                drawGrid(in: ctx, rect: volumeRect, lines: 2)
                drawVolumes(in: ctx, rect: volumeRect)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Grid

    private func drawGrid(in ctx: GraphicsContext, rect: CGRect, lines: Int = 5) {
        var path = Path()
        for i in 0...lines {
            let y = rect.minY + CGFloat(i) * rect.height / CGFloat(lines)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
    }

    // MARK: - Candles

    private func drawCandles(in ctx: GraphicsContext, rect: CGRect) {
        let opens = bars.map { (bars[0].open as NSDecimalNumber).doubleValue }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        _ = opens
        _ = closes

        let priceRange = maxHigh - minLow
        let n = bars.count
        let candleWidth = max(1.5, rect.width / CGFloat(n) * 0.7)

        for (i, bar) in bars.enumerated() {
            let open = (bar.open as NSDecimalNumber).doubleValue
            let close = (bar.close as NSDecimalNumber).doubleValue
            let high = (bar.high as NSDecimalNumber).doubleValue
            let low = (bar.low as NSDecimalNumber).doubleValue
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)

            let yFor = { (price: Double) -> CGFloat in
                rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
            }
            let isUp = close >= open
            let color: Color = isUp ? .red : .green   // 中国习惯：涨红跌绿
            let upper = max(open, close)
            let lower = min(open, close)

            // 上下影线
            var wickPath = Path()
            wickPath.move(to: CGPoint(x: centerX, y: yFor(high)))
            wickPath.addLine(to: CGPoint(x: centerX, y: yFor(low)))
            ctx.stroke(wickPath, with: .color(color), lineWidth: 1)

            // 实体
            let bodyTop = yFor(upper)
            let bodyHeight = max(1, yFor(lower) - bodyTop)
            let bodyRect = CGRect(
                x: centerX - candleWidth / 2,
                y: bodyTop,
                width: candleWidth,
                height: bodyHeight
            )
            if isUp {
                // 涨：实心红
                ctx.fill(Path(bodyRect), with: .color(color))
            } else {
                // 跌：填充实心绿（中国习惯）· 与上影线同色
                ctx.fill(Path(bodyRect), with: .color(color))
            }
        }
    }

    // MARK: - Volume

    private func drawVolumes(in ctx: GraphicsContext, rect: CGRect) {
        let volumes = bars.map { Double($0.volume) }
        guard let maxVol = volumes.max(), maxVol > 0 else { return }

        let n = bars.count
        let barWidth = max(1.5, rect.width / CGFloat(n) * 0.7)

        for (i, bar) in bars.enumerated() {
            let vol = Double(bar.volume)
            let h = CGFloat(vol / maxVol) * rect.height
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let close = (bar.close as NSDecimalNumber).doubleValue
            let open = (bar.open as NSDecimalNumber).doubleValue
            let color: Color = close >= open ? .red.opacity(0.6) : .green.opacity(0.6)
            let volRect = CGRect(
                x: centerX - barWidth / 2,
                y: rect.maxY - h,
                width: barWidth,
                height: h
            )
            ctx.fill(Path(volRect), with: .color(color))
        }
    }
}

// MARK: - Mock K 线生成（独立 cell · seed 按 instrumentID + period 决定 · 同 cell 稳定）

enum MultiChartMockData {

    /// 按 instrumentID + period 生成稳定 mock K 线（120 根 · 不同合约/周期波动幅度有差异）
    static func bars(instrumentID: String, period: KLinePeriod, count: Int = 120) -> [KLine] {
        let basePrice = basePriceFor(instrumentID)
        let volatility = volatilityFor(instrumentID, period: period)
        // 用 hashable 当 seed · 同 (id, period) 重新打开看到一样的图
        var rng = SeededRNG(seed: UInt64(abs(instrumentID.hashValue ^ period.rawValue.hashValue)))
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price = basePrice
        let secondsPerBar = max(60, period.seconds)
        for i in 0..<count {
            let drift = Double.random(in: -volatility...volatility, using: &rng)
            let open = price
            let close = max(basePrice * 0.5, price + drift)
            let wickRange = volatility * 0.6
            let high = max(open, close) + Double.random(in: 0...wickRange, using: &rng)
            let low = min(open, close) - Double.random(in: 0...wickRange, using: &rng)
            let volume = Int.random(in: 800...4000, using: &rng)
            bars.append(KLine(
                instrumentID: instrumentID,
                period: period,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * secondsPerBar)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: volume,
                openInterest: 0,
                turnover: 0
            ))
            price = close
        }
        return bars
    }

    private static func basePriceFor(_ id: String) -> Double {
        switch id {
        case "RB0":  return 3500
        case "IF0":  return 3800
        case "AU0":  return 480
        case "CU0":  return 70000
        case "I0":   return 800
        case "MA0":  return 16000
        default:     return 3000
        }
    }

    private static func volatilityFor(_ id: String, period: KLinePeriod) -> Double {
        let base = basePriceFor(id)
        let pctPerBar: Double
        switch period {
        case .minute1, .minute3, .minute5: pctPerBar = 0.0015
        case .minute15, .minute30:         pctPerBar = 0.003
        case .hour1, .hour2:               pctPerBar = 0.005
        case .hour4, .daily:               pctPerBar = 0.01
        default:                           pctPerBar = 0.002
        }
        return base * pctPerBar
    }

    /// 简单 LCG · 给同 (id, period) 稳定结果（@AppStorage 重启看到一样的图）
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed | 1 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

#endif
