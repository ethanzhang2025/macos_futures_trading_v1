// MainApp · 复盘工作台 Scene（WP-50 UI · 8 图就位）
//
// 留待 M5：JournalStore 真数据替换 Mock（StoreManager 注入时一并接入）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Charts
import Shared
import JournalCore

struct ReviewWindow: View {

    @State private var summary: ReviewSummary?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let summary {
                content(summary)
            } else if let loadError {
                errorView(loadError)
            } else {
                ProgressView("加载复盘数据…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1024, idealWidth: 1280, minHeight: 720, idealHeight: 900)
        .task { await loadMockReview() }
    }

    /// v1 mock trades · M5 替换为 JournalStore 真数据（StoreManager 注入时一并接入）
    private func loadMockReview() async {
        let result = await Task.detached(priority: .userInitiated) {
            let trades = MockReviewTrades.generate(pairCount: 50)
            let multipliers: [String: Int] = ["RB0": 10, "IF0": 300, "AU0": 1000, "CU0": 5]
            let (closed, _) = PositionMatcher.match(trades: trades, multipliers: multipliers)
            return ReviewSummary(
                tradeCount: trades.count,
                closedPositions: closed,
                monthlyPnL: ReviewAnalytics.monthlyPnL(from: closed),
                pnlDistribution: ReviewAnalytics.pnlDistribution(from: closed, binSize: Decimal(500)),
                winRateCurve: ReviewAnalytics.winRateCurve(from: closed),
                instrumentMatrix: ReviewAnalytics.instrumentMatrix(from: closed),
                holdingDuration: ReviewAnalytics.holdingDurationStats(from: closed),
                maxDrawdown: ReviewAnalytics.maxDrawdownCurve(from: closed),
                profitLossRatio: ReviewAnalytics.profitLossRatio(from: closed),
                sessionPnL: ReviewAnalytics.sessionPnL(from: closed)
            )
        }.value
        summary = result
    }

    @ViewBuilder
    private func content(_ s: ReviewSummary) -> some View {
        VStack(spacing: 0) {
            header(s)
            Divider()
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    chartCard("月度盈亏",
                              subtitle: "MonthlyPnL · \(s.monthlyPnL.buckets.count) 月跨度") {
                        monthlyPnLChart(s.monthlyPnL)
                    }
                    chartCard("分布直方",
                              subtitle: "PnLDistribution · \(s.pnlDistribution.bins.count) 桶 · 盈\(s.pnlDistribution.positiveCount)/亏\(s.pnlDistribution.negativeCount)") {
                        pnlDistributionChart(s.pnlDistribution)
                    }
                    chartCard("胜率曲线",
                              subtitle: "WinRateCurve · 终值 \(pct(s.winRateCurve.finalWinRate))") {
                        winRateChart(s.winRateCurve)
                    }
                    chartCard("品种矩阵",
                              subtitle: "InstrumentMatrix · \(s.instrumentMatrix.cells.count) 合约") {
                        instrumentMatrixView(s.instrumentMatrix)
                    }
                    chartCard("持仓时间",
                              subtitle: "中位 \(durationLabel(s.holdingDuration.medianSeconds)) · 平均 \(durationLabel(s.holdingDuration.averageSeconds))") {
                        holdingDurationChart(s.holdingDuration)
                    }
                    chartCard("最大回撤",
                              subtitle: "MaxDrawdown · ¥-\(decimal(s.maxDrawdown.maxDrawdown))") {
                        maxDrawdownChart(s.maxDrawdown)
                    }
                    chartCard("盈亏比",
                              subtitle: "ProfitLossRatio · \(decimal(s.profitLossRatio.ratio)) · 胜 \(s.profitLossRatio.winCount) / 亏 \(s.profitLossRatio.lossCount)") {
                        profitLossRatioView(s.profitLossRatio)
                    }
                    chartCard("时段分析",
                              subtitle: "SessionPnL · \(s.sessionPnL.buckets.count) 段") {
                        sessionPnLChart(s.sessionPnL)
                    }
                }
                .padding(16)
            }
        }
    }

    private func header(_ s: ReviewSummary) -> some View {
        HStack(spacing: 24) {
            Text("📊 复盘工作台").font(.title2).bold()
            Divider().frame(height: 24)
            stat("成交", "\(s.tradeCount) 笔")
            stat("闭合", "\(s.closedPositions.count) 笔")
            stat("总 PnL", "¥\(signedDecimal(s.monthlyPnL.totalPnL))")
            stat("胜率", pct(s.winRateCurve.finalWinRate))
            Spacer()
            Text("v1 mock · 待 M5 接 JournalStore 真数据")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced))
        }
    }

    /// 8 图统一卡片容器（标题 + subtitle + 内容区）
    @ViewBuilder
    private func chartCard<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(minHeight: 220)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    /// 自适应列数：每列至少 260 · 窗口窄自动减到 3/2/1 列 · 不再固定 4 列裁切
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 260, maximum: 600), spacing: 16)]
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("❌ 复盘加载失败").font(.headline)
            Text(msg).font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 折线图

    /// 胜率曲线 · y 固定 0~100% · 50% 虚线参考（盈亏分水岭）
    private func winRateChart(_ curve: WinRateCurve) -> some View {
        Chart {
            ForEach(curve.points, id: \.self) { p in
                LineMark(
                    x: .value("时间", p.timestamp),
                    y: .value("胜率", p.cumulativeWinRate)
                )
                .foregroundStyle(Color.green)
            }
            RuleMark(y: .value("基准", 0.5))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let r = v.as(Double.self) {
                        Text(String(format: "%.0f%%", r * 100))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 9))
            }
        }
    }

    /// 最大回撤 · 双线（累计 PnL 蓝实 + 高水位绿虚）+ 最大回撤区间红阴影
    private func maxDrawdownChart(_ curve: MaxDrawdownCurve) -> some View {
        Chart {
            if let start = curve.maxDrawdownStart, let end = curve.maxDrawdownEnd {
                RectangleMark(
                    xStart: .value("回撤起", start),
                    xEnd: .value("回撤止", end)
                )
                .foregroundStyle(Color.red.opacity(0.15))
            }
            ForEach(curve.points, id: \.self) { p in
                LineMark(
                    x: .value("时间", p.timestamp),
                    y: .value("水位", Self.toDouble(p.highWaterMark)),
                    series: .value("series", "高水位")
                )
                .foregroundStyle(Color.green.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(curve.points, id: \.self) { p in
                LineMark(
                    x: .value("时间", p.timestamp),
                    y: .value("累计PnL", Self.toDouble(p.cumulativePnL)),
                    series: .value("series", "累计 PnL")
                )
                .foregroundStyle(Color.blue)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 9))
            }
        }
        .chartYAxis { Self.axisYuan() }
    }

    // MARK: - 柱状图

    /// 月度盈亏 · 涨红跌绿（中国期货约定）
    private func monthlyPnLChart(_ data: MonthlyPnL) -> some View {
        Chart {
            ForEach(data.buckets, id: \.self) { bucket in
                BarMark(
                    x: .value("月", String(format: "%02d/%02d", bucket.year % 100, bucket.month)),
                    y: .value("PnL", Self.toDouble(bucket.realizedPnL))
                )
                .foregroundStyle(Self.pnlColor(bucket.realizedPnL))
            }
        }
        .chartXAxis { Self.axisCategoryX() }
        .chartYAxis { Self.axisYuan() }
    }

    /// 分布直方 · 按桶下界 · 负桶绿/正桶红
    private func pnlDistributionChart(_ data: PnLDistribution) -> some View {
        Chart {
            ForEach(data.bins, id: \.self) { bin in
                BarMark(
                    x: .value("起", Self.toDouble(bin.lowerBound)),
                    y: .value("笔数", bin.count),
                    width: .ratio(0.9)
                )
                .foregroundStyle(Self.pnlColor(bin.lowerBound))
            }
        }
        .chartXAxis { Self.axisYuan() }
        .chartYAxis { Self.axisIntegerY() }
    }

    /// 持仓时间 · 6 桶（label + count）· 中性蓝
    private func holdingDurationChart(_ data: HoldingDurationStats) -> some View {
        Chart {
            ForEach(data.buckets, id: \.self) { bucket in
                BarMark(
                    x: .value("时长", bucket.label),
                    y: .value("笔数", bucket.count)
                )
                .foregroundStyle(Color.blue.opacity(0.75))
            }
        }
        .chartXAxis { Self.axisCategoryX() }
        .chartYAxis { Self.axisIntegerY() }
    }

    /// 时段分析 · 5 段 · 涨红跌绿
    private func sessionPnLChart(_ data: SessionPnL) -> some View {
        Chart {
            ForEach(data.buckets, id: \.self) { bucket in
                BarMark(
                    x: .value("时段", Self.slotLabel(bucket.slot)),
                    y: .value("PnL", Self.toDouble(bucket.totalPnL))
                )
                .foregroundStyle(Self.pnlColor(bucket.totalPnL))
            }
        }
        .chartXAxis { Self.axisCategoryX() }
        .chartYAxis { Self.axisYuan() }
    }

    // MARK: - 表格 / 数值卡

    /// 品种矩阵 · 简表（合约 / 笔数 / 胜率 / PnL）· prefix 8 行 · 220 卡片高度内不会溢出
    private func instrumentMatrixView(_ data: InstrumentMatrix) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("合约").frame(maxWidth: .infinity, alignment: .leading)
                Text("笔数").frame(width: 36, alignment: .trailing)
                Text("胜率").frame(width: 44, alignment: .trailing)
                Text("PnL").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.bottom, 4)
            Divider()
            VStack(spacing: 2) {
                ForEach(data.cells.prefix(8), id: \.self) { cell in
                    HStack(spacing: 8) {
                        Text(cell.instrumentID)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(cell.tradeCount)")
                            .frame(width: 36, alignment: .trailing)
                        Text(String(format: "%.0f%%", cell.winRate * 100))
                            .frame(width: 44, alignment: .trailing)
                        Text(Self.formatYuan(Self.toDouble(cell.totalPnL)))
                            .frame(width: 60, alignment: .trailing)
                            .foregroundColor(Self.pnlColor(cell.totalPnL))
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.top, 4)
        }
    }

    /// 盈亏比 · 左侧双柱（平均盈红 / 平均亏绿）+ 右侧 ratio 大字
    /// ratio 红绿语义与 PnL 涨红跌绿反向：≥1 盈利占优红 · <1 亏损占优绿
    private func profitLossRatioView(_ data: ProfitLossRatio) -> some View {
        let bars: [(label: String, value: Decimal, color: Color)] = [
            ("平均盈", data.averageWin,  Self.bullColor),
            ("平均亏", data.averageLoss, Self.bearColor),
        ]
        return HStack(spacing: 12) {
            Chart {
                ForEach(bars, id: \.label) { bar in
                    BarMark(
                        x: .value("类型", bar.label),
                        y: .value("¥", Self.toDouble(bar.value))
                    )
                    .foregroundStyle(bar.color)
                }
            }
            .chartXAxis { Self.axisCategoryX() }
            .chartYAxis { Self.axisYuan() }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("盈亏比").font(.caption).foregroundColor(.secondary)
                Text(decimal(data.ratio))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(data.ratio >= 1 ? Self.bullColor : Self.bearColor)
                Text("胜 \(data.winCount) · 亏 \(data.lossCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 90)
        }
    }

    // MARK: - axis builder（4 柱图 + 双柱共用）

    private static func axisCategoryX() -> some AxisContent {
        AxisMarks(values: .automatic) { _ in
            AxisGridLine()
            AxisValueLabel().font(.system(size: 9))
        }
    }

    /// 万元单位 axis 标签（X/Y 通用 · SwiftUI Charts 按 chartXAxis/chartYAxis 位置区分轴）
    private static func axisYuan() -> some AxisContent {
        AxisMarks { v in
            AxisGridLine()
            AxisValueLabel {
                if let n = v.as(Double.self) {
                    Text(formatYuan(n)).font(.system(size: 9, design: .monospaced))
                }
            }
        }
    }

    private static func axisIntegerY() -> some AxisContent {
        AxisMarks { _ in
            AxisGridLine()
            AxisValueLabel().font(.system(size: 9, design: .monospaced))
        }
    }

    // MARK: - 配色 / 格式化（static · 4 chart + matrix + ratio 共用）

    static let bullColor = Color.red.opacity(0.75)   // 涨红（中国期货约定）
    static let bearColor = Color.green.opacity(0.75) // 跌绿

    /// PnL 涨红跌绿（≥0 红 / <0 绿）· 4 chart + matrix + ratio 大字共用
    private static func pnlColor(_ v: Decimal) -> Color {
        v >= 0 ? bullColor : bearColor
    }

    /// 万元单位简写（避免 y 轴标签过长 · 例如 12500 → "1.25w"）
    private static func formatYuan(_ n: Double) -> String {
        let abs = Swift.abs(n)
        if abs >= 10_000 { return String(format: "%.1fw", n / 10_000) }
        return String(format: "%.0f", n)
    }

    private static func toDouble(_ v: Decimal) -> Double {
        NSDecimalNumber(decimal: v).doubleValue
    }

    private static func slotLabel(_ s: TradingSlot) -> String {
        switch s {
        case .morning:   return "早盘"
        case .afternoon: return "午盘"
        case .night:     return "夜盘"
        case .midnight:  return "凌晨"
        case .other:     return "其他"
        }
    }

    // MARK: - HUD 数值格式化（保留 instance · SwiftUI body 直接调）

    private func decimal(_ v: Decimal) -> String {
        String(format: "%.0f", Self.toDouble(v))
    }

    private func signedDecimal(_ v: Decimal) -> String {
        let n = Self.toDouble(v)
        return n >= 0 ? "+\(String(format: "%.0f", n))" : String(format: "%.0f", n)
    }

    private func pct(_ rate: Double) -> String {
        String(format: "%.1f%%", rate * 100)
    }

    private func durationLabel(_ secs: TimeInterval) -> String {
        if secs < 60 { return "\(Int(secs))秒" }
        if secs < 3600 { return "\(Int(secs / 60))分" }
        if secs < 86400 { return String(format: "%.1f时", secs / 3600) }
        return String(format: "%.1f天", secs / 86400)
    }
}

// MARK: - ReviewSummary（8 图聚合结果 + 总览数）

private struct ReviewSummary {
    let tradeCount: Int
    let closedPositions: [ClosedPosition]
    let monthlyPnL: MonthlyPnL
    let pnlDistribution: PnLDistribution
    let winRateCurve: WinRateCurve
    let instrumentMatrix: InstrumentMatrix
    let holdingDuration: HoldingDurationStats
    let maxDrawdown: MaxDrawdownCurve
    let profitLossRatio: ProfitLossRatio
    let sessionPnL: SessionPnL
}

// MARK: - Mock Trades 生成器（v1 演示 · M5 替换为 JournalStore 真数据）

enum MockReviewTrades {

    /// 4 合约 × pairCount 对开-平 trades · 60% 盈利率 · 6 月跨度 · 4 时段轮播
    /// SeededRNG 让同一 seed 跑多次结果一致（演示稳定）
    static func generate(pairCount: Int, seed: UInt64 = 42) -> [Trade] {
        let symbols: [(id: String, base: Decimal, swing: Decimal)] = [
            ("RB0", Decimal(3850),  Decimal(20)),
            ("IF0", Decimal(3500),  Decimal(25)),
            ("AU0", Decimal(450),   Decimal(3)),
            ("CU0", Decimal(72500), Decimal(800)),
        ]
        let openHours = [9, 13, 21, 1]   // 早 / 午 / 夜 / 凌晨
        var rng = SeededRNG(seed: seed)
        let now = Date()
        var trades: [Trade] = []
        trades.reserveCapacity(pairCount * 2)

        for i in 0..<pairCount {
            let sym = symbols[i % symbols.count]
            let dayOffset = Double(180 - (i * 180 / max(1, pairCount)))
            let openHour = openHours[i % openHours.count]
            let openMin = Int.random(in: 0..<55, using: &rng)
            let openTime = now.addingTimeInterval(-(dayOffset * 86400) + Double(openHour * 3600 + openMin * 60))
            let holdSec = Double.random(in: 300...14400, using: &rng)
            let closeTime = openTime.addingTimeInterval(holdSec)

            let isLong = Bool.random(using: &rng)
            let willWin = Double.random(in: 0...1, using: &rng) < 0.6
            // 多头赚价格涨 / 空头赚价格跌
            let priceShift: Double = willWin
                ? (isLong ? Double.random(in: 0.5...3.0, using: &rng) : -Double.random(in: 0.5...3.0, using: &rng))
                : (isLong ? -Double.random(in: 0.5...2.5, using: &rng) : Double.random(in: 0.5...2.5, using: &rng))

            let openPrice = sym.base + Decimal(Double.random(in: -10...10, using: &rng))
            let closePrice = openPrice + sym.swing * Decimal(priceShift / 10)
            let volume = Int.random(in: 1...3, using: &rng)
            let commission = Decimal(volume) * Decimal(5)

            trades.append(Trade(
                tradeReference: "MOCK-O-\(i)",
                instrumentID: sym.id,
                direction: isLong ? .buy : .sell,
                offsetFlag: .open,
                price: openPrice,
                volume: volume,
                commission: commission,
                timestamp: openTime,
                source: .manual
            ))
            trades.append(Trade(
                tradeReference: "MOCK-C-\(i)",
                instrumentID: sym.id,
                direction: isLong ? .sell : .buy,
                offsetFlag: .close,
                price: closePrice,
                volume: volume,
                commission: commission,
                timestamp: closeTime,
                source: .manual
            ))
        }
        return trades
    }
}

/// splitmix64 种子 RNG · 确保 mock 数据每次跑结果一致（演示稳定 + 测试可重现）
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#endif
