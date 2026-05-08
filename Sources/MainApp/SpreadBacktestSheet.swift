// 套利回测 Sheet（v15.37 · 套利分析 V2）
//
// 入口：SpreadWindow ⌘⌥S "回测"按钮 → 弹此 sheet
// 输入：当前 SpreadPair + spreadValues + rollingWindow
// 配置：进场 |Z| 阈值 + 出场 |Z| 阈值 + 最大持仓周期
// 输出：累积 PnL 曲线 + 8 指标 HUD + trades 列表（前 20 笔预览）
//
// 数据：v1 沿用 SpreadWindow 的 mock 数据（保持一致 · 用户看到的是同一时序）
// v2 接真历史（CTP 解锁后扩 · 当前已搁置）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import DataCore

struct SpreadBacktestSheet: View {

    let pair: SpreadPair
    let values: [SpreadValue]
    let rollingWindow: Int
    @Binding var isPresented: Bool

    // MARK: - 配置

    @State private var entryThreshold: Double = 2.0
    @State private var exitThreshold: Double = 0.5
    @State private var maxHoldingBars: Int = 60

    // MARK: - 结果

    @State private var trades: [SpreadTrade] = []
    @State private var summary: SpreadBacktestSummary = .empty

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel.frame(width: 260)
                Divider()
                resultArea
            }
        }
        .frame(width: 1080, height: 660)
        .onAppear { runBacktest() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .foregroundColor(.accentColor)
            Text("回测：\(pair.name)").font(.title3.bold())
            Text("· \(pair.unitLabel) · \(values.count) 样本 · 滚动窗口 \(rollingWindow)")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
            Button("关闭") { isPresented = false }.keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 配置面板

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("回测设置").font(.headline)

            configRow("进场 |Z|") {
                TextField("", value: $entryThreshold, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder).frame(width: 70)
            }

            configRow("出场 |Z|") {
                TextField("", value: $exitThreshold, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder).frame(width: 70)
            }

            configRow("最长持仓") {
                Stepper(value: $maxHoldingBars, in: 5...500, step: 5) {
                    Text("\(maxHoldingBars) 根").font(.callout.monospaced())
                }
            }

            Divider()

            Button {
                runBacktest()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("运行回测").font(.callout.bold())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "info.circle").font(.caption2).foregroundColor(.secondary)
                Text("策略：|Z| 突破阈值进场 · 回归到 ±exit 阈值出场\n做多价差：Z 极低进场 / 上涨获利\n做空价差：Z 极高进场 / 下跌获利")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }

    private func configRow<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label).font(.callout).foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - 结果区

    private var resultArea: some View {
        VStack(spacing: 0) {
            if summary.totalTrades > 0 {
                summaryHUD
                Divider()
                cumulativePnLChart
                Divider()
                tradesList
            } else {
                emptyResult
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.4))
            Text("无交易触发").font(.callout).foregroundColor(.secondary)
            Text("当前阈值 |Z| ≥ \(String(format: "%.1f", entryThreshold)) · \(values.count) 样本未出现极值\n试着降低进场阈值或换价差对")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryHUD: some View {
        let s = summary
        return HStack(spacing: 14) {
            statBlock("总交易", "\(s.totalTrades)", color: .secondary)
            statBlock("胜率", String(format: "%.0f%%", s.winRate * 100),
                     color: s.winRate >= 0.5 ? .green : .red)
            statBlock("总 PnL", fmt(s.totalPnL),
                     color: s.totalPnL > 0 ? .green : .red)
            statBlock("均 PnL", fmt(s.avgPnL),
                     color: s.avgPnL > 0 ? .green : .red)
            statBlock("最大回撤", fmt(s.maxDrawdown), color: .red)
            statBlock("最大单赚", fmt(s.maxWinPnL), color: .green)
            statBlock("最大单亏", fmt(s.maxLossPnL), color: .red)
            statBlock("均持仓", String(format: "%.1f 根", s.avgHoldingBars), color: .secondary)
            Spacer()
            Text("\(s.wins) 赚 / \(s.losses) 亏")
                .font(.caption.monospaced()).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced().weight(.semibold)).foregroundColor(color)
        }
    }

    // MARK: - 累积 PnL 曲线

    private var cumulativePnLChart: some View {
        Canvas { ctx, size in
            drawCumulativePnL(ctx: ctx, size: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    private func drawCumulativePnL(ctx: GraphicsContext, size: CGSize) {
        let cum = summary.cumulativePnL.map { NSDecimalNumber(decimal: $0).doubleValue }
        guard cum.count >= 2 else { return }
        guard let lo = cum.min(), let hi = cum.max() else { return }
        let pad = max(0.01, (hi - lo) * 0.1)
        let viewMin = lo - pad
        let viewMax = hi + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = size.width / CGFloat(cum.count - 1)

        func yFor(_ v: Double) -> CGFloat {
            CGFloat(1 - (v - viewMin) / viewRange) * size.height
        }

        // 0 线（白虚）
        if viewMin < 0 && viewMax > 0 {
            var z = Path()
            z.move(to: CGPoint(x: 0, y: yFor(0)))
            z.addLine(to: CGPoint(x: size.width, y: yFor(0)))
            ctx.stroke(z, with: .color(.white.opacity(0.25)),
                       style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
        }

        // 累积 PnL 折线 · 分段绿/红
        for i in 0..<(cum.count - 1) {
            let x1 = CGFloat(i) * xStep
            let x2 = CGFloat(i + 1) * xStep
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(cum[i])))
            seg.addLine(to: CGPoint(x: x2, y: yFor(cum[i + 1])))
            let isUp = cum[i + 1] >= cum[i]
            ctx.stroke(seg, with: .color(isUp ? .green.opacity(0.85) : .red.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // peak（▲ 绿）+ trough（▼ 红）
        if let peakIdx = cum.firstIndex(of: cum.max()!) {
            let x = CGFloat(peakIdx) * xStep
            let y = yFor(cum[peakIdx])
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.green))
        }
        if let troughIdx = cum.firstIndex(of: cum.min()!) {
            let x = CGFloat(troughIdx) * xStep
            let y = yFor(cum[troughIdx])
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.red))
        }

        let title = Text("累积 PnL（绿涨段 · 红跌段 · ● peak/trough）")
            .font(.system(size: 10)).foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    // MARK: - 交易列表（前 20 笔预览）

    private var tradesList: some View {
        let recent = trades.prefix(20)
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(recent.enumerated()), id: \.offset) { (i, t) in
                    tradeChip(idx: i + 1, trade: t)
                }
                if trades.count > 20 {
                    Text("+\(trades.count - 20) 笔…")
                        .font(.caption2.monospaced()).foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 56)
        .background(Color.secondary.opacity(0.06))
    }

    private func tradeChip(idx: Int, trade: SpreadTrade) -> some View {
        let sideText: String = trade.side == .long ? "多" : "空"
        let sideColor: Color = trade.side == .long ? .green : .red
        let pnlD = NSDecimalNumber(decimal: trade.pnl).doubleValue
        let pnlColor: Color = trade.isWin ? .green : .red
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("#\(idx)").font(.caption2.monospaced()).foregroundColor(.secondary)
                Text(sideText).font(.caption2.bold()).foregroundColor(sideColor)
                Text(String(format: "%+.1f", pnlD))
                    .font(.caption2.monospaced().bold()).foregroundColor(pnlColor)
            }
            Text("\(trade.holdingBars) 根")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color.gray.opacity(0.10))
        .cornerRadius(3)
    }

    // MARK: - 跑回测

    private func runBacktest() {
        let zs = SpreadStatisticsCalculator.rollingZScores(values, window: rollingWindow)
        let sigs = SpreadSignalGenerator.generate(
            values: values, rollingZScores: zs,
            entryThreshold: entryThreshold,
            exitThreshold: exitThreshold,
            maxHoldingBars: maxHoldingBars
        )
        let result = SpreadBacktester.run(signals: sigs)
        trades = result.trades
        summary = result.summary
    }

    private func fmt(_ v: Decimal) -> String {
        let d = NSDecimalNumber(decimal: v).doubleValue
        if abs(d) >= 1000 { return String(format: "%+.0f", d) }
        if abs(d) >= 10   { return String(format: "%+.1f", d) }
        return String(format: "%+.2f", d)
    }
}

#endif
