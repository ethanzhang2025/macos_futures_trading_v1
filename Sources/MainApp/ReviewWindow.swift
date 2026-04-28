// MainApp · 复盘工作台 Scene（WP-50 UI · 共 4 commit）
//
// 进度：
//   ✅ 1/4：开窗 + Mock 数据流 + 8 卡片占位
//   ✅ 2/4：折线类 2 图（胜率曲线 / 最大回撤）· SwiftUI Charts LineMark
//   ⏳ 3/4：柱状类 4 图（月度盈亏 / 分布直方 / 持仓时间 / 时段分析）· BarMark
//   ⏳ 4/4：其他 2 图（品种矩阵 / 盈亏比）+ JournalCore 真数据接入

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

    /// v1 用 mock trades · commit 4/4 替换为 JournalStore 真数据
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
                        placeholderArt("calendar")
                    }
                    chartCard("分布直方",
                              subtitle: "PnLDistribution · \(s.pnlDistribution.bins.count) 桶 · 盈\(s.pnlDistribution.positiveCount)/亏\(s.pnlDistribution.negativeCount)") {
                        placeholderArt("chart.bar.fill")
                    }
                    chartCard("胜率曲线",
                              subtitle: "WinRateCurve · 终值 \(pct(s.winRateCurve.finalWinRate))") {
                        winRateChart(s.winRateCurve)
                    }
                    chartCard("品种矩阵",
                              subtitle: "InstrumentMatrix · \(s.instrumentMatrix.cells.count) 合约") {
                        placeholderArt("tablecells")
                    }
                    chartCard("持仓时间",
                              subtitle: "中位 \(durationLabel(s.holdingDuration.medianSeconds)) · 平均 \(durationLabel(s.holdingDuration.averageSeconds))") {
                        placeholderArt("clock")
                    }
                    chartCard("最大回撤",
                              subtitle: "MaxDrawdown · ¥-\(decimal(s.maxDrawdown.maxDrawdown))") {
                        maxDrawdownChart(s.maxDrawdown)
                    }
                    chartCard("盈亏比",
                              subtitle: "ProfitLossRatio · \(decimal(s.profitLossRatio.ratio)) · 胜 \(s.profitLossRatio.winCount) / 亏 \(s.profitLossRatio.lossCount)") {
                        placeholderArt("scale.3d")
                    }
                    chartCard("时段分析",
                              subtitle: "SessionPnL · \(s.sessionPnL.buckets.count) 段") {
                        placeholderArt("moon.stars")
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
            Text("v1 mock · commit 4/4 接 JournalStore 真数据")
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
        .frame(height: 220)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    /// 占位（待 commit 3/4 替换为真实 SwiftUI Charts）
    private func placeholderArt(_ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("⏳ 待 SwiftUI Charts 绘制")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 280, maximum: 600), spacing: 16), count: 4)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("❌ 复盘加载失败").font(.headline)
            Text(msg).font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 折线类图（commit 2/4）

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
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text(formatYuan(n))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
            }
        }
    }

    /// 万元单位简写（避免 y 轴标签过长 · 例如 12500 → "1.25w"）
    private func formatYuan(_ n: Double) -> String {
        let abs = Swift.abs(n)
        if abs >= 10_000 { return String(format: "%.1fw", n / 10_000) }
        return String(format: "%.0f", n)
    }

    // MARK: - 格式化

    private static func toDouble(_ v: Decimal) -> Double {
        NSDecimalNumber(decimal: v).doubleValue
    }

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

// MARK: - Mock Trades 生成器（v1 演示 · commit 4/4 替换为 JournalStore 真数据）

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
