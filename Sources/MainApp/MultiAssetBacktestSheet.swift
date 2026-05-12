// v17.83 D4 v3 · 多品种 / 多周期组合回测 sheet（BacktestWindow "🧭" 入口）
//
// trader 用同一公式扫 N 品种 × M 周期矩阵 · 看鲁棒性：
//   - positive rate ≥ 60% → 真信号
//   - 矩阵某行（某品种）全红 → 该品种不适配此策略
//   - 矩阵某列（某周期）全红 → 该周期不适配此策略
//
// 设计：
// - 5 标的 × 4 周期 = 20 cell（可调）· seed = hash(symbol + period) 派生 mock 轨迹差异化
// - bars 复用 BacktestWindow.makeBarsForSeed（注入 closure · 保持 mock RNG 一致）
// - 结果：矩阵 + 鲁棒性 HUD · trader 一眼看"哪个 cell 赚 / 哪个亏"

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import IndicatorCore

struct MultiAssetBacktestSheet: View {

    let formula: Formula
    let signalLineName: String
    let initialEquity: Double
    let commission: Double
    let slippage: Double
    let allowShort: Bool
    let barsForSeed: (Int) -> [BarData]
    @Binding var isPresented: Bool

    private static let symbols: [(id: String, name: String)] = [
        ("rb2510", "螺纹"),
        ("i2510",  "铁矿"),
        ("au2510", "黄金"),
        ("ag2510", "白银"),
        ("cu2510", "沪铜"),
    ]
    private static let periods: [String] = ["5m", "15m", "1H", "D"]

    @State private var result: MultiAssetBacktestResult?
    @State private var isRunning: Bool = false
    @State private var elapsedSeconds: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel.frame(width: 280)
                Divider()
                resultArea
            }
        }
        .frame(width: 1080, height: 680)
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundColor(.accentColor)
            Text("🧭 多品种 / 多周期 组合回测").font(.title3.bold())
            Text("· 同公式 × N 标的 × M 周期 · 矩阵鲁棒性")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            if let r = result {
                Text("\(r.outcomes.count)/\(r.inputCellCount) cells · \(String(format: "%.2fs", elapsedSeconds))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("矩阵规模").font(.headline)
            HStack {
                Image(systemName: "tag.fill").foregroundColor(.secondary).font(.caption)
                Text("\(Self.symbols.count) 标的：" + Self.symbols.map(\.id).joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Image(systemName: "clock.fill").foregroundColor(.secondary).font(.caption)
                Text("\(Self.periods.count) 周期：" + Self.periods.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Text("共 \(Self.symbols.count * Self.periods.count) cells · 每 cell 独立 seed mock 轨迹")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            Button(action: runMultiAsset) {
                HStack {
                    if isRunning {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunning ? "跑批中…" : "运行组合回测").font(.callout.bold())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isRunning)

            if let r = result {
                Divider()
                interpretation(r.robustness)
            }
            Spacer()
        }
        .padding(12)
    }

    private func interpretation(_ rob: RobustnessReport) -> some View {
        let stability: String
        let stabilityColor: Color
        if rob.cellCount == 0 {
            stability = "无样本"
            stabilityColor = .secondary
        } else if rob.positiveRate >= 0.7 {
            stability = "✅ 鲁棒（positive ≥ 70%）"
            stabilityColor = .green
        } else if rob.positiveRate >= 0.5 {
            stability = "⚠️ 中等（positive 50-70%）"
            stabilityColor = .orange
        } else {
            stability = "❌ 过拟合风险（positive < 50%）"
            stabilityColor = .red
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("解读").font(.headline)
            Text(stability)
                .font(.callout)
                .foregroundColor(stabilityColor)
            Text("positive：\(rob.positiveCellCount)/\(rob.cellCount) (\(String(format: "%.0f%%", rob.positiveRate * 100)))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("avg PnL：\(String(format: "%+.2f", rob.avgEndingPnL))")
                .font(.caption)
                .foregroundColor(rob.avgEndingPnL >= 0 ? .green : .red)
            Text("avg Sharpe：\(String(format: "%.2f", rob.avgSharpe))")
                .font(.caption)
                .foregroundColor(.secondary)
            if let best = rob.bestCell {
                Text("最佳：\(best.symbol) \(best.periodLabel) · \(String(format: "%+.2f", (best.result.endingPnL as NSDecimalNumber).doubleValue))")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            if let worst = rob.worstCell, worst.symbol != rob.bestCell?.symbol || worst.periodLabel != rob.bestCell?.periodLabel {
                Text("最差：\(worst.symbol) \(worst.periodLabel) · \(String(format: "%+.2f", (worst.result.endingPnL as NSDecimalNumber).doubleValue))")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    private var resultArea: some View {
        VStack(spacing: 0) {
            if let r = result {
                statsHUD(r.robustness)
                Divider()
                matrixView(r)
            } else {
                emptyResult
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("点击 ▶ 跑 \(Self.symbols.count) × \(Self.periods.count) 矩阵")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("trader 看公式在不同品种/周期下的鲁棒性")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statsHUD(_ rob: RobustnessReport) -> some View {
        HStack(spacing: 22) {
            stat("cells", "\(rob.cellCount)", color: .primary)
            stat("positive", "\(rob.positiveCellCount)", color: rob.positiveCellCount > 0 ? .green : .secondary)
            stat("rate", String(format: "%.0f%%", rob.positiveRate * 100),
                 color: rob.positiveRate >= 0.6 ? .green : (rob.positiveRate >= 0.4 ? .orange : .red))
            Divider().frame(height: 28)
            stat("avg PnL", String(format: "%+.2f", rob.avgEndingPnL),
                 color: rob.avgEndingPnL >= 0 ? .green : .red)
            stat("avg Sharpe", String(format: "%.2f", rob.avgSharpe), color: .secondary)
            stat("avg winRate", String(format: "%.0f%%", rob.avgWinRate * 100), color: .secondary)
            stat("trades", "\(rob.totalTradeCount)", color: .secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func matrixView(_ r: MultiAssetBacktestResult) -> some View {
        // 用 outcome dict O(1) lookup
        let map: [String: BacktestCellOutcome] = Dictionary(
            uniqueKeysWithValues: r.outcomes.map { ("\($0.symbol)|\($0.periodLabel)", $0) }
        )
        // 全局 |PnL| max 用于染色归一化
        let maxAbsPnL = r.outcomes.map { abs(($0.result.endingPnL as NSDecimalNumber).doubleValue) }.max() ?? 1.0
        return ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 4) {
                // header row
                HStack(spacing: 4) {
                    Text("").frame(width: 90, alignment: .leading)
                    ForEach(Self.periods, id: \.self) { p in
                        Text(p)
                            .font(.caption.monospaced().bold())
                            .frame(width: 140, alignment: .center)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
                ForEach(Self.symbols, id: \.id) { sym in
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sym.id)
                                .font(.system(size: 11, design: .monospaced).bold())
                            Text(sym.name)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 90, alignment: .leading)
                        ForEach(Self.periods, id: \.self) { p in
                            matrixCell(outcome: map["\(sym.id)|\(p)"], maxAbsPnL: maxAbsPnL)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func matrixCell(outcome: BacktestCellOutcome?, maxAbsPnL: Double) -> some View {
        Group {
            if let o = outcome {
                let pnl = (o.result.endingPnL as NSDecimalNumber).doubleValue
                let intensity = min(1.0, abs(pnl) / max(maxAbsPnL, 1e-9))
                let baseColor: Color = pnl >= 0 ? .green : .red
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(String(format: "%+.1f", pnl))
                            .font(.system(size: 12, design: .monospaced).weight(.semibold))
                            .foregroundColor(pnl >= 0 ? .green : .red)
                        Spacer()
                        Text("\(o.result.trades.count) trade")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("S \(String(format: "%.2f", o.result.sharpe))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("W \(String(format: "%.0f%%", o.result.winRate * 100))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(6)
                .frame(width: 140, alignment: .leading)
                .background(baseColor.opacity(0.10 + 0.30 * intensity))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(baseColor.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(4)
                .help("\(o.symbol) \(o.periodLabel) · PnL \(String(format: "%+.2f", pnl)) · Sharpe \(String(format: "%.2f", o.result.sharpe)) · 胜率 \(String(format: "%.0f%%", o.result.winRate * 100)) · \(o.result.trades.count) trade")
            } else {
                Text("—")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 140, height: 38)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                    .help("cell 跑失败（公式 parse 错或 bars 不足）")
            }
        }
    }

    private func runMultiAsset() {
        isRunning = true
        result = nil
        let t0 = Date()
        Task { @MainActor in
            let cells: [BacktestCell] = Self.symbols.flatMap { sym in
                Self.periods.map { period -> BacktestCell in
                    // seed = hash(symbol + period) · 每 cell 独立 mock 轨迹
                    let seed = abs("\(sym.id)|\(period)".hashValue) % 9999 + 1
                    return BacktestCell(symbol: sym.id, periodLabel: period, bars: barsForSeed(seed))
                }
            }
            let r = MultiAssetMultiPeriodBacktest.run(
                formula: formula,
                cells: cells,
                signalLineName: signalLineName,
                initialEquity: Decimal(initialEquity),
                commission: Decimal(commission),
                slippage: Decimal(slippage),
                allowShort: allowShort
            )
            elapsedSeconds = Date().timeIntervalSince(t0)
            result = r
            isRunning = false
        }
    }
}

#endif
