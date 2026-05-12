// 公式回测窗口（v17.39 D3 · TradingView 对齐 D 段可视化）
//
// 入口：⌘⌥B（与 spreadAlert 区分；spreadAlert = ⌘⌥W）
// 设计：与 OptionBacktestSheet 同 UX 模式 · 但围绕 FormulaEngine + SimpleBacktestEngine
//
// 数据流（v1）：
//   公式 → Lexer/Parser → Formula
//   mock 标的轨迹（4 模式 · randomWalk/up/down/sideways）→ [BarData]
//   SimpleBacktestEngine.run → BacktestResult
//   结果区：6 指标 HUD + equity 曲线（带 0 基线 + DD 阴影）+ trades 表
//
// v2（留）：接 CTP 真历史 K 线（CTP 解锁后 · 当前搁置）
//          多公式 grid search UI 入口（已存 GridSearchEngine）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import IndicatorCore

public struct BacktestWindow: View {

    // MARK: - 配置（@AppStorage 持久化）

    @AppStorage("backtestWindow.v1.source") private var sourceText: String = defaultFormula
    @AppStorage("backtestWindow.v1.signalLine") private var signalLineName: String = "BUY"
    @AppStorage("backtestWindow.v1.initialEquity") private var initialEquity: Double = 100_000
    @AppStorage("backtestWindow.v1.barCount") private var barCount: Int = 200
    @AppStorage("backtestWindow.v1.initialSpot") private var initialSpot: Double = 100
    @AppStorage("backtestWindow.v1.volatility") private var volatility: Double = 0.20
    @AppStorage("backtestWindow.v1.seed") private var rngSeedStored: Int = 42
    @AppStorage("backtestWindow.v1.trajectory") private var trajectoryRaw: String = TrajectoryMode.randomWalk.rawValue
    @AppStorage("backtestWindow.v2.commission") private var commission: Double = 0   // v17.46 · 每 trade 双向手续费
    @AppStorage("backtestWindow.v2.slippage") private var slippage: Double = 0       // v17.46 · 滑点（绝对额）
    @AppStorage("backtestWindow.v2.allowShort") private var allowShort: Bool = false // v17.47 · 双向（信号 < 0 做空）

    // MARK: - 结果 / 状态

    @State private var result: BacktestResult?
    @State private var bars: [BarData] = []
    @State private var errorMessage: String?
    @State private var hoverPoint: CGPoint?
    @State private var historyRevision: Int = 0   // 触发 history 列表刷新
    @State private var showGridSearchSheet: Bool = false   // v17.44 D4 UI · 参数扫描

    // MARK: - 标的轨迹

    enum TrajectoryMode: String, CaseIterable, Identifiable {
        case randomWalk = "random"
        case uptrend    = "up"
        case downtrend  = "down"
        case sideways   = "sideways"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .randomWalk: return "随机游走"
            case .uptrend:    return "上涨趋势"
            case .downtrend:  return "下跌趋势"
            case .sideways:   return "横盘震荡"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                configPanel
                    .frame(width: 320)
                Divider()
                resultArea
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .sheet(isPresented: $showGridSearchSheet) {
            GridSearchSheet(
                bars: bars,
                signalLineName: signalLineName,
                initialEquity: initialEquity,
                isPresented: $showGridSearchSheet,
                onApplyFormula: { filledFormula in
                    sourceText = filledFormula
                    runBacktest()
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .foregroundColor(.accentColor)
            Text("公式回测").font(.title3.bold())
            Text("· SimpleBacktestEngine v1 · long-only · close 撮合")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            if let r = result {
                Text("trades \(r.trades.count) · bars \(r.equityCurve.count)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - 配置面板

    private var configPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("公式（麦语言）").font(.headline)
                TextEditor(text: $sourceText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 160)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))

                Text("回测设置").font(.headline)

                configRow("信号 line") {
                    TextField("", text: $signalLineName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                configRow("初始权益") {
                    TextField("", value: $initialEquity, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                configRow("K 线根数") {
                    Stepper(value: $barCount, in: 30...2000, step: 10) {
                        Text("\(barCount)").font(.callout.monospaced())
                    }
                }

                Divider()

                Text("成本模型（v17.46）").font(.headline)
                configRow("手续费/笔") {
                    TextField("", value: $commission, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .help("每笔交易双向手续费（绝对额 · 开+平一次性扣）")
                }
                configRow("滑点") {
                    TextField("", value: $slippage, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .help("滑点（绝对额 · 开仓买高 +slip · 平仓卖低 -slip）")
                }
                Toggle("允许做空（信号 < 0 开空 · v17.47）", isOn: $allowShort)
                    .font(.callout)
                    .help("勾选后信号 < 0 → 空仓 · 反向信号自动反手")

                Divider()

                Text("标的轨迹（mock）").font(.headline)
                Picker("", selection: Binding(
                    get: { TrajectoryMode(rawValue: trajectoryRaw) ?? .randomWalk },
                    set: { trajectoryRaw = $0.rawValue }
                )) {
                    ForEach(TrajectoryMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                configRow("起始价") {
                    TextField("", value: $initialSpot, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                configRow("波动率 σ") {
                    TextField("", value: $volatility, format: .percent.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                configRow("随机种子") {
                    Stepper(value: $rngSeedStored, in: 0...10_000) {
                        Text("\(rngSeedStored)").font(.callout.monospaced())
                    }
                }

                Divider()

                Button(action: runBacktest) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("运行回测").font(.callout.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                if result != nil {
                    Button(action: saveCurrentToHistory) {
                        HStack {
                            Image(systemName: "tray.and.arrow.down.fill")
                            Text("保存到历史").font(.callout)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("保存当前回测结果 · 可在月报中 cross-ref")
                }

                // v17.44 D4 · 参数扫描入口（需要已跑过一次回测确保 bars 有效）
                Button {
                    if bars.isEmpty {
                        bars = makeBars()
                    }
                    showGridSearchSheet = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("参数扫描").font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("批量跑公式参数组合（笛卡尔积）· 按 metric 排序找最优")

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }

                Divider()

                historySection
            }
            .padding(12)
        }
    }

    private func configRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout).foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
    }

    // MARK: - 历史区（D5 cross-ref 入口）

    private var historySection: some View {
        let entries = BacktestHistoryStore.load().entries.sorted { $0.createdAt > $1.createdAt }
        _ = historyRevision   // 依赖 · 保存后刷新
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("历史 \(entries.count)").font(.headline)
                Spacer()
                if !entries.isEmpty {
                    Button {
                        BacktestHistoryStore.clear()
                        historyRevision &+= 1
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("清空所有历史")
                }
            }
            if entries.isEmpty {
                Text("无 · 跑回测后点 💾 保存")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entries.prefix(8)) { e in
                    historyRow(e)
                }
                if entries.count > 8 {
                    Text("…还有 \(entries.count - 8) 条").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private func historyRow(_ e: BacktestHistoryEntry) -> some View {
        HStack(spacing: 6) {
            Text(BacktestHistoryEntry.dateLabel(e.createdAt))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(String(format: "%+.0f", (e.endingPnL as NSDecimalNumber).doubleValue))
                .font(.caption.monospaced())
                .foregroundColor(e.endingPnL >= 0 ? .green : .red)
            Text(String(format: "WR %.0f%%", e.winRate * 100))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
            Spacer()
            Button {
                BacktestHistoryStore.remove(id: e.id)
                historyRevision &+= 1
            } label: {
                Image(systemName: "xmark.circle.fill").font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
    }

    // MARK: - 结果区

    private var resultArea: some View {
        VStack(spacing: 0) {
            if let r = result {
                hud(r)
                Divider()
                equityChart(r)
                Divider()
                tradesTable(r)
                    .frame(height: 180)
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
            Text("默认公式 · MA 双均线穿越（MA5/MA20）· 信号 line = BUY")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hud(_ r: BacktestResult) -> some View {
        let endingD = (r.endingPnL as NSDecimalNumber).doubleValue
        let ddD = (r.maxDrawdown as NSDecimalNumber).doubleValue
        let expD = (r.expectancy as NSDecimalNumber).doubleValue
        return HStack(spacing: 14) {
            statBlock("末日 PnL", String(format: "%+.2f", endingD),
                     color: endingD >= 0 ? .green : .red)
            statBlock("最大回撤", String(format: "%.2f", ddD), color: .red)
            statBlock("Sharpe", String(format: "%.2f", r.sharpe),
                     color: r.sharpe >= 1 ? .green : .secondary)
            statBlock("Sortino", String(format: "%.2f", r.sortino),
                     color: r.sortino >= 1 ? .green : .secondary)
            statBlock("Calmar", String(format: "%.2f", r.calmar),
                     color: r.calmar >= 1 ? .green : .secondary)
            statBlock("胜率", String(format: "%.0f%%", r.winRate * 100),
                     color: r.winRate >= 0.5 ? .green : .secondary)
            statBlock("交易数", "\(r.trades.count)", color: .primary)
            statBlock("期望/笔", String(format: "%+.2f", expD),
                     color: expD >= 0 ? .green : .red)
            Spacer()
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

    // MARK: - Equity 曲线

    private func equityChart(_ r: BacktestResult) -> some View {
        GeometryReader { geom in
            ZStack {
                Canvas { ctx, size in
                    drawEquity(ctx: ctx, size: size, result: r)
                }
                .background(Color.black.opacity(0.85))

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): hoverPoint = pt
                        case .ended: hoverPoint = nil
                        }
                    }

                if let pt = hoverPoint, r.equityCurve.count >= 2,
                   let info = hoverInfo(at: pt, in: geom.size, result: r) {
                    crosshair(at: info.snapX, in: geom.size, hoverY: pt.y)
                    tooltip(info: info)
                        .position(tooltipPosition(near: pt, in: geom.size,
                                                  tooltipSize: CGSize(width: 200, height: 130)))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct HoverInfo {
        let index: Int
        let equity: Double
        let drawdown: Double
        let inTrade: Bool
        let snapX: CGFloat
    }

    private func hoverInfo(at pt: CGPoint, in size: CGSize, result r: BacktestResult) -> HoverInfo? {
        let n = r.equityCurve.count
        guard n >= 2, size.width > 0 else { return nil }
        let xStep = size.width / CGFloat(n - 1)
        let raw = Int((pt.x / xStep).rounded())
        let idx = max(0, min(n - 1, raw))
        let snapX = CGFloat(idx) * xStep
        let eq = (r.equityCurve[idx] as NSDecimalNumber).doubleValue
        let peak = peakUpTo(r.equityCurve, idx: idx)
        let dd = peak - eq
        let inTrade = r.trades.contains { idx >= $0.entryBarIndex && idx <= $0.exitBarIndex }
        return HoverInfo(index: idx, equity: eq, drawdown: dd, inTrade: inTrade, snapX: snapX)
    }

    private func peakUpTo(_ curve: [Decimal], idx: Int) -> Double {
        var peak: Decimal = curve[0]
        for i in 1...idx where curve[i] > peak { peak = curve[i] }
        return (peak as NSDecimalNumber).doubleValue
    }

    private func crosshair(at snapX: CGFloat, in size: CGSize, hoverY: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: snapX, y: 0))
            p.addLine(to: CGPoint(x: snapX, y: size.height))
            p.move(to: CGPoint(x: 0, y: hoverY))
            p.addLine(to: CGPoint(x: size.width, y: hoverY))
        }
        .stroke(Color.white.opacity(0.50),
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        .allowsHitTesting(false)
    }

    private func tooltip(info: HoverInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("第 \(info.index + 1) 根 bar")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Divider().background(Color.white.opacity(0.3))
            tooltipRow("权益", String(format: "%.2f", info.equity), color: .cyan)
            tooltipRow("回撤", String(format: "%.2f", info.drawdown),
                       color: info.drawdown > 0.0001 ? .red : .secondary)
            tooltipRow("持仓", info.inTrade ? "✓" : "—",
                       color: info.inTrade ? .green : .secondary)
        }
        .padding(8)
        .frame(width: 200, alignment: .leading)
        .background(Color.black.opacity(0.85))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }

    private func tooltipRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
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

    // MARK: - 绘图

    private func drawEquity(ctx: GraphicsContext, size: CGSize, result r: BacktestResult) {
        let curve = r.equityCurve
        guard curve.count >= 2 else { return }
        let vals = curve.map { ($0 as NSDecimalNumber).doubleValue }
        let initial = (r.initialEquity as NSDecimalNumber).doubleValue
        let minV = min(vals.min() ?? 0, initial)
        let maxV = max(vals.max() ?? 0, initial)
        let pad = max(0.01, (maxV - minV) * 0.10)
        let viewMin = minV - pad
        let viewMax = maxV + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = size.width / CGFloat(curve.count - 1)

        func yFor(_ v: Double) -> CGFloat {
            CGFloat(1 - (v - viewMin) / viewRange) * size.height
        }

        // 起始权益基线（白虚线）
        var base = Path()
        base.move(to: CGPoint(x: 0, y: yFor(initial)))
        base.addLine(to: CGPoint(x: size.width, y: yFor(initial)))
        ctx.stroke(base, with: .color(.white.opacity(0.30)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // DD 阴影（peak 以下区间填充半透明红）
        var peaks: [Double] = []
        peaks.reserveCapacity(vals.count)
        var p: Double = vals[0]
        for v in vals {
            if v > p { p = v }
            peaks.append(p)
        }
        var ddFill = Path()
        ddFill.move(to: CGPoint(x: 0, y: yFor(peaks[0])))
        for (i, peak) in peaks.enumerated() {
            let x = CGFloat(i) * xStep
            ddFill.addLine(to: CGPoint(x: x, y: yFor(peak)))
        }
        for i in stride(from: vals.count - 1, through: 0, by: -1) {
            let x = CGFloat(i) * xStep
            ddFill.addLine(to: CGPoint(x: x, y: yFor(vals[i])))
        }
        ddFill.closeSubpath()
        ctx.fill(ddFill, with: .color(.red.opacity(0.10)))

        // equity 折线 · 分段绿/红（相对基线）
        for i in 0..<(vals.count - 1) {
            let v1 = vals[i]
            let v2 = vals[i + 1]
            let x1 = CGFloat(i) * xStep
            let x2 = CGFloat(i + 1) * xStep
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(v1)))
            seg.addLine(to: CGPoint(x: x2, y: yFor(v2)))
            let color: Color = (v1 >= initial && v2 >= initial) ? .green.opacity(0.85)
                              : (v1 < initial && v2 < initial) ? .red.opacity(0.85)
                              : .yellow.opacity(0.85)
            ctx.stroke(seg, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // 交易区段顶部小标记（持仓 bar 上画淡蓝点）
        for trade in r.trades {
            let xEntry = CGFloat(trade.entryBarIndex) * xStep
            let yEntry = yFor((curve[trade.entryBarIndex] as NSDecimalNumber).doubleValue)
            ctx.fill(Path(ellipseIn: CGRect(x: xEntry - 3, y: yEntry - 3, width: 6, height: 6)),
                     with: .color(.cyan.opacity(0.85)))
            let xExit = CGFloat(trade.exitBarIndex) * xStep
            let yExit = yFor((curve[trade.exitBarIndex] as NSDecimalNumber).doubleValue)
            ctx.fill(Path(ellipseIn: CGRect(x: xExit - 3, y: yExit - 3, width: 6, height: 6)),
                     with: .color(trade.isWin ? .green : .red))
        }

        // y 轴标签（4 等分）
        for i in 0..<5 {
            let v = viewMin + Double(i) * (viewMax - viewMin) / 4.0
            let y = yFor(v)
            let label = Text(String(format: "%.0f", v))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            ctx.draw(label, at: CGPoint(x: size.width - 6, y: y), anchor: .trailing)
        }

        // 标题
        let title = Text("权益曲线（白基线 = 起始权益 · 红阴影 = 回撤 · ● 进出场点）")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
        ctx.draw(title, at: CGPoint(x: 8, y: 8), anchor: .topLeading)
    }

    // MARK: - Trades 表

    private func tradesTable(_ r: BacktestResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("成交记录 \(r.trades.count) 笔")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            tradesHeader

            if r.trades.isEmpty {
                Text("无成交 · 调整公式或起始价后重跑")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(r.trades.indices, id: \.self) { i in
                            tradeRow(idx: i, trade: r.trades[i])
                        }
                    }
                }
            }
        }
    }

    private var tradesHeader: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 36, alignment: .trailing)
            Text("入场 bar").frame(width: 70, alignment: .trailing)
            Text("入场价").frame(width: 80, alignment: .trailing)
            Text("出场 bar").frame(width: 70, alignment: .trailing)
            Text("出场价").frame(width: 80, alignment: .trailing)
            Text("PnL").frame(width: 80, alignment: .trailing)
            Text("PnL %").frame(width: 70, alignment: .trailing)
            Text("结果").frame(width: 50, alignment: .center)
            Spacer()
        }
        .font(.caption2.monospaced())
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
    }

    private func tradeRow(idx: Int, trade: BacktestTrade) -> some View {
        let pnlD = (trade.pnl as NSDecimalNumber).doubleValue
        let pctD = (trade.pnlPercent as NSDecimalNumber).doubleValue * 100
        return HStack(spacing: 0) {
            Text("\(idx + 1)").frame(width: 36, alignment: .trailing)
            Text("\(trade.entryBarIndex)").frame(width: 70, alignment: .trailing)
            Text(String(format: "%.2f", (trade.entryPrice as NSDecimalNumber).doubleValue))
                .frame(width: 80, alignment: .trailing)
            Text("\(trade.exitBarIndex)").frame(width: 70, alignment: .trailing)
            Text(String(format: "%.2f", (trade.exitPrice as NSDecimalNumber).doubleValue))
                .frame(width: 80, alignment: .trailing)
            Text(String(format: "%+.2f", pnlD))
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(pnlD >= 0 ? .green : .red)
            Text(String(format: "%+.1f%%", pctD))
                .frame(width: 70, alignment: .trailing)
                .foregroundColor(pnlD >= 0 ? .green : .red)
            Text(trade.isWin ? "盈" : "亏")
                .frame(width: 50, alignment: .center)
                .foregroundColor(trade.isWin ? .green : .red)
            Spacer()
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
    }

    // MARK: - 跑回测

    private func runBacktest() {
        errorMessage = nil
        do {
            var lexer = Lexer(source: sourceText)
            let tokens = try lexer.tokenize()
            var parser = Parser(tokens: tokens)
            let formula = try parser.parse()
            let generatedBars = makeBars()
            let r = try SimpleBacktestEngine.run(
                formula: formula,
                bars: generatedBars,
                signalLineName: signalLineName,
                initialEquity: Decimal(initialEquity),
                commission: Decimal(commission),
                slippage: Decimal(slippage),
                allowShort: allowShort
            )
            self.bars = generatedBars
            self.result = r
        } catch {
            self.result = nil
            self.errorMessage = "回测失败：\(error)"
        }
    }

    private func makeBars() -> [BarData] {
        let mode = TrajectoryMode(rawValue: trajectoryRaw) ?? .randomWalk
        var rng = SeededRNG(seed: UInt64(max(1, rngSeedStored)))
        let dailyVol = volatility / sqrt(252.0)
        let drift: Double
        switch mode {
        case .randomWalk: drift = 0
        case .uptrend:    drift = 0.005
        case .downtrend:  drift = -0.005
        case .sideways:   drift = 0
        }
        var spot = initialSpot
        var bars: [BarData] = []
        bars.reserveCapacity(barCount)
        let start = Date()
        for i in 0..<barCount {
            let z = rng.nextGaussian()
            switch mode {
            case .randomWalk, .uptrend, .downtrend:
                spot *= (1 + drift + dailyVol * z)
            case .sideways:
                spot = initialSpot * (1 + dailyVol * z * 2)
            }
            spot = max(0.01, spot)
            let close = spot
            let open = close * (1 - dailyVol * z * 0.3)
            let high = max(open, close) * (1 + abs(dailyVol * z) * 0.5)
            let low = min(open, close) * (1 - abs(dailyVol * z) * 0.5)
            bars.append(BarData(
                open: Decimal(max(0.01, open)),
                high: Decimal(max(0.01, high)),
                low: Decimal(max(0.01, low)),
                close: Decimal(close),
                volume: 1000,
                timestamp: start.addingTimeInterval(TimeInterval(i * 86400))
            ))
        }
        return bars
    }

    // MARK: - 历史保存（D5 cross-ref 入口）

    private func saveCurrentToHistory() {
        guard let r = result else { return }
        let mode = TrajectoryMode(rawValue: trajectoryRaw) ?? .randomWalk
        let entry = BacktestHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            signalLineName: signalLineName,
            trajectoryRaw: mode.rawValue,
            barCount: r.equityCurve.count,
            initialEquity: r.initialEquity,
            endingPnL: r.endingPnL,
            maxDrawdown: r.maxDrawdown,
            sharpe: r.sharpe,
            sortino: r.sortino,
            calmar: r.calmar,
            winRate: r.winRate,
            expectancy: r.expectancy,
            tradeCount: r.trades.count,
            commission: Decimal(commission),
            slippage: Decimal(slippage),
            allowShort: allowShort
        )
        BacktestHistoryStore.append(entry)
        historyRevision &+= 1
    }
}

// MARK: - 默认公式

private let defaultFormula: String = """
{ MA5 上穿 MA20 持仓 · 下穿空仓 }
MA5  := MA(CLOSE, 5);
MA20 := MA(CLOSE, 20);
BUY  : IF(MA5 > MA20, 1, 0);
"""

// MARK: - 简易 seeded RNG（XorShift64）

private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef : seed }
    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }
    mutating func nextGaussian() -> Double {
        let u1 = max(1e-10, Double(next() % 1_000_000) / 1_000_000.0)
        let u2 = max(1e-10, Double(next() % 1_000_000) / 1_000_000.0)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

#endif
