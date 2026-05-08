// 跨品种套利分析窗口（v15.27 · WP-套利分析 V1 MVP）
//
// 职责：
//   - 顶部 toolbar：预设 Picker（12 经典对）+ 周期 Picker
//   - 中部 Canvas：价差折线 + mean 中线 + ±2σ 通道（套利交易者必看）
//   - 底部 HUD：count / current / mean / std / zScore / percentile / range / upper/lower band
//
// 数据来源（v1）：mock 合成两腿 K 线 → SpreadCalculator → SpreadStatistics
// v2 计划：接入 SinaMarketData / 真 CTP 历史，对预设两腿都拉 K 线再计算

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore

// MARK: - 主窗口

struct SpreadWindow: View {

    @State private var selectedPairID: String = SpreadPresets.all.first?.id ?? "rb-hc"
    @State private var period: KLinePeriod = .minute15
    @State private var spreadValues: [SpreadValue] = []
    @State private var statistics: SpreadStatistics = .empty

    private var selectedPair: SpreadPair {
        SpreadPresets.byID[selectedPairID] ?? SpreadPresets.all.first!
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statisticsHUD
            Divider()
            spreadChart
        }
        .frame(minWidth: 920, minHeight: 540)
        .task(id: selectedPairID) { reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("套利对").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $selectedPairID) {
                    ForEach(SpreadPair.Category.allCases, id: \.self) { cat in
                        if let pairs = SpreadPresets.byCategory[cat], !pairs.isEmpty {
                            Section(cat.rawValue) {
                                ForEach(pairs) { pair in
                                    Text(pair.name).tag(pair.id)
                                }
                            }
                        }
                    }
                }
                .frame(width: 220)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("周期").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $period) {
                    Text("1 分").tag(KLinePeriod.minute1)
                    Text("15 分").tag(KLinePeriod.minute15)
                    Text("60 分").tag(KLinePeriod.hour1)
                    Text("日").tag(KLinePeriod.daily)
                }
                .frame(width: 100)
                .labelsHidden()
            }

            Spacer()

            Text("\(selectedPair.leg1.ratio > 0 ? "+" : "")\(selectedPair.leg1.ratio)·\(selectedPair.leg1.instrumentID) / \(selectedPair.leg2.ratio > 0 ? "+" : "")\(selectedPair.leg2.ratio)·\(selectedPair.leg2.instrumentID)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            Button {
                reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 统计 HUD

    private var statisticsHUD: some View {
        let s = statistics
        let zColor: Color = abs(NSDecimalNumber(decimal: s.zScore).doubleValue) > 2 ? .orange : .secondary
        return HStack(spacing: 22) {
            stat("点数", "\(s.count)", color: .secondary)
            stat("当前", fmt(s.current), color: .primary)
            stat("均值", fmt(s.mean), color: .secondary)
            stat("σ", fmt(s.stdDev), color: .secondary)
            stat("Z", String(format: "%.2f", NSDecimalNumber(decimal: s.zScore).doubleValue), color: zColor)
            stat("分位", String(format: "%.0f%%", s.percentile * 100), color: .secondary)
            Divider().frame(height: 24)
            stat("最低", fmt(s.min), color: .red)
            stat("最高", fmt(s.max), color: .green)
            stat("区间", fmt(s.range), color: .secondary)
            Divider().frame(height: 24)
            stat("+2σ", fmt(s.upperBand2σ), color: .orange.opacity(0.8))
            stat("-2σ", fmt(s.lowerBand2σ), color: .orange.opacity(0.8))
            Spacer()
            Text(selectedPair.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    // MARK: - 价差图

    private var spreadChart: some View {
        Canvas { ctx, size in
            drawSpread(ctx, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    private func drawSpread(_ ctx: GraphicsContext, size: CGSize) {
        guard spreadValues.count >= 2 else {
            let text = Text("等待数据 · \(spreadValues.count) 点")
                .font(.system(size: 12)).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        let values = spreadValues.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        let mean = NSDecimalNumber(decimal: statistics.mean).doubleValue
        let upper = NSDecimalNumber(decimal: statistics.upperBand2σ).doubleValue
        let lower = NSDecimalNumber(decimal: statistics.lowerBand2σ).doubleValue

        guard let minV = values.min(), let maxV = values.max() else { return }
        // 视图范围扩到 ±2σ + 价差极值（双方取宽）
        let vMin = min(minV, lower)
        let vMax = max(maxV, upper)
        let pad = max(0.01, (vMax - vMin) * 0.08)
        let viewMin = vMin - pad
        let viewMax = vMax + pad
        let viewRange = max(0.01, viewMax - viewMin)

        let n = values.count
        let step = (n > 1) ? size.width / CGFloat(n - 1) : size.width

        func yFor(_ v: Double) -> CGFloat {
            (1 - (v - viewMin) / viewRange) * size.height
        }

        // ±2σ 通道（橙色虚线）
        var upperLine = Path()
        upperLine.move(to: CGPoint(x: 0, y: yFor(upper)))
        upperLine.addLine(to: CGPoint(x: size.width, y: yFor(upper)))
        ctx.stroke(upperLine, with: .color(.orange.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        var lowerLine = Path()
        lowerLine.move(to: CGPoint(x: 0, y: yFor(lower)))
        lowerLine.addLine(to: CGPoint(x: size.width, y: yFor(lower)))
        ctx.stroke(lowerLine, with: .color(.orange.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        // 均值中线（白色虚线）
        var meanLine = Path()
        meanLine.move(to: CGPoint(x: 0, y: yFor(mean)))
        meanLine.addLine(to: CGPoint(x: size.width, y: yFor(mean)))
        ctx.stroke(meanLine, with: .color(.white.opacity(0.30)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 价差折线（cyan）
        var path = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: yFor(v))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(.cyan),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // 终点圆点
        let lastIdx = values.count - 1
        let lastPt = CGPoint(x: CGFloat(lastIdx) * step, y: yFor(values[lastIdx]))
        let dot = Path(ellipseIn: CGRect(x: lastPt.x - 3.5, y: lastPt.y - 3.5, width: 7, height: 7))
        ctx.fill(dot, with: .color(.cyan))
    }

    // MARK: - 数据加载

    private func reload() {
        let pair = selectedPair
        // v1 mock：合成两腿 K 线 · v2 接 SinaMarketData
        let leg1Bars = MockSpreadData.bars(
            instrumentID: pair.leg1.instrumentID,
            basePrice: defaultBasePrice(pair.leg1.instrumentID),
            period: period,
            count: 200
        )
        let leg2Bars = MockSpreadData.bars(
            instrumentID: pair.leg2.instrumentID,
            basePrice: defaultBasePrice(pair.leg2.instrumentID),
            period: period,
            count: 200,
            seed: pair.id.hashValue ^ 0x1F   // 第 2 腿不同 seed · 不完全相关
        )
        spreadValues = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1Bars, leg2Bars: leg2Bars)
        statistics = SpreadStatisticsCalculator.compute(spreadValues)
    }

    private func fmt(_ v: Decimal) -> String {
        let d = NSDecimalNumber(decimal: v).doubleValue
        if abs(d) >= 1000 { return String(format: "%.0f", d) }
        if abs(d) >= 10   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func defaultBasePrice(_ id: String) -> Double {
        // 复用 MockQuote.table（没用 import 简化 · v1 hardcoded 默认）
        switch id {
        case "RB0":  return 3245
        case "HC0":  return 3450
        case "J0":   return 1925
        case "JM0":  return 1180
        case "M0":   return 3180
        case "Y0":   return 8240
        case "P0":   return 8920
        case "OI0":  return 9180
        case "AU0":  return 612.5
        case "AG0":  return 7890
        case "CU0":  return 78650
        case "AL0":  return 19450
        case "IF0":  return 3856.4
        case "IH0":  return 2820.8
        case "IC0":  return 5680.2
        case "IM0":  return 6420.5
        case "T0":   return 104.85
        case "TF0":  return 103.42
        case "TS0":  return 101.85
        case "TL0":  return 108.20
        default:     return 1000
        }
    }
}

// MARK: - Mock 数据生成器

private enum MockSpreadData {
    /// 合成 K 线：random walk + 周期波动（让套利图有 mean-reverting 视觉效果）
    static func bars(
        instrumentID: String, basePrice: Double, period: KLinePeriod,
        count: Int = 200, seed: Int? = nil
    ) -> [KLine] {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed ?? instrumentID.hashValue)))
        let stepSec = TimeInterval(period.seconds)
        let baseTime = Date().addingTimeInterval(-Double(count) * stepSec)

        var price = basePrice
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        for i in 0..<count {
            // 周期 sin 波 + 小幅 random walk · 价差自然 mean-revert
            let cycle = sin(Double(i) * 0.1) * basePrice * 0.005
            let noise = rng.nextDouble(in: -0.002...0.002) * basePrice
            price = basePrice + cycle + noise + (price - basePrice) * 0.95
            let high = price + abs(noise) + 0.5
            let low = price - abs(noise) - 0.5
            bars.append(KLine(
                instrumentID: instrumentID, period: period,
                openTime: baseTime.addingTimeInterval(TimeInterval(i) * stepSec),
                open: Decimal(price - noise * 0.3),
                high: Decimal(high), low: Decimal(low), close: Decimal(price),
                volume: 100 + Int(abs(noise) * 100),
                openInterest: 0, turnover: 0
            ))
        }
        return bars
    }
}

// MARK: - 简单 seeded RNG（避免 SystemRandomNumberGenerator 跨预设 reload 同种）

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xCAFEBABE : seed }
    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let u = Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}

// MARK: - KLinePeriod helper

private extension KLinePeriod {
    var seconds: Int {
        switch self {
        case .minute1:  return 60
        case .minute5:  return 300
        case .minute15: return 900
        case .minute30: return 1800
        case .hour1:    return 3600
        case .daily:    return 86400
        default:        return 60
        }
    }
}

#endif
