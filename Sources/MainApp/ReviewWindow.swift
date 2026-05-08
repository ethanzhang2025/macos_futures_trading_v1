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
    /// v15.20 batch60 · 区间筛选持久化（rawTag 字符串 · UserDefaults · 重启保留）
    /// 默认 "all" · 反解析失败 fallback .all
    @AppStorage("viewState.v1.review.dateFilter") private var dateFilterRawTag: String = "all"
    /// 全量 closedPositions · 启动一次加载 · 区间切换不重拉数据
    @State private var allPositions: [ClosedPosition] = []
    @State private var totalTradeCount: Int = 0

    /// v15.20 batch65 · chartCard 全屏放大查看（trader 专注分析单张图）
    /// v15.21 batch123 · 加 index/total · 支持 ←/→ 切前后图
    @State private var zoomedCard: ZoomedCard?
    /// v15.23 batch64 · 帮助面板（⌘⇧? · 4 大新窗口 UX 一致）
    @State private var showHelpSheet: Bool = false

    /// v15.23 batch203 · 合约 filter（与 dateFilter 互补 · 自动从 allPositions 列举）
    @State private var filterInstrument: String? = nil

    /// v15.23 batch205 · 跨窗口跳主图
    @Environment(\.openWindow) private var openWindow

    private struct ZoomedCard: Identifiable {
        var id: String { title }
        let title: String
        let subtitle: String
        let content: AnyView
        let index: Int      // v15.21 batch123 · 当前在 specs 中的索引
        let total: Int      // v15.21 batch123 · specs 总数（用于循环边界）
    }

    /// v15.20 batch60 · 从 AppStorage rawTag 解析（dateFilter 计算属性 · 写入用 setDateFilter）
    private var dateFilter: ReviewDateFilter {
        ReviewDateFilter.fromRawTag(dateFilterRawTag) ?? .all
    }
    private func setDateFilter(_ filter: ReviewDateFilter) {
        dateFilterRawTag = filter.rawTag
    }

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
        .onChange(of: dateFilterRawTag) { _ in
            recomputeSummary()
            // v15.21 batch133 · 区间切换 toast 反馈（trader 不知道切了 Picker 数据真的变了 · 显示新区间统计）
            if let s = summary {
                Toast.info("区间已切换：\(dateFilter.displayName)",
                           "闭合 \(s.closedPositions.count) 笔 · 总 PnL ¥\(signedDecimal(s.monthlyPnL.totalPnL))")
            }
        }
        // v15.23 batch203 · 合约 filter 切换 → 重算 summary + toast
        .onChange(of: filterInstrument) { _ in
            recomputeSummary()
            if let s = summary {
                let label = filterInstrument ?? "全部合约"
                Toast.info("合约 filter：\(label)",
                           "闭合 \(s.closedPositions.count) 笔 · 总 PnL ¥\(signedDecimal(s.monthlyPnL.totalPnL))")
            }
        }
        .sheet(item: $zoomedCard) { card in
            zoomedCardView(card)
        }
        .sheet(isPresented: $showHelpSheet) {
            helpSheet
        }
        .background(
            Button("") { showHelpSheet = true }
                .keyboardShortcut("?", modifiers: [.command, .shift])
                .opacity(0)
        )
    }

    // MARK: - v15.23 batch64 · 帮助面板（4 大新窗口 UX 一致）

    private static let helpGroups: [(String, [(String, String)])] = [
        ("📅 区间筛选", [
            ("toolbar 区间 Menu", "全部 / 7 天 / 30 天 / 当月 / 月份 / 季度"),
            ("toolbar 合约 Menu (batch203)", "全部 / 各合约（自动从 positions 列举 + 笔数）· 与区间 filter 互补"),
            ("跳主图 button (batch205)", "选中合约后 → 在主图查看（chart.line 图标 · 仅 filter 时显示）"),
            ("Toast 反馈", "切换后顶部提示新区间数据量"),
        ]),
        ("📊 12 张图（v15.23 闭环）", [
            ("月度盈亏", "按月聚合 · 总 PnL 趋势"),
            ("分布直方", "PnL 桶 · 盈/亏笔数对比"),
            ("胜率曲线", "累积胜率 · 终值"),
            ("品种矩阵", "各合约绩效对比"),
            ("持仓时间", "中位 / 平均 / 直方"),
            ("最大回撤", "MDD 曲线"),
            ("盈亏比", "ProfitLossRatio + 胜亏数"),
            ("时段分析", "5 段交易时段绩效"),
            ("连胜连败", "连续胜负曲线 · 极值"),
            ("心理标签", "EmotionAutoTagger 6 类"),
            ("日历热力图（v15.23 第 11）", "每日盈亏 · 周历网格"),
            ("时长×盈亏（v15.23 第 12）", "散点图 · 多绿空蓝"),
        ]),
        ("🔍 全屏放大", [
            ("点击 chartCard", "全屏放大查看（trader 专注分析）"),
            ("← / →", "切前后图（循环 · 不必关闭再开）"),
            ("Esc / 关闭", "退出全屏"),
            ("PNG 导出", "全屏放大后一键保存图片"),
        ]),
        ("📝 报告导出（v15.23 batch196）", [
            ("⌘E", "导出本月 markdown 月报"),
            ("⌘⌥E", "导出最近 7 天周报（与月报互补 · trader 周复盘节奏）"),
            ("⌘⇧E", "导出全部 12 张 chartCard PNG 到目录"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 复盘工作台全功能").font(.title2).bold()
                Spacer()
                Button("关闭") { showHelpSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.helpGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.0).font(.headline)
                            ForEach(group.1, id: \.0) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(item.0)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 200, alignment: .leading)
                                    Text(item.1).font(.system(size: 12))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 580, idealWidth: 680, minHeight: 480, idealHeight: 620)
    }

    /// v15.20 batch65/71 · 全屏放大 chartCard sheet（关闭 + PNG 导出 · trader 放大后立刻分享）
    /// v15.21 batch123 · 加 ←/→ 切前后图（trader 复盘连续翻 · 不必关闭再开）
    @ViewBuilder
    private func zoomedCardView(_ card: ZoomedCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title).font(.title2).bold()
                Text("\(card.index + 1) / \(card.total)").font(.caption).foregroundColor(.secondary)
                Spacer()
                // v15.21 batch123 · ← / → 切前后图（循环边界 · 0 → total-1 反之亦然）
                Button {
                    navigateZoomedCard(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help("上一张（←）")
                Button {
                    navigateZoomedCard(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help("下一张（→）")
                Button {
                    exportChartCardPNG(title: card.title, subtitle: card.subtitle, content: card.content)
                } label: {
                    Label("导出 PNG", systemImage: "camera")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .help("导出全屏视图为 PNG（⌘S）")
                Button("关闭") { zoomedCard = nil }
                    .keyboardShortcut(.cancelAction)
            }
            Text(card.subtitle)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            card.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
    }

    /// v15.21 batch123 · 全屏 ←/→ 切前后图（循环边界 · 当前 summary 不变 · 只换 zoomedCard 内容）
    @MainActor
    private func navigateZoomedCard(by step: Int) {
        guard let current = zoomedCard, let s = summary else { return }
        let specs = reviewCardSpecs(s)
        guard !specs.isEmpty else { return }
        let next = ((current.index + step) % specs.count + specs.count) % specs.count
        let spec = specs[next]
        zoomedCard = ZoomedCard(title: spec.title, subtitle: spec.subtitle,
                                content: spec.content, index: next, total: specs.count)
    }

    /// 启动加载 · 拉一次 trades + match · 后续仅按 dateFilter 重算 summary
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

    /// 按 dateFilter 过滤 + 重算 summary（同步 · MainActor · 0 IO）
    /// v15.23 batch203 · 加 instrument filter（dateFilter 之后再 filter）
    @MainActor
    private func recomputeSummary() {
        var filtered = ReviewDateFilterEngine.filter(allPositions, by: dateFilter)
        if let inst = filterInstrument {
            filtered = filtered.filter { $0.instrumentID == inst }
        }
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
            psychTagCounts: Self.computePsychTagCounts(from: filtered),
            dailyPnL: ReviewAnalytics.dailyPnL(from: filtered)
        )
    }

    /// 当前 positions 涵盖的所有月份（升序）· 用于 Picker 选项 · 委托 Engine
    private var availableMonths: [String] {
        ReviewDateFilterEngine.availableMonths(allPositions)
    }

    /// 当前 positions 涵盖的所有季度（升序）· v15.20 batch56
    private var availableQuarters: [String] {
        ReviewDateFilterEngine.availableQuarters(allPositions)
    }

    @ViewBuilder
    private func content(_ s: ReviewSummary) -> some View {
        VStack(spacing: 0) {
            header(s)
            Divider()
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    // v15.21 batch123 · chartCard 数据驱动 · 全屏 ←/→ 切换前后图依赖此数组顺序
                    ForEach(Array(reviewCardSpecs(s).enumerated()), id: \.offset) { idx, spec in
                        chartCard(spec.title, subtitle: spec.subtitle, index: idx, total: reviewCardSpecs(s).count) {
                            spec.content
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    /// v15.21 batch123 · chartCard 数据驱动数组 · 单一 source-of-truth · grid 渲染 + zoomedCard 切换共用
    private struct ReviewCardSpec {
        let title: String
        let subtitle: String
        let content: AnyView
    }

    private func reviewCardSpecs(_ s: ReviewSummary) -> [ReviewCardSpec] {
        [
            .init(title: "月度盈亏",
                  subtitle: "MonthlyPnL · \(s.monthlyPnL.buckets.count) 月跨度",
                  content: AnyView(monthlyPnLChart(s.monthlyPnL))),
            .init(title: "分布直方",
                  subtitle: "PnLDistribution · \(s.pnlDistribution.bins.count) 桶 · 盈\(s.pnlDistribution.positiveCount)/亏\(s.pnlDistribution.negativeCount)",
                  content: AnyView(pnlDistributionChart(s.pnlDistribution))),
            .init(title: "胜率曲线",
                  subtitle: "WinRateCurve · 终值 \(pct(s.winRateCurve.finalWinRate))",
                  content: AnyView(winRateChart(s.winRateCurve))),
            .init(title: "品种矩阵",
                  subtitle: "InstrumentMatrix · \(s.instrumentMatrix.cells.count) 合约",
                  content: AnyView(instrumentMatrixView(s.instrumentMatrix))),
            .init(title: "持仓时间",
                  subtitle: "中位 \(durationLabel(s.holdingDuration.medianSeconds)) · 平均 \(durationLabel(s.holdingDuration.averageSeconds))",
                  content: AnyView(holdingDurationChart(s.holdingDuration))),
            .init(title: "最大回撤",
                  subtitle: "MaxDrawdown · ¥-\(decimal(s.maxDrawdown.maxDrawdown))",
                  content: AnyView(maxDrawdownChart(s.maxDrawdown))),
            .init(title: "盈亏比",
                  subtitle: "ProfitLossRatio · \(decimal(s.profitLossRatio.ratio)) · 胜 \(s.profitLossRatio.winCount) / 亏 \(s.profitLossRatio.lossCount)",
                  content: AnyView(profitLossRatioView(s.profitLossRatio))),
            .init(title: "时段分析",
                  subtitle: "SessionPnL · \(s.sessionPnL.buckets.count) 段",
                  content: AnyView(sessionPnLChart(s.sessionPnL))),
            .init(title: "连胜连败曲线",
                  subtitle: "Streak · 最长连胜 \(s.streak.maxWinningStreak) / 最长连败 \(s.streak.maxLosingStreak)",
                  content: AnyView(streakRunChart(s.streakRunPoints))),
            .init(title: "心理风险标签",
                  subtitle: "EmotionAutoTagger · 6 类自动建议",
                  content: AnyView(psychTagsChart(s.psychTagCounts))),
            // v15.23 batch48 · 第 11 图 · 日历盈亏热力图（trader 一年盈亏直观）
            .init(title: "日历热力图",
                  subtitle: "DailyPnL · \(s.dailyPnL.tradingDays) 交易日 · 盈\(s.dailyPnL.winningDays) 亏\(s.dailyPnL.losingDays)",
                  content: AnyView(dailyPnLHeatmap(s.dailyPnL))),
            // v15.23 batch49 · 第 12 图 · 持仓时长 vs PnL 散点图（trader 检测"持仓越久越亏"模式）
            .init(title: "时长 × 盈亏",
                  subtitle: "Scatter · \(s.closedPositions.count) 笔 · 多空区分",
                  content: AnyView(holdingPnLScatter(s.closedPositions))),
        ]
    }

    private func header(_ s: ReviewSummary) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 20) {
                Text("📊 复盘工作台").font(.title2).bold()
                Divider().frame(height: 24)
                // v15.20 batch56 · 区间筛选 Menu（v15.20 batch60 · @AppStorage rawTag 持久化）
                Menu(dateFilter.displayName) {
                    Button("全部") { setDateFilter(.all) }
                    Divider()
                    Button("近 7 天") { setDateFilter(.last7Days) }
                    Button("近 30 天") { setDateFilter(.last30Days) }
                    Button("当月") { setDateFilter(.currentMonth) }
                    if !availableMonths.isEmpty {
                        Divider()
                        Menu("月份") {
                            ForEach(availableMonths, id: \.self) { m in
                                Button(m) { setDateFilter(.month(m)) }
                            }
                        }
                    }
                    if !availableQuarters.isEmpty {
                        Menu("季度") {
                            ForEach(availableQuarters, id: \.self) { q in
                                Button(q) { setDateFilter(.quarter(q)) }
                            }
                        }
                    }
                }
                .frame(width: 110)
                .help("筛选复盘区间 · 全部 / 7 天 / 30 天 / 当月 / 月份 / 季度")

                // v15.23 batch203 · 合约 filter Menu（自动列举 allPositions 中的所有 instrumentID）
                let instruments = Array(Set(allPositions.map { $0.instrumentID })).sorted()
                Menu(filterInstrument ?? "全部合约") {
                    Button("\(filterInstrument == nil ? "✓ " : "")全部合约") { filterInstrument = nil }
                    if !instruments.isEmpty { Divider() }
                    ForEach(instruments, id: \.self) { id in
                        let isOn = filterInstrument == id
                        let n = allPositions.filter { $0.instrumentID == id }.count
                        Button("\(isOn ? "✓ " : "")\(id) · \(n)") { filterInstrument = id }
                    }
                }
                .frame(width: 130)
                .help("按合约筛选复盘 · 与区间 filter 互补 · 自动从 closed positions 列举")

                // v15.23 batch205 · 当前合约 filter 时 · 加跳主图 button（trader 看绩效后想去图上验证）
                if let inst = filterInstrument {
                    Button {
                        openWindow(id: "chart")
                        NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst)
                        Toast.info("已切到主图", "\(inst)")
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.borderless)
                    .help("在主图查看「\(inst)」（v15.23 batch205）")
                }

                stat("成交", "\(s.tradeCount) 笔")
                stat("闭合", "\(s.closedPositions.count) 笔")
                stat("总 PnL", "¥\(signedDecimal(s.monthlyPnL.totalPnL))")
                stat("胜率", pct(s.winRateCurve.finalWinRate))
                stat("最长连胜", "\(s.streak.maxWinningStreak) 笔")
                stat("最长连败", "\(s.streak.maxLosingStreak) 笔")
                stat("当前", currentStreakLabel(s.streak))
                Spacer()
                // v15.21 batch108 · 复制 header 全部统计行（trader 月底直接贴邮件/IM）
                Button {
                    Pasteboard.copy(headerStatsText(s))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("复制全部 stat 行（成交/闭合/总 PnL/胜率/Sharpe/Sortino 等 · 一段文本 · ⌘⇧C）")
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
                    .help("生成本月 Markdown 复盘报告 · 含全套指标 + 心理标签 + 品种/时段分布（⌘E）")
                    .keyboardShortcut("e", modifiers: [.command])
                // v15.23 batch196 · 周报（最近 7 天 · 与月报互补）
                Button("导出周报…") { exportWeeklyReport(s) }
                    .help("生成最近 7 天 Markdown 周报告（⌘⌥E · trader 周复盘节奏）")
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("导出全部图…") { exportAllChartCards(s) }
                    .help("一键导出全部 12 张 chartCard 为 PNG 到选定目录 · 月底归档（⌘⇧E · v15.23 加日历热力 + 时长散点）")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                // v15.21 batch114 · ⌘R 重新加载复盘数据（trader 实时数据更新或纠错重算）
                Button {
                    summary = nil
                    Task { await loadMockReview() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: [.command])
                .help("重新加载复盘数据（⌘R）· 重算所有指标")
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

        // 12 张图 · 与 content() 内 chartCard 顺序一致（v15.23 batch48-49 加日历热力 + 时长散点）
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
            ("心理风险标签", AnyView(psychTagsChart(s.psychTagCounts))),
            ("日历热力图", AnyView(dailyPnLHeatmap(s.dailyPnL))),
            ("时长×盈亏", AnyView(holdingPnLScatter(s.closedPositions))),
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

    /// v15.23 batch196 · 周度 Markdown 复盘报告导出（最近 7 天 · trader 周复盘节奏）
    @MainActor
    private func exportWeeklyReport(_ s: ReviewSummary) {
        let panel = NSSavePanel()
        panel.title = "导出周复盘报告"
        panel.allowedContentTypes = [.plainText]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        let stamp = fmt.string(from: Date())
        panel.nameFieldStringValue = "复盘周报_截至\(stamp).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = MonthlyReportGenerator.generateWeekly(positions: s.closedPositions)
        do {
            try md.data(using: .utf8)?.write(to: url, options: .atomic)
            Toast.info("导出成功", "已生成最近 7 天周报到 \(url.lastPathComponent)。")
        } catch {
            Toast.error("导出失败", error)
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

    /// v15.21 batch108 · 把 header 两行 stat 合成一段文本（按区间筛选 · trader 月底贴邮件/IM）
    private func headerStatsText(_ s: ReviewSummary) -> String {
        let lines: [String] = [
            "📊 复盘统计 · 区间：\(dateFilter.displayName)",
            "成交 \(s.tradeCount) 笔 · 闭合 \(s.closedPositions.count) 笔 · 总 PnL ¥\(signedDecimal(s.monthlyPnL.totalPnL)) · 胜率 \(pct(s.winRateCurve.finalWinRate))",
            "最长连胜 \(s.streak.maxWinningStreak) 笔 · 最长连败 \(s.streak.maxLosingStreak) 笔 · 当前 \(currentStreakLabel(s.streak))",
            "Sharpe \(String(format: "%.2f", s.riskAdjusted.sharpeRatio)) · Sortino \(String(format: "%.2f", s.riskAdjusted.sortinoRatio)) · Calmar \(String(format: "%.2f", s.riskAdjusted.calmarRatio)) · Recovery \(String(format: "%.2f", s.riskAdjusted.recoveryFactor))",
            "ProfitFactor \(String(format: "%.2f", s.profitability.profitFactor)) · Expectancy ¥\(signedDecimal(s.profitability.expectancy)) · 最大单笔盈 ¥\(decimal(s.profitability.largestWin)) · 最大单笔亏 ¥\(decimal(s.profitability.largestLoss))",
        ]
        return lines.joined(separator: "\n")
    }

    /// 8 图统一卡片容器（标题 + subtitle + 内容区）· v15.19 batch41 加 📷 PNG 导出按钮
    /// v15.21 batch123 · 加 index/total 用于全屏 ←/→ 切换 + 双击进全屏
    @ViewBuilder
    private func chartCard<Content: View>(
        _ title: String,
        subtitle: String,
        index: Int,
        total: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let body = content()
        let chart = VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Button {
                    zoomedCard = ZoomedCard(title: title, subtitle: subtitle, content: AnyView(body), index: index, total: total)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("放大查看本图（双击 card 也可）")
                Button {
                    exportChartCardPNG(title: title, subtitle: subtitle, content: body)
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
            body
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(minHeight: 220)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        // v15.21 batch123 · 双击 chartCard 全屏（与 ↗ 按钮同效 · trader 流畅）
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            zoomedCard = ZoomedCard(title: title, subtitle: subtitle, content: AnyView(body), index: index, total: total)
        }
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

    /// v15.20 batch81 · 加载错误视图 + "重试" 按钮（trader 暂态错误恢复）
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("复盘加载失败").font(.headline)
            Text(msg).font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("重试") {
                loadError = nil
                Task { await loadMockReview() }
            }
            .keyboardShortcut(.defaultAction)
            .help("重新尝试加载复盘数据 · 网络/IO 暂态错误时点此恢复")
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

    /// v15.23 batch48 · 日历盈亏热力图（第 11 图 · 一格一天 · 颜色按 PnL 强度）
    /// 布局：每周 7 列（周一→周日）· 行数自适应 · 鼠标悬停显示当日明细
    /// 颜色：盈利绿色 / 亏损红色 / 平 / 无交易 灰色 · 强度按 |pnl| / maxAbs
    private func dailyPnLHeatmap(_ daily: DailyPnL) -> some View {
        let cellSize: CGFloat = 16
        let cellSpacing: CGFloat = 3
        let cal = Calendar(identifier: .gregorian)
        let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let lookup: [Date: DailyPnLBucket] = Dictionary(
            uniqueKeysWithValues: daily.buckets.map { ($0.day, $0) }
        )
        // 计算填充范围：从首日所在周一到末日所在周日
        guard let first = daily.buckets.first?.day,
              let last = daily.buckets.last?.day else {
            return AnyView(
                VStack {
                    Spacer()
                    Text("（暂无交易日数据）")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        let startWeekday = (cal.component(.weekday, from: first) + 5) % 7  // 一=0..日=6
        let firstMonday = cal.date(byAdding: .day, value: -startWeekday, to: first) ?? first
        let endWeekday = (cal.component(.weekday, from: last) + 5) % 7
        let lastSunday = cal.date(byAdding: .day, value: 6 - endWeekday, to: last) ?? last
        let totalDays = cal.dateComponents([.day], from: firstMonday, to: lastSunday).day ?? 0
        let weekCount = (totalDays + 1) / 7
        let maxAbsDouble = (daily.maxAbsPnL as NSDecimalNumber).doubleValue
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                // 顶部图例
                HStack(spacing: 8) {
                    Text("色阶：").font(.caption2).foregroundColor(.secondary)
                    ForEach(0..<5) { level in
                        Rectangle()
                            .fill(heatColor(level: Double(level) / 4, isWin: true))
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                    }
                    Text("盈").font(.caption2).foregroundColor(.green)
                    Spacer().frame(width: 12)
                    ForEach(0..<5) { level in
                        Rectangle()
                            .fill(heatColor(level: Double(level) / 4, isWin: false))
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                    }
                    Text("亏").font(.caption2).foregroundColor(.red)
                }
                // 网格：行 = 周一-周日 / 列 = 周
                HStack(alignment: .top, spacing: cellSpacing) {
                    // 左侧周几标签
                    VStack(alignment: .trailing, spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(weekdayLabels[i])
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 14, height: cellSize)
                        }
                    }
                    // 滚动区
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: cellSpacing) {
                            ForEach(0..<weekCount, id: \.self) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(0..<7, id: \.self) { weekday in
                                        let day = cal.date(byAdding: .day, value: week * 7 + weekday, to: firstMonday) ?? firstMonday
                                        let normalized = cal.startOfDay(for: day)
                                        let bucket = lookup[normalized]
                                        heatCell(bucket: bucket, day: day, maxAbs: maxAbsDouble, size: cellSize)
                                    }
                                }
                            }
                        }
                    }
                }
                // 底部统计
                HStack(spacing: 14) {
                    Text("总计 \(daily.tradingDays) 交易日")
                        .font(.caption).foregroundColor(.secondary)
                    Text("总 PnL ¥\(signedDecimal(daily.totalPnL))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(daily.totalPnL >= 0 ? .green : .red)
                    if daily.tradingDays > 0 {
                        Text("胜率 \(daily.winningDays)/\(daily.tradingDays) = \(String(format: "%.1f", Double(daily.winningDays) / Double(daily.tradingDays) * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
        )
    }

    private func heatStyle(bucket: DailyPnLBucket?, day: Date, maxAbs: Double) -> (Color, String) {
        if let b = bucket {
            let pnl = (b.realizedPnL as NSDecimalNumber).doubleValue
            let level = maxAbs > 0 ? min(1.0, abs(pnl) / maxAbs) : 0
            let dateStr = Self.formatDay(day)
            return (heatColor(level: level, isWin: b.realizedPnL > 0),
                    "\(dateStr) · \(b.tradeCount) 笔 · ¥\(signedDecimal(b.realizedPnL))")
        }
        return (Color.secondary.opacity(0.08), Self.formatDay(day) + " · 无交易")
    }

    @ViewBuilder
    private func heatCell(bucket: DailyPnLBucket?, day: Date, maxAbs: Double, size: CGFloat) -> some View {
        let style = heatStyle(bucket: bucket, day: day, maxAbs: maxAbs)
        Rectangle()
            .fill(style.0)
            .frame(width: size, height: size)
            .cornerRadius(2)
            .help(style.1)
    }

    private func heatColor(level: Double, isWin: Bool) -> Color {
        let opacity = 0.15 + level * 0.85
        return isWin
            ? Color.green.opacity(opacity)
            : Color.red.opacity(opacity)
    }

    private static func formatDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: d)
    }

    /// v15.23 batch49 · 持仓时长 vs PnL 散点图（第 12 图）
    /// X = 持仓分钟（线性 · 自适应范围）· Y = realizedPnL · 颜色按 side（多绿空蓝）
    /// trader 用：判断"持仓越久越亏"（趋势线下倾）/ "持仓越久越赚"（趋势线上倾）
    private func holdingPnLScatter(_ positions: [ClosedPosition]) -> some View {
        Chart {
            ForEach(positions) { p in
                let minutes = p.holdingSeconds / 60
                let pnl = (p.realizedPnL as NSDecimalNumber).doubleValue
                PointMark(
                    x: .value("分钟", minutes),
                    y: .value("PnL", pnl)
                )
                .foregroundStyle(
                    p.side == .long
                        ? Color.green.opacity(0.65)
                        : Color.blue.opacity(0.65)
                )
                .symbolSize(p.realizedPnL == 0 ? 30 : 60)
            }
            // 0 轴参考线
            RuleMark(y: .value("0 轴", 0))
                .foregroundStyle(Color.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartLegend(position: .top, alignment: .leading) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("多").font(.caption2)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("空").font(.caption2)
                }
                Text("X：持仓分钟 · Y：PnL").font(.caption2).foregroundColor(.secondary)
            }
        }
        .chartXAxisLabel("分钟", position: .bottom)
        .chartYAxisLabel("PnL", position: .leading)
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
    /// v15.23 batch48 · 第 11 图 · 日历盈亏热力图
    let dailyPnL: DailyPnL
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
