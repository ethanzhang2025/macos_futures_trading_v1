// v17.51 D2 v2.4 · Monte Carlo 鲁棒性测试 sheet（BacktestWindow "🎲" 入口）
//
// trader 跑同一公式 N 次（不同 seed → 不同 mock 轨迹）· 看 PnL 分布判稳定性
//
// 设计：
// - 输入：runs N · baseSeed（生成 [base, base+1, ..., base+N-1]）
// - 跑 → MonteCarloRunner.run（barsForSeed closure 复用主窗口 mock 模型）
// - 输出：9 stats + histogram（20 bin Canvas bar chart）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import IndicatorCore

struct MonteCarloSheet: View {

    let formula: Formula
    let signalLineName: String
    let initialEquity: Double
    let commission: Double
    let slippage: Double
    let allowShort: Bool
    let barsForSeed: (Int) -> [BarData]
    @Binding var isPresented: Bool

    @AppStorage("monteCarlo.v1.runs") private var runsN: Int = 50
    @AppStorage("monteCarlo.v1.baseSeed") private var baseSeed: Int = 1

    @State private var result: MonteCarloResult?
    @State private var isRunning: Bool = false
    @State private var elapsedSeconds: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel.frame(width: 320)
                Divider()
                resultArea
            }
        }
        .frame(width: 1080, height: 680)
    }

    private var header: some View {
        HStack {
            Image(systemName: "die.face.5.fill")
                .foregroundColor(.accentColor)
            Text("🎲 鲁棒性测试（Monte Carlo）")
                .font(.title3.bold())
            Text("· 同公式 × N 个 seed · 判稳定性 vs lucky")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            if let r = result {
                Text("\(r.runs.count) runs · \(String(format: "%.2fs", elapsedSeconds))")
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
            Text("跑批配置").font(.headline)

            HStack {
                Text("Runs N").font(.callout).foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                Stepper(value: $runsN, in: 10...500, step: 10) {
                    Text("\(runsN)").font(.callout.monospaced())
                }
            }

            HStack {
                Text("起始 seed").font(.callout).foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                Stepper(value: $baseSeed, in: 1...10_000, step: 1) {
                    Text("\(baseSeed)").font(.callout.monospaced())
                }
            }

            Text("种子范围：[\(baseSeed), \(baseSeed + runsN - 1)]")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button(action: runMonteCarlo) {
                HStack {
                    if isRunning {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunning ? "跑批中…" : "运行鲁棒性测试").font(.callout.bold())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isRunning)

            if let r = result {
                Divider()
                interpretation(r)
            }

            Spacer()
        }
        .padding(12)
    }

    /// 解读：std/avg ratio · profitableRatio · trader 一眼看结论
    private func interpretation(_ r: MonteCarloResult) -> some View {
        let stability: String
        let stabilityColor: Color
        if r.avgPnL == 0 {
            stability = "无盈利"
            stabilityColor = .secondary
        } else {
            let cv = r.stdPnL / abs(r.avgPnL)   // 变异系数
            if cv < 0.3 { stability = "✅ 稳定（CV < 30%）"; stabilityColor = .green }
            else if cv < 0.7 { stability = "⚠️ 中等（CV 30-70%）"; stabilityColor = .orange }
            else { stability = "❌ 不稳定（CV ≥ 70%）"; stabilityColor = .red }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("解读").font(.headline)
            Text(stability)
                .font(.callout)
                .foregroundColor(stabilityColor)
            Text("盈利占比：\(String(format: "%.0f%%", r.profitableRatio * 100))")
                .font(.caption)
                .foregroundColor(r.profitableRatio >= 0.6 ? .green : .secondary)
            Text("最差 5%：\(String(format: "%+.2f", r.p5PnL))")
                .font(.caption)
                .foregroundColor(r.p5PnL < 0 ? .red : .secondary)
        }
    }

    private var resultArea: some View {
        VStack(spacing: 0) {
            if let r = result {
                statsHUD(r)
                Divider()
                histogram(r)
            } else {
                emptyResult
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("点击 ▶ 跑批查看 PnL 分布")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("默认 50 runs × seed [1..50] · trader 判稳定性")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statsHUD(_ r: MonteCarloResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                stat("平均", r.avgPnL, color: r.avgPnL >= 0 ? .green : .red)
                stat("标准差", r.stdPnL, color: .secondary)
                stat("最差", r.minPnL, color: .red)
                stat("最好", r.maxPnL, color: .green)
                stat("中位数", r.medianPnL, color: r.medianPnL >= 0 ? .green : .red)
                Spacer()
            }
            HStack(spacing: 16) {
                stat("p5", r.p5PnL, color: r.p5PnL < 0 ? .red : .secondary)
                stat("p95", r.p95PnL, color: .green)
                statText("盈利占比", String(format: "%.0f%%", r.profitableRatio * 100),
                         color: r.profitableRatio >= 0.6 ? .green : .secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stat(_ label: String, _ value: Double, color: Color) -> some View {
        statText(label, String(format: "%+.2f", value), color: color)
    }

    private func statText(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundColor(color)
        }
    }

    // MARK: - Histogram（20 bin Canvas）

    private func histogram(_ r: MonteCarloResult) -> some View {
        GeometryReader { geom in
            Canvas { ctx, size in
                drawHistogram(ctx: ctx, size: size, result: r)
            }
            .background(Color.black.opacity(0.85))
        }
    }

    private func drawHistogram(ctx: GraphicsContext, size: CGSize, result r: MonteCarloResult) {
        let pnls = r.runs.map { ($0.endingPnL as NSDecimalNumber).doubleValue }
        guard pnls.count >= 2 else {
            ctx.draw(Text("样本不足（< 2 runs）")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6)),
                     at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let minV = pnls.min() ?? 0
        let maxV = pnls.max() ?? 0
        guard maxV > minV else {
            ctx.draw(Text("所有 run PnL 相同（\(String(format: "%.2f", minV))）")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6)),
                     at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let binCount = 20
        let binWidth = (maxV - minV) / Double(binCount)
        var counts = Array(repeating: 0, count: binCount)
        for v in pnls {
            var idx = Int((v - minV) / binWidth)
            if idx >= binCount { idx = binCount - 1 }
            if idx < 0 { idx = 0 }
            counts[idx] += 1
        }
        let maxCount = counts.max() ?? 1

        let leftPad: CGFloat = 40
        let bottomPad: CGFloat = 24
        let topPad: CGFloat = 24
        let rightPad: CGFloat = 12
        let chartW = size.width - leftPad - rightPad
        let chartH = size.height - topPad - bottomPad
        let barW = chartW / CGFloat(binCount)

        // 0 线（黄虚 · trader 一眼看正负分布）
        if minV < 0 && maxV > 0 {
            let zeroX = leftPad + CGFloat((0 - minV) / (maxV - minV)) * chartW
            var line = Path()
            line.move(to: CGPoint(x: zeroX, y: topPad))
            line.addLine(to: CGPoint(x: zeroX, y: topPad + chartH))
            ctx.stroke(line, with: .color(.yellow.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // bars
        for (i, count) in counts.enumerated() {
            let binMid = minV + (Double(i) + 0.5) * binWidth
            let barColor: Color = binMid >= 0 ? .green.opacity(0.7) : .red.opacity(0.7)
            let h = chartH * CGFloat(count) / CGFloat(maxCount)
            let rect = CGRect(x: leftPad + CGFloat(i) * barW,
                              y: topPad + chartH - h,
                              width: barW * 0.9, height: h)
            ctx.fill(Path(rect), with: .color(barColor))
        }

        // 标题 + 坐标
        let title = Text("PnL 分布（\(r.runs.count) runs · 20 bin · 绿盈红亏 · 黄虚=0）")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)

        let xMin = Text(String(format: "%+.0f", minV))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
        ctx.draw(xMin, at: CGPoint(x: leftPad, y: size.height - 4), anchor: .bottomLeading)
        let xMax = Text(String(format: "%+.0f", maxV))
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
        ctx.draw(xMax, at: CGPoint(x: size.width - rightPad, y: size.height - 4), anchor: .bottomTrailing)
    }

    // MARK: - 跑批

    private func runMonteCarlo() {
        isRunning = true
        result = nil
        let t0 = Date()
        let seeds = Array(baseSeed..<(baseSeed + runsN))
        Task { @MainActor in
            let r = MonteCarloRunner.run(
                formula: formula,
                seeds: seeds,
                barsForSeed: barsForSeed,
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
