// MainApp · Shell · v17.61 · 右辅助 Inspector
//
// v17.0 设计 §1.1 列出的右辅助 4 section：
//   - 盘口 5 档（bid/ask）
//   - 分时 mini chart
//   - Tick 流
//   - 异动池
//
// Stage A 占位（mock 数据 · 不接 CTP · 视觉骨架优先）
// v2 接 SinaQuote bid/ask / TickEngine / AnomalyMonitor 真数据

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellInspector: View {

    @EnvironmentObject var shellVM: ShellViewModel
    /// v17.242 · NSPanel 嵌入模式时关闭 panel 的回调 · 默认 nil（旧版 Shell 内嵌仍走 inspectorVisible = false）
    var onClose: (() -> Void)? = nil

    /// 当前 active Pane 的 symbol（跟随 group binding · ShellInspector 显示其盘口/Tick）
    private var activeSymbol: String {
        guard let ws = shellVM.activeWorkspace else { return "rb2510" }
        let pane = shellVM.maximizedPaneID.flatMap { mid in ws.panes.first { $0.id == mid } }
            ?? ws.panes.first
        return pane.flatMap { shellVM.effectiveSymbol(for: $0) ?? $0.symbol } ?? "rb2510"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    orderBookSection
                    Divider()
                    miniIntradaySection
                    Divider()
                    tickStreamSection
                    Divider()
                    anomalySection
                }
                .padding(10)
            }
        }
        .frame(width: ShellMetrics.inspectorWidth)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("📊 \(activeSymbol)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Spacer()
            Button {
                // v17.242 · NSPanel 嵌入模式优先调 onClose 关闭 panel · 否则回退旧版 inspectorVisible 行为
                if let onClose { onClose() } else { shellVM.layout.inspectorVisible = false }
            } label: {
                Image(systemName: onClose != nil ? "xmark" : "sidebar.right")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(onClose != nil ? "关闭浮顶面板" : "收起右辅助（⌘⌥I 切换）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(Color.secondary.opacity(0.08))
    }

    // MARK: - 盘口 5 档

    @ViewBuilder
    private var orderBookSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("盘口 5 档")
            // 卖盘（从高到低）
            ForEach(Array(mockAsks(for: activeSymbol).enumerated()), id: \.offset) { _, level in
                bookRow(side: "卖\(level.idx)", price: level.price, qty: level.qty, isBid: false)
            }
            // 现价
            HStack {
                Text(currentPriceText(for: activeSymbol))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                Text(changeText(for: activeSymbol))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(.vertical, 4)
            // 买盘（从高到低）
            ForEach(Array(mockBids(for: activeSymbol).enumerated()), id: \.offset) { _, level in
                bookRow(side: "买\(level.idx)", price: level.price, qty: level.qty, isBid: true)
            }
        }
    }

    @ViewBuilder
    private func bookRow(side: String, price: String, qty: String, isBid: Bool) -> some View {
        HStack {
            Text(side)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(price)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isBid ? .red : .green)
            Spacer()
            Text(qty)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 1)
    }

    // MARK: - 分时 mini

    @ViewBuilder
    private var miniIntradaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("分时 (mini)")
            Canvas { ctx, size in
                let points = mockIntradayPoints
                guard points.count > 1 else { return }
                let minP = points.min() ?? 0
                let maxP = points.max() ?? 1
                let span = max(maxP - minP, 1e-6)
                var path = Path()
                for (i, p) in points.enumerated() {
                    let x = CGFloat(i) / CGFloat(points.count - 1) * size.width
                    let y = (1 - CGFloat((p - minP) / span)) * size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(.red), lineWidth: 1.4)
                // 基准线（首点价）
                let baselineY = (1 - CGFloat((points[0] - minP) / span)) * size.height
                var base = Path()
                base.move(to: CGPoint(x: 0, y: baselineY))
                base.addLine(to: CGPoint(x: size.width, y: baselineY))
                ctx.stroke(base, with: .color(.secondary.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
            .frame(height: 60)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(4)
            Text("mock · v2 接真实 9:00-15:00 分时")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tick 流

    @ViewBuilder
    private var tickStreamSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Tick 流")
            ForEach(Array(mockTicks(for: activeSymbol).enumerated()), id: \.offset) { _, t in
                HStack {
                    Text(t.time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Text(t.price)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(t.side == .buy ? .red : .green)
                    Spacer()
                    Text(t.qty)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - 异动池

    @ViewBuilder
    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("异动池")
            ForEach(Array(mockAnomalyPool.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Text("⚠️").font(.system(size: 10))
                    Text(item.symbol)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                    Text(item.event)
                        .font(.system(size: 10))
                    Spacer()
                    Text(item.time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - helper

    @ViewBuilder
    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Mock 数据（v2 接 SinaQuote / TickEngine / AnomalyMonitor）

    private struct BookLevel { let idx: Int; let price: String; let qty: String }
    private struct Tick { let time: String; let price: String; let qty: String; let side: Side; enum Side { case buy, sell } }
    private struct Anomaly { let symbol: String; let event: String; let time: String }

    private func currentPriceText(for symbol: String) -> String {
        // mock 现价 · 与 mockAsks/mockBids 中间挂钩
        switch symbol.lowercased() {
        case "rb2510": return "3225"
        case "if2509": return "3870"
        case "i2510":  return "780.5"
        case "ag2510": return "8520"
        default:       return "3000"
        }
    }

    private func changeText(for symbol: String) -> String {
        switch symbol.lowercased() {
        case "rb2510": return "+0.78% (+25)"
        case "if2509": return "-0.52% (-20)"
        case "i2510":  return "+1.23% (+9.5)"
        default:       return "+0.30%"
        }
    }

    private func mockAsks(for symbol: String) -> [BookLevel] {
        // 卖 5 → 卖 1 自上而下
        let base = Int(currentPriceText(for: symbol).split(separator: ".").first ?? "3000") ?? 3000
        return (1...5).reversed().map { i in
            BookLevel(idx: i, price: "\(base + i)", qty: "\(20 + i * 7)")
        }
    }

    private func mockBids(for symbol: String) -> [BookLevel] {
        let base = Int(currentPriceText(for: symbol).split(separator: ".").first ?? "3000") ?? 3000
        return (1...5).map { i in
            BookLevel(idx: i, price: "\(base - i)", qty: "\(15 + i * 6)")
        }
    }

    private var mockIntradayPoints: [Double] {
        // 简单的开盘后 30 个点 · 模拟分时趋势
        let base: Double = 3200
        return (0..<30).map { i in
            let drift = Double(i) * 0.4
            let noise = Double((i * 17) % 13 - 6)
            return base + drift + noise
        }
    }

    private func mockTicks(for symbol: String) -> [Tick] {
        let base = Int(currentPriceText(for: symbol).split(separator: ".").first ?? "3000") ?? 3000
        return [
            Tick(time: "14:25:33", price: "\(base)",      qty: "12", side: .buy),
            Tick(time: "14:25:32", price: "\(base - 1)",  qty: "8",  side: .sell),
            Tick(time: "14:25:31", price: "\(base)",      qty: "5",  side: .buy),
            Tick(time: "14:25:30", price: "\(base + 1)",  qty: "20", side: .buy),
            Tick(time: "14:25:29", price: "\(base)",      qty: "3",  side: .sell),
            Tick(time: "14:25:28", price: "\(base - 1)",  qty: "11", side: .sell),
        ]
    }

    private let mockAnomalyPool: [Anomaly] = [
        Anomaly(symbol: "rb2510", event: "突破前高 3230", time: "14:23"),
        Anomaly(symbol: "i2510",  event: "持续单边上扬", time: "14:18"),
        Anomaly(symbol: "ag2510", event: "成交量异常",   time: "14:05"),
        Anomaly(symbol: "MA2510", event: "价差扩大",     time: "13:55"),
    ]
}

#endif
