// 期权回测 Sheet（v15.36 · 期权 Phase 6.4 · 工作台接 OptionBacktester）
//
// 入口：OptionWindow ⌘⌥O 策略面板"运行回测"按钮 → 弹此 sheet
// 输入：当前已构造的 OptionStrategy（snapshot · sheet 关闭后释放）
// 配置：持有天数 + 标的轨迹模式 + 起始 spot + IV + r
// 输出：PnL 曲线（绿/红 + 0 线 + spot 副曲线）+ 6 指标 HUD（endingPnL / maxDD / Sharpe / winRate / best / worst）
//
// 数据：v1 用 mock 标的轨迹（5 种模式：random walk / 上涨 / 下跌 / 横盘震荡 / V 反转）
// v2 接 CTP 真历史 K 线（CTP 解锁后接 · 当前已搁置 · 详 feedback_CTP_SimNow搁置.md）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import DataCore

struct OptionBacktestSheet: View {

    let strategy: OptionStrategy
    @Binding var isPresented: Bool

    // MARK: - 配置

    @State private var holdingDays: Int = 25
    @State private var trajectoryMode: TrajectoryMode = .randomWalk
    @State private var initialSpot: Double = 100
    @State private var volatility: Double = 0.20
    @State private var riskFreeRate: Double = 0.03
    @State private var rngSeed: UInt64 = 42

    // MARK: - 结果

    @State private var result: OptionBacktestResult?

    // MARK: - 轨迹模式

    enum TrajectoryMode: String, CaseIterable, Identifiable {
        case randomWalk = "random"
        case uptrend    = "up"
        case downtrend  = "down"
        case sideways   = "sideways"
        case vShape     = "v"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .randomWalk: return "随机游走"
            case .uptrend:    return "上涨趋势"
            case .downtrend:  return "下跌趋势"
            case .sideways:   return "横盘震荡"
            case .vShape:     return "V 形反转"
            }
        }
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel
                    .frame(width: 280)
                Divider()
                resultArea
            }
        }
        .frame(width: 1080, height: 640)
        .onAppear {
            // sheet 打开时按 strategy.underlyingEntryPrice 或推断的 spot 初始化
            if strategy.underlyingPositionSize > 0 {
                initialSpot = strategy.underlyingEntryPrice
            } else if let firstStrike = strategy.distinctStrikes.first {
                // 纯期权策略 · 用 strike 中位数作为初始 spot
                let mids = strategy.distinctStrikes
                initialSpot = mids[mids.count / 2]
                _ = firstStrike
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .foregroundColor(.accentColor)
            Text("回测：\(strategy.name)")
                .font(.title3.bold())
            Text("· \(strategy.underlyingName)（\(strategy.underlyingID)）")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 配置面板

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("回测设置").font(.headline)

            configRow("持有天数") {
                Stepper(value: $holdingDays, in: 1...365) {
                    Text("\(holdingDays) 天")
                        .font(.callout.monospaced())
                }
            }

            configRow("起始 spot") {
                TextField("", value: $initialSpot, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            configRow("波动率 σ") {
                TextField("", value: $volatility, format: .percent.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            configRow("利率 r") {
                TextField("", value: $riskFreeRate, format: .percent.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("标的轨迹").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $trajectoryMode) {
                    ForEach(TrajectoryMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            configRow("随机种子") {
                Stepper(value: $rngSeed, in: 0...10_000) {
                    Text("\(rngSeed)")
                        .font(.callout.monospaced())
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

            // 数据来源提示
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("v1 用 mock 标的轨迹 · 5 种模式可选\nv2 接真历史（待 CTP 解锁）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }

    private func configRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
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
            if let r = result {
                resultHUD(r)
                Divider()
                resultChart(r)
            } else {
                emptyResult
            }
        }
    }

    private var emptyResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("点击 ▶ 运行回测查看结果")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("策略：\(strategy.legs.count) leg · 持仓标的 \(strategy.underlyingPositionSize) 单位")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultHUD(_ r: OptionBacktestResult) -> some View {
        HStack(spacing: 16) {
            statBlock("末日 PnL", String(format: "%+.2f", r.endingPnL),
                     color: r.endingPnL >= 0 ? .green : .red)
            statBlock("最大回撤", String(format: "%.2f", r.maxDrawdown), color: .red)
            statBlock("年化 Sharpe", String(format: "%.2f", r.sharpeRatio),
                     color: r.sharpeRatio >= 1 ? .green : .secondary)
            statBlock("胜率", String(format: "%.0f%%", r.winRate * 100),
                     color: r.winRate >= 0.5 ? .green : .secondary)
            statBlock("最佳", String(format: "%+.2f", r.peakPnL), color: .green)
            statBlock("最差", String(format: "%+.2f", r.troughPnL), color: .red)
            Spacer()
            Text("\(r.curve.count) 样本 · \(strategy.strategyType.displayName)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundColor(color)
        }
    }

    private func resultChart(_ r: OptionBacktestResult) -> some View {
        Canvas { ctx, size in
            drawBacktestChart(ctx: ctx, size: size, result: r)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    // MARK: - 绘图

    private func drawBacktestChart(ctx: GraphicsContext, size: CGSize, result: OptionBacktestResult) {
        let curve = result.curve
        guard curve.count >= 2 else { return }
        // 上 65% 画 PnL · 下 30% 画 spot · 中间 5% 间隔
        let pnlH = size.height * 0.65
        let gapH: CGFloat = 16
        let spotH = size.height - pnlH - gapH
        let pnlRect = CGRect(x: 0, y: 0, width: size.width, height: pnlH)
        let spotRect = CGRect(x: 0, y: pnlH + gapH, width: size.width, height: spotH)

        drawPnLCurve(ctx: ctx, rect: pnlRect, curve: curve)
        drawSpotCurve(ctx: ctx, rect: spotRect, curve: curve)
    }

    private func drawPnLCurve(ctx: GraphicsContext, rect: CGRect, curve: [OptionBacktestPnL]) {
        let pnls = curve.map { $0.totalPnL }
        guard let minP = pnls.min(), let maxP = pnls.max() else { return }
        let pad = max(0.01, (maxP - minP) * 0.10)
        let viewMin = minP - pad
        let viewMax = maxP + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = rect.width / CGFloat(curve.count - 1)

        func yFor(_ p: Double) -> CGFloat {
            rect.minY + CGFloat(1 - (p - viewMin) / viewRange) * rect.height
        }

        // 0 线（白虚线）
        if viewMin < 0 && viewMax > 0 {
            var zero = Path()
            zero.move(to: CGPoint(x: rect.minX, y: yFor(0)))
            zero.addLine(to: CGPoint(x: rect.maxX, y: yFor(0)))
            ctx.stroke(zero, with: .color(.white.opacity(0.30)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // PnL 折线 · 分段绿/红
        for i in 0..<(curve.count - 1) {
            let p1 = curve[i].totalPnL
            let p2 = curve[i + 1].totalPnL
            let x1 = rect.minX + CGFloat(i) * xStep
            let x2 = rect.minX + CGFloat(i + 1) * xStep
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(p1)))
            seg.addLine(to: CGPoint(x: x2, y: yFor(p2)))
            let color: Color = (p1 >= 0 && p2 >= 0) ? .green
                              : (p1 < 0 && p2 < 0) ? .red
                              : .yellow
            ctx.stroke(seg, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // 标 peak / trough（小圆点）
        if let peakIdx = pnls.firstIndex(of: pnls.max()!) {
            let x = rect.minX + CGFloat(peakIdx) * xStep
            let y = yFor(pnls[peakIdx])
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.green))
        }
        if let troughIdx = pnls.firstIndex(of: pnls.min()!) {
            let x = rect.minX + CGFloat(troughIdx) * xStep
            let y = yFor(pnls[troughIdx])
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                     with: .color(.red))
        }

        // y 轴标签（4 等分）
        for i in 0..<5 {
            let v = viewMin + Double(i) * (viewMax - viewMin) / 4.0
            let y = yFor(v)
            let label = Text(String(format: "%+.1f", v))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
            ctx.draw(label, at: CGPoint(x: rect.maxX - 6, y: y), anchor: .trailing)
        }

        // 顶部标题
        let title = Text("PnL 曲线（绿盈 · 红亏 · 0 线虚 · ● 极值点）")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: rect.minX + 8, y: rect.minY + 8), anchor: .topLeading)
    }

    private func drawSpotCurve(ctx: GraphicsContext, rect: CGRect, curve: [OptionBacktestPnL]) {
        let spots = curve.map { $0.spotPrice }
        guard let minS = spots.min(), let maxS = spots.max(), maxS > minS else { return }
        let pad = (maxS - minS) * 0.10
        let viewMin = minS - pad
        let viewMax = maxS + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = rect.width / CGFloat(curve.count - 1)

        func yFor(_ s: Double) -> CGFloat {
            rect.minY + CGFloat(1 - (s - viewMin) / viewRange) * rect.height
        }

        // 入场价水平线（cyan 虚）
        if strategy.underlyingPositionSize > 0 {
            let entry = strategy.underlyingEntryPrice
            if entry >= viewMin && entry <= viewMax {
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: yFor(entry)))
                line.addLine(to: CGPoint(x: rect.maxX, y: yFor(entry)))
                ctx.stroke(line, with: .color(.cyan.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }

        // strike 水平线（橙虚）
        for s in strategy.distinctStrikes {
            guard s >= viewMin && s <= viewMax else { continue }
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: yFor(s)))
            line.addLine(to: CGPoint(x: rect.maxX, y: yFor(s)))
            ctx.stroke(line, with: .color(.orange.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
        }

        // spot 折线（白）
        var spotPath = Path()
        for (i, s) in spots.enumerated() {
            let pt = CGPoint(x: rect.minX + CGFloat(i) * xStep, y: yFor(s))
            if i == 0 { spotPath.move(to: pt) } else { spotPath.addLine(to: pt) }
        }
        ctx.stroke(spotPath, with: .color(.white.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // 标题
        let title = Text("标的价（cyan: 入场 · 橙: strikes）")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: rect.minX + 8, y: rect.minY + 6), anchor: .topLeading)
    }

    // MARK: - 跑回测

    private func runBacktest() {
        let samples = generateSamples()
        result = OptionBacktester.run(
            strategy: strategy,
            samples: samples,
            riskFreeRate: riskFreeRate,
            dividendYield: 0
        )
    }

    /// 5 种 mock 轨迹生成器（seeded RNG · 同种子可复现）
    private func generateSamples() -> [OptionBacktestSample] {
        var rng = SimpleSeededRNG(seed: rngSeed)
        let dailyVol = volatility / sqrt(252.0)   // 年化 σ → 日 σ
        let drift: Double
        switch trajectoryMode {
        case .randomWalk: drift = 0
        case .uptrend:    drift = 0.005
        case .downtrend:  drift = -0.005
        case .sideways:   drift = 0
        case .vShape:     drift = 0    // 特殊处理（先跌后涨）
        }

        let start = Date()
        var samples: [OptionBacktestSample] = []
        var spot = initialSpot
        let initialSpot = self.initialSpot

        for i in 0..<holdingDays {
            let date = start.addingTimeInterval(TimeInterval(i * 86400))
            let z = rng.nextGaussian()

            switch trajectoryMode {
            case .randomWalk, .uptrend, .downtrend:
                // GBM 简化：spot *= (1 + drift + σ·z)
                spot *= (1 + drift + dailyVol * z)
            case .sideways:
                // 均值回归：spot = initial + 小幅噪声（不累积）
                spot = initialSpot * (1 + dailyVol * z * 2)
            case .vShape:
                // 前半下跌（drift = -0.01）· 后半上涨（drift = +0.01）
                let halfPoint = holdingDays / 2
                let dynamicDrift = i < halfPoint ? -0.01 : 0.01
                spot *= (1 + dynamicDrift + dailyVol * z)
            }

            samples.append(OptionBacktestSample(
                date: date,
                spotPrice: max(0.01, spot),
                impliedVolatility: volatility
            ))
        }
        return samples
    }
}

// MARK: - 简易 seeded RNG（XorShift64 · 同种子可复现 · Sheet 切种子刷新轨迹）

private struct SimpleSeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdead_beef : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }

    /// 标准正态分布（Box-Muller）· 范围 [-3.5, 3.5] 99.9%
    mutating func nextGaussian() -> Double {
        let u1 = max(1e-10, Double(next() % 1_000_000) / 1_000_000.0)
        let u2 = max(1e-10, Double(next() % 1_000_000) / 1_000_000.0)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

#endif
