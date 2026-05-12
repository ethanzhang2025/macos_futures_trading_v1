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
import ChartCore

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
    /// 第 4 个 strike · 仅铁鹰用（callHighStrike · K4）
    @State private var strategyExtraStrike: Double = 4000
    /// v15.36 · 期权 Phase 6.4 · 回测 sheet 显隐
    @State private var backtestSheetPresented: Bool = false
    /// v15.40 · PnL 图 hover（鼠标在 strategyPnLChart 内的像素 · nil = 离开）
    @State private var pnlHoverPoint: CGPoint?
    /// v15.42 · IV smile 副图 hover（鼠标在 ivSmileChart 内的像素 · nil = 离开）
    @State private var ivSmileHoverPoint: CGPoint?
    /// v15.42 · IV smile 翼端 skew（笑容陡峭度 · 0=无 smile / 0.5=典型笑 / 1=极端 skew）
    @State private var ivSmileSkew: Double = 0.5

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
        case .ironCondor:
            // 4 strike 映射：low=putLow(K1) · mid=putHigh(K2) · high=callLow(K3) · extra=callHigh(K4)
            return OptionStrategyBuilder.ironCondor(
                context: ctx,
                putLowStrike:   strategyLowStrike,
                putHighStrike:  strategyMidStrike,
                callLowStrike:  strategyHighStrike,
                callHighStrike: strategyExtraStrike,
                expiration: exp
            )
        case .coveredCall:
            // 单 strike：mid 用作 callStrike（OTM Call）· 标的入场默认现价
            return OptionStrategyBuilder.coveredCall(
                context: ctx, callStrike: strategyMidStrike, expiration: exp
            )
        case .protectivePut:
            // 单 strike：mid 用作 putStrike（OTM Put）· 标的入场默认现价
            return OptionStrategyBuilder.protectivePut(
                context: ctx, putStrike: strategyMidStrike, expiration: exp
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
        .onChange(of: selectedUnderlyingID) { _ in resetForNewUnderlying() }
        .onChange(of: selectedStrategyType) { newType in remapStrikesForStrategy(newType) }
        // v17.95 · 接 watchlistInstrumentSelected · 当主图切到 IO / m / SR 等期权标的时同步
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            guard let id = note.object as? String,
                  OptionPresets.byUnderlyingID[id] != nil,
                  id != selectedUnderlyingID
            else { return }
            selectedUnderlyingID = id
        }
        // v15.36 · Phase 6.4 · 回测 sheet
        .sheet(isPresented: $backtestSheetPresented) {
            if let s = currentStrategy {
                OptionBacktestSheet(strategy: s, isPresented: $backtestSheetPresented)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32)).foregroundColor(.orange)
                    Text("无有效策略 · 请先在工作台选 strike 构造策略")
                        .font(.callout)
                    Button("关闭") { backtestSheetPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(40).frame(width: 360)
            }
        }
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
            // 表头（v17.35 C2 加 Vega / Rho 两列 · 5 Greeks 完整）
            HStack(spacing: 0) {
                cellHeader("CALL Δ", w: 60)
                cellHeader("CALL Γ", w: 60)
                cellHeader("CALL ν", w: 60)
                cellHeader("CALL Θ/天", w: 70)
                cellHeader("CALL ρ", w: 60)
                cellHeader("CALL 理论", w: 70)
                cellHeader("STRIKE", w: 70).background(Color.secondary.opacity(0.12))
                cellHeader("PUT 理论", w: 70)
                cellHeader("PUT Δ", w: 60)
                cellHeader("PUT Γ", w: 60)
                cellHeader("PUT ν", w: 60)
                cellHeader("PUT Θ/天", w: 70)
                cellHeader("PUT ρ", w: 60)
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
            // v17.35 C2 · Vega 每 1% 波动 · Rho 每 1% 利率（compute 输出按 100% · 这里 / 100 转 per-1%）
            cellNumeric(cGreeks.vega / 100, fmt: "%.3f", w: 60, color: .purple.opacity(0.8))
            cellNumeric(cGreeks.theta / 365, fmt: "%.2f", w: 70, color: .red.opacity(0.8))
            cellNumeric(cGreeks.rho / 100, fmt: "%.4f", w: 60, color: .blue.opacity(0.7))
            cellNumeric(cPrice, fmt: "%.2f", w: 70, color: .primary)
            cellNumeric(strikeD, fmt: "%.0f", w: 70,
                        color: .primary, bold: true)
                .background(isATM ? Color.yellow.opacity(0.15) : Color.secondary.opacity(0.06))
            cellNumeric(pPrice, fmt: "%.2f", w: 70, color: .primary)
            cellNumeric(pGreeks.delta, fmt: "%.3f", w: 60, color: cellColor(forStrike: strikeD, isCall: false, atSpot: spotPrice))
            cellNumeric(pGreeks.gamma, fmt: "%.4f", w: 60)
            cellNumeric(pGreeks.vega / 100, fmt: "%.3f", w: 60, color: .purple.opacity(0.8))
            cellNumeric(pGreeks.theta / 365, fmt: "%.2f", w: 70, color: .red.opacity(0.8))
            cellNumeric(pGreeks.rho / 100, fmt: "%.4f", w: 60, color: .blue.opacity(0.7))
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
                .frame(maxHeight: .infinity)
            Divider()
            ivSmileToolbar
            ivSmileChart
                .frame(height: 160)
        }
    }

    /// IV smile 顶部工具条（skew 可调 · 0.0-1.0）
    private var ivSmileToolbar: some View {
        HStack(spacing: 10) {
            Text("IV smile").font(.caption.bold()).foregroundColor(.secondary)
            Spacer()
            Text("skew").font(.caption2).foregroundColor(.secondary)
            Stepper(value: $ivSmileSkew, in: 0.0...1.0, step: 0.1) {
                Text(String(format: "%.1f", ivSmileSkew))
                    .font(.caption.monospaced())
                    .frame(minWidth: 28)
            }
            .frame(width: 110)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var strategyToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("策略", selection: $selectedStrategyType) {
                Text("牛市价差").tag(StrategyType.bullCallSpread)
                Text("熊市价差").tag(StrategyType.bearPutSpread)
                Text("长跨式").tag(StrategyType.longStraddle)
                Text("长宽跨式").tag(StrategyType.longStrangle)
                Text("蝶式").tag(StrategyType.longButterfly)
                Text("铁鹰").tag(StrategyType.ironCondor)
                Text("备兑").tag(StrategyType.coveredCall)
                Text("护跌").tag(StrategyType.protectivePut)
            }
            .pickerStyle(.segmented)

            switch selectedStrategyType {
            case .ironCondor:
                // 铁鹰 4 strike：K1<K2<K3<K4
                HStack(spacing: 8) {
                    strikeField("PutK1", $strategyLowStrike)
                    strikeField("PutK2", $strategyMidStrike)
                    strikeField("CallK3", $strategyHighStrike)
                    strikeField("CallK4", $strategyExtraStrike)
                }
            case .coveredCall, .protectivePut:
                // 单 strike + 标的入场提示
                HStack(spacing: 8) {
                    strikeField(selectedStrategyType == .coveredCall ? "Call K" : "Put K",
                                $strategyMidStrike)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("标的入场").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.2f", spotPrice))
                            .font(.callout.monospaced())
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            default:
                HStack(spacing: 8) {
                    strikeField("低", $strategyLowStrike)
                    strikeField("中", $strategyMidStrike)
                    strikeField("高", $strategyHighStrike)
                }
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
                HStack {
                    Text(s.name).font(.callout.bold())
                    Spacer()
                    Button {
                        backtestSheetPresented = true
                    } label: {
                        Label("回测", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .tooltip("跑历史回测 · PnL 曲线 + maxDD + Sharpe + 胜率")
                }
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
        GeometryReader { geom in
            ZStack {
                Canvas { ctx, size in
                    drawPnLChart(ctx, size: size)
                }
                .background(ChartTheme.dark.background)

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): pnlHoverPoint = pt
                        case .ended: pnlHoverPoint = nil
                        }
                    }

                if let pt = pnlHoverPoint, let s = currentStrategy {
                    let analysis = OptionPayoffAnalyzer.analyze(strategy: s, sampleCount: 200)
                    if !analysis.curve.isEmpty,
                       let info = optionHoverInfo(at: pt, in: geom.size, analysis: analysis) {
                        optionCrosshair(at: pt, snapX: info.snapX, in: geom.size)
                        optionHoverTooltip(info: info, strategy: s, analysis: analysis)
                            .position(tooltipPosition(near: pt, in: geom.size,
                                                      tooltipSize: CGSize(width: 220, height: 175)))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// PnL 图 hover 信息
    private struct OptionPnLHoverInfo {
        let index: Int
        let spotPrice: Double
        let pnl: Double
        let snapX: CGFloat   // 视觉对齐到 sample 上
    }

    private func optionHoverInfo(
        at pt: CGPoint, in size: CGSize, analysis: PayoffAnalysis
    ) -> OptionPnLHoverInfo? {
        guard let i = ChartHitTester.barIndex(
            atX: pt.x, width: size.width, barCount: analysis.curve.count
        ) else { return nil }
        let n = analysis.curve.count
        let xStep = (n > 1) ? size.width / CGFloat(n - 1) : size.width
        let snapX = CGFloat(i) * xStep
        return OptionPnLHoverInfo(
            index: i,
            spotPrice: analysis.curve[i].spotPrice,
            pnl: analysis.curve[i].pnl,
            snapX: snapX
        )
    }

    private func optionCrosshair(at pt: CGPoint, snapX: CGFloat, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: snapX, y: 0))
            p.addLine(to: CGPoint(x: snapX, y: size.height))
        }
        .stroke(ChartTheme.crosshairLine,
                style: StrokeStyle(lineWidth: ChartTheme.crosshairLineWidth, dash: ChartTheme.crosshairDash))
        .allowsHitTesting(false)
    }

    private func optionHoverTooltip(
        info: OptionPnLHoverInfo, strategy: OptionStrategy, analysis: PayoffAnalysis
    ) -> some View {
        let pnlColor: Color = info.pnl > 0 ? ChartTheme.chartProfit
                            : (info.pnl < 0 ? ChartTheme.chartLoss : ChartTheme.chartTransition)
        let diffSpot = info.spotPrice - spotPrice
        // 最近 breakeven 距离（绝对值最小）
        let nearestBE = analysis.breakevens.min(by: { abs($0 - info.spotPrice) < abs($1 - info.spotPrice) })
        let beText: String
        if let be = nearestBE {
            let d = info.spotPrice - be
            beText = String(format: "%@%.2f", d >= 0 ? "+" : "", d)
        } else {
            beText = "—"
        }
        // 各 leg ITM 状态（hover spot 下）
        let legSummary = strategy.legs.map { leg -> String in
            let strike = NSDecimalNumber(decimal: leg.contract.strikePrice).doubleValue
            let isITM: Bool
            switch leg.contract.type {
            case .call: isITM = info.spotPrice > strike
            case .put:  isITM = info.spotPrice < strike
            }
            let cp = leg.contract.type == .call ? "C" : "P"
            let sd = leg.direction == .long ? "+" : "-"
            return "\(sd)\(cp)\(String(format: "%.0f", strike))\(isITM ? "✓" : "·")"
        }.joined(separator: " ")
        let isAtSpot = abs(info.spotPrice - spotPrice) < (analysis.curve.count > 1
            ? (analysis.curve.last!.spotPrice - analysis.curve.first!.spotPrice) / Double(analysis.curve.count - 1) * 1.5
            : 0.01)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(format: "spot %.2f", info.spotPrice))
                    .font(ChartTheme.fontValueBold)
                    .foregroundColor(ChartTheme.chartLine)
                if isAtSpot {
                    Text("≈现价")
                        .font(ChartTheme.fontHint)
                        .foregroundColor(ChartTheme.chartLine.opacity(0.7))
                }
            }
            Text("点 #\(info.index + 1) / \(analysis.curve.count)")
                .font(ChartTheme.fontSubvalue)
                .foregroundColor(ChartTheme.tooltipMuted)
            Divider().background(ChartTheme.tooltipDivider)
            optionTooltipRow("PnL", String(format: "%+.2f", info.pnl), color: pnlColor)
            optionTooltipRow("距现价", String(format: "%@%.2f", diffSpot >= 0 ? "+" : "", diffSpot),
                             color: diffSpot >= 0 ? ChartTheme.chartProfitEmphasized : ChartTheme.chartLossEmphasized)
            optionTooltipRow("距盈亏点", beText,
                             color: nearestBE.map { abs(info.spotPrice - $0) < 1 ? ChartTheme.chartTransition : ChartTheme.tooltipSecondary } ?? .secondary)
            Divider().background(ChartTheme.tooltipDivider)
            HStack {
                Text("Leg")
                    .font(ChartTheme.fontLabel)
                    .foregroundColor(ChartTheme.tooltipLabel)
                    .frame(width: 32, alignment: .leading)
                Text(legSummary)
                    .font(ChartTheme.fontSubvalue)
                    .foregroundColor(ChartTheme.tooltipSecondary)
                Spacer()
            }
            Text("✓=ITM · ·=OTM · +=买 · -=卖")
                .font(ChartTheme.fontHint)
                .foregroundColor(ChartTheme.tooltipDimmed)
        }
        .padding(ChartTheme.tooltipPadding)
        .frame(width: 220, alignment: .leading)
        .background(ChartTheme.tooltipBackground)
        .cornerRadius(ChartTheme.tooltipCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: ChartTheme.tooltipCornerRadius)
                    .stroke(ChartTheme.tooltipBorder, lineWidth: ChartTheme.tooltipBorderWidth))
    }

    private func optionTooltipRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ChartTheme.fontLabel)
                .foregroundColor(ChartTheme.tooltipLabel)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(ChartTheme.fontValue)
                .foregroundColor(color)
            Spacer()
        }
    }

    private func tooltipPosition(near pt: CGPoint, in size: CGSize, tooltipSize: CGSize) -> CGPoint {
        let dx: CGFloat = pt.x + 12 + tooltipSize.width / 2 < size.width
            ? tooltipSize.width / 2 + 12
            : -tooltipSize.width / 2 - 12
        let dy: CGFloat = pt.y + 12 + tooltipSize.height / 2 < size.height
            ? tooltipSize.height / 2 + 12
            : -tooltipSize.height / 2 - 12
        return CGPoint(x: pt.x + dx, y: pt.y + dy)
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
            ctx.stroke(zeroPath, with: .color(ChartTheme.chartLineSecondary),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // 当前现价垂线（cyan 虚）
        if spotPrice >= minS && spotPrice <= maxS {
            var spotLine = Path()
            spotLine.move(to: CGPoint(x: xFor(spotPrice), y: 0))
            spotLine.addLine(to: CGPoint(x: xFor(spotPrice), y: size.height))
            ctx.stroke(spotLine, with: .color(ChartTheme.chartSpotLine),
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
            let color: Color = (p1.pnl >= 0 && p2.pnl >= 0) ? ChartTheme.chartProfitEmphasized
                              : (p1.pnl < 0 && p2.pnl < 0) ? ChartTheme.chartLossEmphasized
                              : ChartTheme.chartTransition.opacity(0.85)
            ctx.stroke(seg, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: - 切换标的时重置

    private func resetForNewUnderlying() {
        selectedExpirationIndex = 0
        if let m = meta {
            spotPrice = NSDecimalNumber(decimal: m.spotPrice).doubleValue
            let step = NSDecimalNumber(decimal: m.strikeStep).doubleValue
            // 通用 3 strike：low=ATM-2step / mid=ATM / high=ATM+2step（蝶式等距 / 牛熊价差合理）
            strategyLowStrike  = round((spotPrice - 2 * step) / step) * step
            strategyMidStrike  = round(spotPrice / step) * step
            strategyHighStrike = round((spotPrice + 2 * step) / step) * step
            // 铁鹰用：切到铁鹰时按 K1<K2<K3<K4 重映射 · 见 onChange(of: selectedStrategyType)
            strategyExtraStrike = round((spotPrice + 4 * step) / step) * step
        }
    }

    /// 切策略时 · 把 strike 按各策略经典布局重新铺开
    /// - 铁鹰：K1<K2<K3<K4 围绕 ATM 对称
    /// - 备兑：mid = ATM + step（OTM Call · 卖虚一档）
    /// - 护跌：mid = ATM - step（OTM Put · 买虚一档）
    /// - 其他：low/mid/high 围绕 ATM 对称（蝶式等距 / 牛熊价差合理）
    private func remapStrikesForStrategy(_ type: StrategyType) {
        guard let m = meta else { return }
        let step = NSDecimalNumber(decimal: m.strikeStep).doubleValue
        let atm = round(spotPrice / step) * step
        switch type {
        case .ironCondor:
            strategyLowStrike   = atm - 2 * step    // PutK1
            strategyMidStrike   = atm - step        // PutK2
            strategyHighStrike  = atm + step        // CallK3
            strategyExtraStrike = atm + 2 * step    // CallK4
        case .coveredCall:
            strategyMidStrike = atm + step          // 卖虚一档 Call
        case .protectivePut:
            strategyMidStrike = atm - step          // 买虚一档 Put
        default:
            strategyLowStrike  = atm - 2 * step
            strategyMidStrike  = atm
            strategyHighStrike = atm + 2 * step
        }
    }

    // MARK: - v15.42 · IV smile 副图（trader 看波动率结构）

    /// IV smile mock 公式（笑容形状 · 远 ATM IV 高 / ATM 低）
    /// - Parameter strike: 行权价
    /// - Parameter spot: 标的现价
    /// - Parameter baseIV: ATM 平价 IV（用户输入的 assumedVol）
    /// - Parameter skew: 翼端陡峭度（0=flat / 0.5=典型笑 / 1=极端）
    /// - Returns: 该 strike 处的 IV
    private func mockSmileIV(strike: Double, spot: Double, baseIV: Double, skew: Double) -> Double {
        guard spot > 0, strike > 0 else { return baseIV }
        let m = log(strike / spot)               // log-moneyness
        // 二次型 + 偏斜：左翼（K<S）IV 高 +0.05 · 右翼（K>S）IV 低 -0.02（put skew · 经典股票）
        let curvature = skew * m * m * 4         // 笑容曲率 ∝ m²
        let putSkew = m < 0 ? skew * (-m) * 0.30 : -skew * m * 0.10
        return max(0.01, baseIV * (1 + curvature) + putSkew)
    }

    private var ivSmileChart: some View {
        GeometryReader { geom in
            ZStack {
                Canvas { ctx, size in
                    drawIVSmile(ctx: ctx, size: size)
                }
                .background(ChartTheme.dark.background)

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): ivSmileHoverPoint = pt
                        case .ended: ivSmileHoverPoint = nil
                        }
                    }

                if let pt = ivSmileHoverPoint, let slice = selectedSlice, !slice.rows.isEmpty,
                   let info = ivSmileHoverInfo(at: pt, in: geom.size, slice: slice) {
                    ivSmileCrosshair(at: pt, snapX: info.snapX, in: geom.size)
                    ivSmileTooltip(info: info)
                        .position(tooltipPosition(near: pt, in: geom.size,
                                                   tooltipSize: CGSize(width: 200, height: 130)))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func drawIVSmile(ctx: GraphicsContext, size: CGSize) {
        guard let slice = selectedSlice, !slice.rows.isEmpty else {
            let text = Text("无期权链 · IV smile 不可用")
                .font(ChartTheme.fontSubvalue).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let rows = slice.rows
        let strikes = rows.map { NSDecimalNumber(decimal: $0.strikePrice).doubleValue }
        guard let minK = strikes.min(), let maxK = strikes.max(), maxK > minK else { return }

        // 双线：call IV (cyan) · put IV (orange) · ATM 处吻合
        let callIVs = strikes.map { mockSmileIV(strike: $0, spot: spotPrice, baseIV: assumedVol, skew: ivSmileSkew) }
        let putIVs  = strikes.map { mockSmileIV(strike: $0, spot: spotPrice, baseIV: assumedVol, skew: ivSmileSkew) + 0.005 }

        let allIVs = callIVs + putIVs
        guard let minIV = allIVs.min(), let maxIV = allIVs.max(), maxIV > minIV else { return }
        let pad = max(0.005, (maxIV - minIV) * 0.15)
        let viewMinIV = minIV - pad
        let viewMaxIV = maxIV + pad
        let viewRangeIV = viewMaxIV - viewMinIV
        let kRange = maxK - minK

        func xFor(_ k: Double) -> CGFloat { CGFloat((k - minK) / kRange) * size.width }
        func yFor(_ iv: Double) -> CGFloat {
            CGFloat(1 - (iv - viewMinIV) / viewRangeIV) * (size.height - 22) + 16
        }

        // 现价垂线（cyan 虚）
        if spotPrice >= minK && spotPrice <= maxK {
            var line = Path()
            line.move(to: CGPoint(x: xFor(spotPrice), y: 16))
            line.addLine(to: CGPoint(x: xFor(spotPrice), y: size.height - 6))
            ctx.stroke(line, with: .color(ChartTheme.chartSpotLine),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // baseIV 水平线（白虚 · ATM IV）
        var baseLine = Path()
        baseLine.move(to: CGPoint(x: 0, y: yFor(assumedVol)))
        baseLine.addLine(to: CGPoint(x: size.width, y: yFor(assumedVol)))
        ctx.stroke(baseLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))

        // call IV 折线（cyan · 实线）
        var callPath = Path()
        for (i, iv) in callIVs.enumerated() {
            let pt = CGPoint(x: xFor(strikes[i]), y: yFor(iv))
            if i == 0 { callPath.move(to: pt) } else { callPath.addLine(to: pt) }
        }
        ctx.stroke(callPath, with: .color(ChartTheme.chartLine),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

        // put IV 折线（orange · 实线 · 略高于 call · put skew 视觉）
        var putPath = Path()
        for (i, iv) in putIVs.enumerated() {
            let pt = CGPoint(x: xFor(strikes[i]), y: yFor(iv))
            if i == 0 { putPath.move(to: pt) } else { putPath.addLine(to: pt) }
        }
        ctx.stroke(putPath, with: .color(.orange.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

        // strike 数据点（圆点）
        for (i, k) in strikes.enumerated() {
            let cx = xFor(k)
            let cy1 = yFor(callIVs[i])
            let cy2 = yFor(putIVs[i])
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy1 - 2, width: 4, height: 4)),
                     with: .color(ChartTheme.chartLine))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy2 - 2, width: 4, height: 4)),
                     with: .color(.orange.opacity(0.85)))
            _ = k
        }

        // 顶部标题 + skew 提示
        let skewLabel: String
        switch ivSmileSkew {
        case 0..<0.2: skewLabel = "平坦"
        case 0.2..<0.4: skewLabel = "微笑"
        case 0.4..<0.7: skewLabel = "标准笑"
        default: skewLabel = "陡笑"
        }
        let title = Text("📈 IV smile（cyan=call · orange=put · skew=\(String(format: "%.1f", ivSmileSkew)) \(skewLabel)）")
            .font(ChartTheme.fontSubvalue).foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    /// IV smile hover 信息
    private struct IVSmileHoverInfo {
        let strike: Double
        let callIV: Double
        let putIV: Double
        let snapX: CGFloat
    }

    private func ivSmileHoverInfo(at pt: CGPoint, in size: CGSize, slice: OptionChainSlice) -> IVSmileHoverInfo? {
        let rows = slice.rows
        let strikes = rows.map { NSDecimalNumber(decimal: $0.strikePrice).doubleValue }
        guard let minK = strikes.min(), let maxK = strikes.max(), maxK > minK else { return nil }
        let kRange = maxK - minK
        // 鼠标 x 反推 strike · 找最近的 row
        let xRatio = max(0, min(1, pt.x / size.width))
        let cursorK = minK + xRatio * kRange
        guard let i = strikes.indices.min(by: { abs(strikes[$0] - cursorK) < abs(strikes[$1] - cursorK) }) else { return nil }
        let k = strikes[i]
        let snapX = CGFloat((k - minK) / kRange) * size.width
        let callIV = mockSmileIV(strike: k, spot: spotPrice, baseIV: assumedVol, skew: ivSmileSkew)
        let putIV = callIV + 0.005
        return IVSmileHoverInfo(strike: k, callIV: callIV, putIV: putIV, snapX: snapX)
    }

    private func ivSmileCrosshair(at pt: CGPoint, snapX: CGFloat, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: snapX, y: 0))
            p.addLine(to: CGPoint(x: snapX, y: size.height))
        }
        .stroke(ChartTheme.crosshairLine,
                style: StrokeStyle(lineWidth: ChartTheme.crosshairLineWidth, dash: ChartTheme.crosshairDash))
        .allowsHitTesting(false)
    }

    private func ivSmileTooltip(info: IVSmileHoverInfo) -> some View {
        let isATM = abs(info.strike - spotPrice) < 0.5
        let moneyness = info.strike > spotPrice ? "OTM Call / ITM Put"
                      : (info.strike < spotPrice ? "ITM Call / OTM Put" : "ATM")
        let skewVsBase = info.callIV - assumedVol
        let skewColor: Color = skewVsBase > 0.005 ? ChartTheme.chartLossEmphasized
                             : (skewVsBase < -0.005 ? ChartTheme.chartProfitEmphasized : ChartTheme.tooltipSecondary)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(format: "K %.0f", info.strike))
                    .font(ChartTheme.fontValueBold)
                    .foregroundColor(ChartTheme.tooltipPrimary)
                if isATM {
                    Text("ATM")
                        .font(ChartTheme.fontHint)
                        .foregroundColor(ChartTheme.chartLine)
                }
            }
            Text(moneyness)
                .font(ChartTheme.fontSubvalue)
                .foregroundColor(ChartTheme.tooltipMuted)
            Divider().background(ChartTheme.tooltipDivider)
            optionTooltipRow("call IV", String(format: "%.1f%%", info.callIV * 100), color: ChartTheme.chartLine)
            optionTooltipRow("put IV", String(format: "%.1f%%", info.putIV * 100), color: .orange.opacity(0.85))
            optionTooltipRow("base", String(format: "%.1f%%", assumedVol * 100), color: ChartTheme.tooltipSecondary)
            optionTooltipRow("vs base", String(format: "%@%.1f%%", skewVsBase >= 0 ? "+" : "", skewVsBase * 100),
                             color: skewColor)
        }
        .padding(ChartTheme.tooltipPadding)
        .frame(width: 200, alignment: .leading)
        .background(ChartTheme.tooltipBackground)
        .cornerRadius(ChartTheme.tooltipCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: ChartTheme.tooltipCornerRadius)
                    .stroke(ChartTheme.tooltipBorder, lineWidth: ChartTheme.tooltipBorderWidth))
    }
}

#endif
