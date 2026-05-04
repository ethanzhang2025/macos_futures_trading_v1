// MainApp · 复盘工作台 Scene（WP-50 UI · 8 图就位）
//
// 留待 M5：JournalStore 真数据替换 Mock（StoreManager 注入时一并接入）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers
import Shared
import JournalCore

struct ReviewWindow: View {

    @State private var summary: ReviewSummary?
    @State private var loadError: String?
    /// v15.19 batch44 · 月份筛选 · "" = 全部 · 否则 "yyyy-MM" · 改值后重算 summary
    @State private var selectedMonth: String = ""
    /// 全量 closedPositions · 启动一次加载 · 月份切换不重拉数据
    @State private var allPositions: [ClosedPosition] = []
    @State private var totalTradeCount: Int = 0

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
        .onChange(of: selectedMonth) { _ in recomputeSummary() }
    }

    /// 启动加载 · 拉一次 trades + match · 后续仅按 selectedMonth 重算 summary
    private func loadMockReview() async {
        let (trades, closed) = await Task.detached(priority: .userInitiated) {
            let t = MockReviewTrades.generate(pairCount: 50)
            let multipliers: [String: Int] = ["RB0": 10, "IF0": 300, "AU0": 1000, "CU0": 5]
            let (c, _) = PositionMatcher.match(trades: t, multipliers: multipliers)
            return (t, c)
        }.value
        allPositions = closed
        totalTradeCount = trades.count
        recomputeSummary()
    }

    /// 按 selectedMonth 过滤 + 重算 summary（同步 · MainActor · 0 IO）
    @MainActor
    private func recomputeSummary() {
        let filtered = filterByMonth(allPositions, monthString: selectedMonth)
        summary = ReviewSummary(
            tradeCount: totalTradeCount,
            closedPositions: filtered,
            monthlyPnL: ReviewAnalytics.monthlyPnL(from: filtered),
            pnlDistribution: ReviewAnalytics.pnlDistribution(from: filtered, binSize: Decimal(500)),
            winRateCurve: ReviewAnalytics.winRateCurve(from: filtered),
            instrumentMatrix: ReviewAnalytics.instrumentMatrix(from: filtered),
            holdingDuration: ReviewAnalytics.holdingDurationStats(from: filtered),
            maxDrawdown: ReviewAnalytics.maxDrawdownCurve(from: filtered),
            profitLossRatio: ReviewAnalytics.profitLossRatio(from: filtered),
            sessionPnL: ReviewAnalytics.sessionPnL(from: filtered),
            streak: ReviewAnalytics.streakMetrics(from: filtered),
            riskAdjusted: ReviewAnalytics.riskAdjustedMetrics(from: filtered),
            profitability: ReviewAnalytics.profitabilityMetrics(from: filtered),
            streakRunPoints: Self.computeStreakRunPoints(from: filtered),
            psychTagCounts: Self.computePsychTagCounts(from: filtered)
        )
    }

    /// 月份过滤 · "" = 全部 · 否则按 yyyy-MM 字符串匹配
    private func filterByMonth(_ positions: [ClosedPosition], monthString: String) -> [ClosedPosition] {
        guard !monthString.isEmpty else { return positions }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        fmt.timeZone = cal.timeZone
        return positions.filter { fmt.string(from: $0.closeTime) == monthString }
    }

    /// 当前 positions 涵盖的所有月份（升序）· 用于 Picker 选项
    private var availableMonths: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        fmt.timeZone = cal.timeZone
        let months = Set(allPositions.map { fmt.string(from: $0.closeTime) })
        return months.sorted()
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
                    // v15.19 batch27 · streak 累积曲线（trader 看交易心理时间线 · 哪段连胜哪段连败）
                    chartCard("连胜连败曲线",
                              subtitle: "Streak · 最长连胜 \(s.streak.maxWinningStreak) / 最长连败 \(s.streak.maxLosingStreak)") {
                        streakRunChart(s.streakRunPoints)
                    }
                    // v15.19 batch27 · 心理标签命中分布（基于 EmotionAutoTagger.tagAll）
                    chartCard("心理风险标签",
                              subtitle: "EmotionAutoTagger · 6 类自动建议") {
                        psychTagsChart(s.psychTagCounts)
                    }
                }
                .padding(16)
            }
        }
    }

    private func header(_ s: ReviewSummary) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 20) {
                Text("📊 复盘工作台").font(.title2).bold()
                Divider().frame(height: 24)
                // v15.19 batch44 · 月份筛选 Picker（全部 / yyyy-MM 历史月份）
                Picker("", selection: $selectedMonth) {
                    Text("全部").tag("")
                    ForEach(availableMonths, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .help("按月份筛选 · 默认全部")
                stat("成交", "\(s.tradeCount) 笔")
                stat("闭合", "\(s.closedPositions.count) 笔")
                stat("总 PnL", "¥\(signedDecimal(s.monthlyPnL.totalPnL))")
                stat("胜率", pct(s.winRateCurve.finalWinRate))
                stat("最长连胜", "\(s.streak.maxWinningStreak) 笔")
                stat("最长连败", "\(s.streak.maxLosingStreak) 笔")
                stat("当前", currentStreakLabel(s.streak))
                Spacer()
                Text("v1 mock · 待 M5 接 JournalStore 真数据")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            // 风险调整 / 盈利能力专业指标（v15.18 已计算 · v15.19 batch20 暴露 UI）
            HStack(spacing: 20) {
                Spacer().frame(width: 110)   // 与上行 "📊 复盘工作台" + Divider 对齐
                stat("Sharpe", String(format: "%.2f", s.riskAdjusted.sharpeRatio))
                stat("Sortino", String(format: "%.2f", s.riskAdjusted.sortinoRatio))
                stat("Calmar", String(format: "%.2f", s.riskAdjusted.calmarRatio))
                stat("Recovery", String(format: "%.2f", s.riskAdjusted.recoveryFactor))
                stat("ProfitFactor", String(format: "%.2f", s.profitability.profitFactor))
                stat("Expectancy", "¥\(signedDecimal(s.profitability.expectancy))")
                stat("最大单笔盈", "¥\(decimal(s.profitability.largestWin))")
                stat("最大单笔亏", "¥\(decimal(s.profitability.largestLoss))")
                Spacer()
                Button("导出月报…") { exportMonthlyReport(s) }
                    .help("生成本月 Markdown 复盘报告 · 含全套指标 + 心理标签 + 品种/时段分布")
                Button("导出全部图…") { exportAllChartCards(s) }
                    .help("一键导出全部 10 张 chartCard 为 PNG 到选定目录 · 月底归档")
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// v15.19 batch47 · 一键导出全部 chartCard 为 PNG 到选定目录（trader 月底归档）
    @MainActor
    private func exportAllChartCards(_ s: ReviewSummary) {
        let panel = NSOpenPanel()
        panel.title = "选择导出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出到这里"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        let timestamp = dateFmt.string(from: Date())

        // 10 张图 · 与 content() 内 chartCard 顺序一致
        let cards: [(title: String, view: AnyView)] = [
            ("月度盈亏", AnyView(monthlyPnLChart(s.monthlyPnL))),
            ("分布直方", AnyView(pnlDistributionChart(s.pnlDistribution))),
            ("胜率曲线", AnyView(winRateChart(s.winRateCurve))),
            ("品种矩阵", AnyView(instrumentMatrixView(s.instrumentMatrix))),
            ("持仓时间", AnyView(holdingDurationChart(s.holdingDuration))),
            ("最大回撤", AnyView(maxDrawdownChart(s.maxDrawdown))),
            ("盈亏比", AnyView(profitLossRatioView(s.profitLossRatio))),
            ("时段分析", AnyView(sessionPnLChart(s.sessionPnL))),
            ("连胜连败曲线", AnyView(streakRunChart(s.streakRunPoints))),
            ("心理风险标签", AnyView(psychTagsChart(s.psychTagCounts)))
        ]

        var failedCount = 0
        for (title, content) in cards {
            let exportable = VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            .padding(20)
            .background(Color.white)
            guard let pngData = PNGRenderer.render(exportable, width: 720, height: 480) else {
                failedCount += 1
                continue
            }
            let url = folder.appendingPathComponent("复盘_\(title)_\(timestamp).png")
            do {
                try pngData.write(to: url, options: .atomic)
            } catch {
                failedCount += 1
            }
        }
        let success = cards.count - failedCount
        if failedCount == 0 {
            Toast.info("导出成功", "已导出 \(success) 张图到 \(folder.lastPathComponent)。")
        } else {
            Toast.errorBody("部分导出失败", "成功 \(success) / 失败 \(failedCount) 张 · 检查目录可写权限。")
        }
    }

    /// 月度 Markdown 复盘报告导出（NSSavePanel · 默认本月 · 用户可改文件名带年月）
    @MainActor
    private func exportMonthlyReport(_ s: ReviewSummary) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let panel = NSSavePanel()
        panel.title = "导出月度复盘报告"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(format: "复盘报告_%04d-%02d.md", year, month)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = MonthlyReportGenerator.generate(
            positions: s.closedPositions, year: year, month: month
        )
        do {
            try md.data(using: .utf8)?.write(to: url, options: .atomic)
            Toast.info("导出成功",
                       "已生成 \(year) 年 \(month) 月复盘报告到 \(url.lastPathComponent)。")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    private func currentStreakLabel(_ s: ReviewAnalytics.StreakMetrics) -> String {
        if s.currentStreak == 0 { return "—" }
        if s.currentStreakIsWinning { return "连胜 \(s.currentStreak)" }
        return "连败 \(abs(s.currentStreak))"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced))
        }
    }

    /// 8 图统一卡片容器（标题 + subtitle + 内容区）· v15.19 batch41 加 📷 PNG 导出按钮
    @ViewBuilder
    private func chartCard<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let chart = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Button {
                    exportChartCardPNG(title: title, subtitle: subtitle, content: content())
                } label: {
                    Image(systemName: "camera").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("导出本图为 PNG")
            }
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
        chart
    }

    /// v15.19 batch41 · 单 chartCard PNG 导出（trader 分享单图）
    @MainActor
    private func exportChartCardPNG<Content: View>(title: String, subtitle: String, content: Content) {
        let exportable = VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            content
        }
        .padding(20)
        .background(Color.white)   // 白底便于导出后插入文档

        guard let pngData = PNGRenderer.render(exportable, width: 720, height: 480) else {
            Toast.errorBody("截图失败", "ImageRenderer 渲染失败")
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 \(title) PNG"
        panel.allowedContentTypes = [.png]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "\(title)_\(dateFmt.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pngData.write(to: url, options: .atomic)
            Toast.info("导出成功", "已导出 \(title) 到 \(url.lastPathComponent)。")
        } catch {
            Toast.error("导出失败", error)
        }
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

    /// v15.19 batch27 · 连胜连败累积曲线（读取 ReviewSummary 缓存 · body 不重算）
    private func streakRunChart(_ points: [(idx: Int, run: Int)]) -> some View {
        Chart {
            ForEach(points.indices, id: \.self) { i in
                LineMark(
                    x: .value("笔数", points[i].idx),
                    y: .value("Run", points[i].run)
                )
                .foregroundStyle(Color.blue)
            }
            RuleMark(y: .value("0 轴", 0))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXAxis { Self.axisCategoryX() }
    }

    /// v15.19 batch27 · 心理风险标签命中分布（读取缓存 · body 不重算）
    private func psychTagsChart(_ entries: [(tag: EmotionAutoTagger.Tag, count: Int)]) -> some View {
        Chart {
            ForEach(entries.indices, id: \.self) { i in
                BarMark(
                    x: .value("标签", entries[i].tag.displayName),
                    y: .value("命中", entries[i].count)
                )
                .foregroundStyle(Color.orange.opacity(0.7))
            }
        }
        .chartXAxis { Self.axisCategoryX() }
    }

    /// 一次性预算 · loadMockReview 调用 · 与 streakMetrics 同 sign-run 模式
    fileprivate static func computeStreakRunPoints(from positions: [ClosedPosition]) -> [(idx: Int, run: Int)] {
        let sorted = positions.sorted { $0.closeTime < $1.closeTime }
        var run = 0
        var prevWin: Bool? = nil
        var points: [(idx: Int, run: Int)] = []
        var idx = 0
        for p in sorted {
            let pnl = p.realizedPnL
            if pnl == 0 { continue }
            let isWin = pnl > 0
            if let prev = prevWin, prev != isWin { run = 0 }
            run += isWin ? 1 : -1
            idx += 1
            points.append((idx, run))
            prevWin = isWin
        }
        return points
    }

    /// 一次性预算 · 6 类标签命中计数（保留全部 6 类便于柱状对齐 · 0 也展示）
    fileprivate static func computePsychTagCounts(from positions: [ClosedPosition]) -> [(tag: EmotionAutoTagger.Tag, count: Int)] {
        var counts: [EmotionAutoTagger.Tag: Int] = [:]
        for (_, tags) in EmotionAutoTagger.tagAll(positions) {
            for t in tags { counts[t, default: 0] += 1 }
        }
        return EmotionAutoTagger.Tag.allCases.map { tag in
            (tag: tag, count: counts[tag] ?? 0)
        }
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
    let streak: ReviewAnalytics.StreakMetrics
    let riskAdjusted: ReviewAnalytics.RiskAdjustedMetrics
    let profitability: ReviewAnalytics.ProfitabilityMetrics
    /// 累积缓存 · 防 chartCard 每次 body re-eval 重算（10K 持仓时显著）
    let streakRunPoints: [(idx: Int, run: Int)]
    let psychTagCounts: [(tag: EmotionAutoTagger.Tag, count: Int)]
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
