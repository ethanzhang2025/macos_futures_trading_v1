// 期权工作台窗口（v15.32 · 期权 Phase 5 · UI 收尾）
//
// 4 大区块（垂直分割）：
//   1. 顶部 toolbar：标的 Picker（IO/m/SR）+ 到期 Picker + 现价/利率/IV 输入
//   2. T 型期权链表格（同到期 · CALL 在左 · STRIKE 中 · PUT 在右 · ATM 行高亮）
//      每行展示：bid/ask/last(占位) + 理论价 + IV + Δ + Γ + Θ
//   3. 选中合约 / 策略 → 实时 Greeks HUD
//   4. 底部策略 PnL 曲线（Canvas · 5 种预设构造按钮）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore

// MARK: - 主窗口

struct OptionWindow: View {

    @State private var selectedUnderlyingID: String = "IO"
    @State private var selectedExpirationIndex: Int = 0
    @State private var spotPrice: Double = 3856
    @State private var riskFreeRate: Double = 0.03
    @State private var assumedVol: Double = 0.20

    @State private var selectedStrategyType: StrategyType = .bullCallSpread
    @State private var strategyLowStrike: Double = 3800
    @State private var strategyHighStrike: Double = 3950
    @State private var strategyMidStrike: Double = 3850

    private var meta: OptionPresets.UnderlyingMeta? {
        OptionPresets.byUnderlyingID[selectedUnderlyingID]
    }

    private var chain: OptionChain? {
        OptionPresets.sampleChain(for: selectedUnderlyingID)
    }

    private var selectedSlice: OptionChainSlice? {
        guard let chain = chain, !chain.slices.isEmpty else { return nil }
        let idx = max(0, min(selectedExpirationIndex, chain.slices.count - 1))
        return chain.slices[idx]
    }

    private var bsContext: OptionStrategyBuilder.Context? {
        guard let chain = chain else { return nil }
        return OptionStrategyBuilder.Context(
            chain: chain, spotPrice: spotPrice,
            riskFreeRate: riskFreeRate, volatility: assumedVol
        )
    }

    private var currentStrategy: OptionStrategy? {
        guard let ctx = bsContext, let slice = selectedSlice else { return nil }
        let exp = slice.expirationDate
        switch selectedStrategyType {
        case .bullCallSpread:
            return OptionStrategyBuilder.bullCallSpread(
                context: ctx, lowStrike: strategyLowStrike, highStrike: strategyHighStrike, expiration: exp
            )
        case .bearPutSpread:
            return OptionStrategyBuilder.bearPutSpread(
                context: ctx, lowStrike: strategyLowStrike, highStrike: strategyHighStrike, expiration: exp
            )
        case .longStraddle:
            return OptionStrategyBuilder.longStraddle(
                context: ctx, strike: strategyMidStrike, expiration: exp
            )
        case .longStrangle:
            return OptionStrategyBuilder.longStrangle(
                context: ctx, lowStrike: strategyLowStrike, highStrike: strategyHighStrike, expiration: exp
            )
        case .longButterfly:
            return OptionStrategyBuilder.longButterfly(
                context: ctx, lowStrike: strategyLowStrike, midStrike: strategyMidStrike,
                highStrike: strategyHighStrike, expiration: exp
            )
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                optionChainTable
                    .frame(minWidth: 580)
                Divider()
                strategyPanel
                    .frame(width: 360)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onChange(of: selectedUnderlyingID) { _, _ in resetForNewUnderlying() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("标的").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $selectedUnderlyingID) {
                    ForEach(OptionPresets.underlyings, id: \.id) { meta in
                        Text("\(meta.name)（\(meta.id)）").tag(meta.id)
                    }
                }
                .frame(width: 200)
                .labelsHidden()
            }

            if let chain = chain {
                HStack(spacing: 6) {
                    Text("到期").font(.callout).foregroundColor(.secondary)
                    Picker("", selection: $selectedExpirationIndex) {
                        ForEach(chain.slices.indices, id: \.self) { idx in
                            let slice = chain.slices[idx]
                            Text("\(slice.daysToExpiration()) 天").tag(idx)
                        }
                    }
                    .frame(width: 120)
                    .labelsHidden()
                }
            }

            HStack(spacing: 6) {
                Text("现价").font(.callout).foregroundColor(.secondary)
                TextField("", value: $spotPrice, format: .number.precision(.fractionLength(2)))
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                Text("利率").font(.callout).foregroundColor(.secondary)
                TextField("", value: $riskFreeRate, format: .percent.precision(.fractionLength(1)))
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                Text("IV").font(.callout).foregroundColor(.secondary)
                TextField("", value: $assumedVol, format: .percent.precision(.fractionLength(0)))
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            Text(meta.map { "\($0.exchange.displayName) · \($0.exerciseStyle.displayName) · \($0.multiplier)/张" } ?? "")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 期权链表格

    private var optionChainTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                cellHeader("CALL Δ", w: 60)
                cellHeader("CALL Γ", w: 60)
                cellHeader("CALL Θ/天", w: 70)
                cellHeader("CALL 理论", w: 70)
                cellHeader("STRIKE", w: 70).background(Color.secondary.opacity(0.12))
                cellHeader("PUT 理论", w: 70)
                cellHeader("PUT Δ", w: 60)
                cellHeader("PUT Γ", w: 60)
                cellHeader("PUT Θ/天", w: 70)
                Spacer()
            }
            .background(Color.secondary.opacity(0.06))
            .frame(height: 28)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let slice = selectedSlice, let ctx = bsContext {
                        ForEach(slice.rows.indices, id: \.self) { idx in
                            let row = slice.rows[idx]
                            optionChainRowView(row: row, slice: slice, ctx: ctx)
                        }
                    }
                }
            }
        }
    }

    private func optionChainRowView(
        row: OptionChainRow, slice: OptionChainSlice, ctx: OptionStrategyBuilder.Context
    ) -> some View {
        let strikeD = NSDecimalNumber(decimal: row.strikePrice).doubleValue
        let isATM = abs(strikeD - spotPrice) <= (meta.map { NSDecimalNumber(decimal: $0.strikeStep).doubleValue } ?? 1) * 0.5
        let T = max(Double(slice.daysToExpiration()) / 365.0, 1e-6)
        let bsInputs = BlackScholes.Inputs(
            spotPrice: ctx.spotPrice, strikePrice: strikeD,
            timeToExpirationYears: T, riskFreeRate: ctx.riskFreeRate,
            volatility: ctx.volatility, dividendYield: ctx.dividendYield
        )
        let cGreeks = OptionGreeks.compute(type: .call, inputs: bsInputs)
        let cPrice = BlackScholes.price(type: .call, inputs: bsInputs)
        let pGreeks = OptionGreeks.compute(type: .put, inputs: bsInputs)
        let pPrice = BlackScholes.price(type: .put, inputs: bsInputs)

        return HStack(spacing: 0) {
            cellNumeric(cGreeks.delta, fmt: "%.3f", w: 60, color: cellColor(forStrike: strikeD, isCall: true, atSpot: spotPrice))
            cellNumeric(cGreeks.gamma, fmt: "%.4f", w: 60)
            cellNumeric(cGreeks.theta / 365, fmt: "%.2f", w: 70, color: .red.opacity(0.8))
            cellNumeric(cPrice, fmt: "%.2f", w: 70, color: .primary)
            cellNumeric(strikeD, fmt: "%.0f", w: 70,
                        color: .primary, bold: true)
                .background(isATM ? Color.yellow.opacity(0.15) : Color.secondary.opacity(0.06))
            cellNumeric(pPrice, fmt: "%.2f", w: 70, color: .primary)
            cellNumeric(pGreeks.delta, fmt: "%.3f", w: 60, color: cellColor(forStrike: strikeD, isCall: false, atSpot: spotPrice))
            cellNumeric(pGreeks.gamma, fmt: "%.4f", w: 60)
            cellNumeric(pGreeks.theta / 365, fmt: "%.2f", w: 70, color: .red.opacity(0.8))
            Spacer()
        }
        .frame(height: 24)
        .background(isATM ? Color.yellow.opacity(0.05) : Color.clear)
    }

    private func cellHeader(_ text: String, w: CGFloat) -> some View {
        Text(text).font(.caption2).foregroundColor(.secondary)
            .frame(width: w, alignment: .center)
    }

    private func cellNumeric(_ v: Double, fmt: String, w: CGFloat,
                              color: Color = .secondary, bold: Bool = false) -> some View {
        Text(String(format: fmt, v))
            .font(.system(size: 11, design: .monospaced).weight(bold ? .bold : .regular))
            .foregroundColor(color)
            .frame(width: w, alignment: .trailing)
            .padding(.horizontal, 4)
    }

    private func cellColor(forStrike strike: Double, isCall: Bool, atSpot spot: Double) -> Color {
        let isITM = isCall ? (strike < spot) : (strike > spot)
        return isITM ? .green.opacity(0.85) : .secondary
    }

    // MARK: - 策略面板

    private var strategyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            strategyToolbar
            Divider()
            strategyHUD
            Divider()
            strategyPnLChart
        }
    }

    private var strategyToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("策略", selection: $selectedStrategyType) {
                Text("牛市价差").tag(StrategyType.bullCallSpread)
                Text("熊市价差").tag(StrategyType.bearPutSpread)
                Text("长跨式").tag(StrategyType.longStraddle)
                Text("长宽跨式").tag(StrategyType.longStrangle)
                Text("蝶式").tag(StrategyType.longButterfly)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                strikeField("低", $strategyLowStrike)
                strikeField("中", $strategyMidStrike)
                strikeField("高", $strategyHighStrike)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func strikeField(_ label: String, _ binding: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            TextField("", value: binding, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var strategyHUD: some View {
        let s = currentStrategy
        let analysis = s.map { OptionPayoffAnalyzer.analyze(strategy: $0) }
        return VStack(alignment: .leading, spacing: 6) {
            if let s = s {
                Text(s.name).font(.callout.bold())
                HStack(spacing: 16) {
                    statBlock("净权利金", String(format: "%.2f", s.netPremium),
                             color: s.netPremium > 0 ? .red : .green)
                    statBlock("最大利润",
                             analysis?.isMaxProfitUnlimited == true ? "∞" : String(format: "%.2f", analysis?.maxProfit ?? 0),
                             color: .green)
                    statBlock("最大亏损",
                             analysis?.isMaxLossUnlimited == true ? "∞" : String(format: "%.2f", analysis?.maxLoss ?? 0),
                             color: .red)
                }
                Text("损益平衡：\(analysis?.breakevens.map { String(format: "%.1f", $0) }.joined(separator: " · ") ?? "—")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("策略构造失败 · 检查 strike 是否在期权链中").font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    private var strategyPnLChart: some View {
        Canvas { ctx, size in
            drawPnLChart(ctx, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    private func drawPnLChart(_ ctx: GraphicsContext, size: CGSize) {
        guard let s = currentStrategy else {
            let text = Text("无策略").font(.system(size: 12)).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let analysis = OptionPayoffAnalyzer.analyze(strategy: s, sampleCount: 200)
        guard !analysis.curve.isEmpty else { return }

        let pnls = analysis.curve.map { $0.pnl }
        let spots = analysis.curve.map { $0.spotPrice }
        guard let minP = pnls.min(), let maxP = pnls.max(),
              let minS = spots.min(), let maxS = spots.max() else { return }
        let pad = max(0.01, (maxP - minP) * 0.10)
        let viewMin = minP - pad
        let viewMax = maxP + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = size.width / CGFloat(analysis.curve.count - 1)
        let xRange = maxS - minS

        func yFor(_ p: Double) -> CGFloat {
            (1 - (p - viewMin) / viewRange) * size.height
        }
        func xFor(_ s: Double) -> CGFloat {
            CGFloat((s - minS) / xRange) * size.width
        }

        // 零线（白虚线）
        if viewMin < 0 && viewMax > 0 {
            var zeroPath = Path()
            zeroPath.move(to: CGPoint(x: 0, y: yFor(0)))
            zeroPath.addLine(to: CGPoint(x: size.width, y: yFor(0)))
            ctx.stroke(zeroPath, with: .color(.white.opacity(0.30)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // 当前现价垂线（cyan 虚）
        if spotPrice >= minS && spotPrice <= maxS {
            var spotLine = Path()
            spotLine.move(to: CGPoint(x: xFor(spotPrice), y: 0))
            spotLine.addLine(to: CGPoint(x: xFor(spotPrice), y: size.height))
            ctx.stroke(spotLine, with: .color(.cyan.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // breakeven 垂线（橙）
        for be in analysis.breakevens {
            guard be >= minS && be <= maxS else { continue }
            var line = Path()
            line.move(to: CGPoint(x: xFor(be), y: 0))
            line.addLine(to: CGPoint(x: xFor(be), y: size.height))
            ctx.stroke(line, with: .color(.orange.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // PnL 折线（盈利绿 / 亏损红 · 分段填色）
        for i in 0..<(analysis.curve.count - 1) {
            let p1 = analysis.curve[i]
            let p2 = analysis.curve[i + 1]
            let x1 = CGFloat(i) * xStep
            let x2 = CGFloat(i + 1) * xStep
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(p1.pnl)))
            seg.addLine(to: CGPoint(x: x2, y: yFor(p2.pnl)))
            let color: Color = (p1.pnl >= 0 && p2.pnl >= 0) ? .green
                              : (p1.pnl < 0 && p2.pnl < 0) ? .red
                              : .yellow
            ctx.stroke(seg, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: - 切换标的时重置

    private func resetForNewUnderlying() {
        selectedExpirationIndex = 0
        if let m = meta {
            spotPrice = NSDecimalNumber(decimal: m.spotPrice).doubleValue
            let step = NSDecimalNumber(decimal: m.strikeStep).doubleValue
            strategyLowStrike = round((spotPrice - 2 * step) / step) * step
            strategyMidStrike = round(spotPrice / step) * step
            strategyHighStrike = round((spotPrice + 2 * step) / step) * step
        }
    }
}

#endif
