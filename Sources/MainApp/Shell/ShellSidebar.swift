// MainApp · Shell · v17.0 PoC Step 6
// 左侧 Sidebar · 5 section（自选 / 板块 / 持仓 / 异动 / 训练）
// v17.3 训练真数据 · v17.21 持仓真数据（SimulatedTradingStore）· 自选 + 板块 + 异动仍 mock

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import TradingCore
import Shared
import AlertCore

struct ShellSidebar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    /// v17.70 · 预警历史 store（mini section · 5 条最近触发）
    @Environment(\.storeManager) private var storeManager
    /// v17.82 · 异动 / 预警行点击 → 切主图 K 线（与 ⌘⌥A AnomalyMonitorWindow 同机制）
    @Environment(\.openWindow) private var openWindow
    /// v17.3 · 训练 log 真实数据（启动时一次性加载 · 后续重启刷新）
    @State private var trainingLog: TrainingSessionLog = TrainingLogPersistence.load()
    /// v17.21 · 模拟交易 snapshot 真实数据（持仓 + 现价 · UserDefaults didChange 跟随）
    @State private var tradingSnapshot: SimulatedTradingSnapshot? = SimulatedTradingStore.load()
    /// v17.57 · F6 跳焦自选 高亮反馈（1.5s 自动消失）
    @State private var watchlistHighlight: Bool = false
    @State private var watchlistHighlightTask: Task<Void, Never>?
    /// v17.64 · sidebar 5 section 自定义顺序/显隐
    @State private var sidebarLayout: SidebarLayoutSettings = SidebarLayoutStore.load()
    @State private var showSidebarLayoutSheet: Bool = false
    /// v17.70 · 预警历史最近 5 条（启动 + UserDefaults didChange 刷新）
    @State private var recentAlerts: [AlertHistoryEntry] = []

    /// v17.88 · 异动 top 5 缓存（Timer 30s 刷新 · 显示扫描时间）
    @State private var topAnomaliesCache: [AnomalyEvent] = []
    @State private var lastAnomalyScanAt: Date = Date()
    /// Timer publisher · 30s 一次触发 anomaly 重新扫描（trader 看"系统活着"）
    private let anomalyTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// v17.89 · 自选合约真数据（接续 v17.77 ⌘K · 同 SQLiteWatchlistBookStore 数据源 · 最多 5 条）
    @State private var sidebarWatchSymbols: [String] = []

    var body: some View {
        List {
            ForEach(sidebarLayout.visibleSections, id: \.self) { sec in
                section(for: sec)
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("📋 自定义 section…") { showSidebarLayoutSheet = true }
        }
        .sheet(isPresented: $showSidebarLayoutSheet) {
            ShellSidebarLayoutSheet(
                isPresented: $showSidebarLayoutSheet,
                onApply: { sidebarLayout = $0 }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // v17.21 · TradingWindow 改持仓时 Sidebar 实时跟（与 chartTheme/HUD 同模式）
            if let snap = SimulatedTradingStore.load() { tradingSnapshot = snap }
            // v17.64 · 跨窗口 sidebar 设置同步
            let layout = SidebarLayoutStore.load()
            if layout != sidebarLayout { sidebarLayout = layout }
        }
        // v17.57 · F6 跳焦反馈：自选 section 临时高亮 1.5s
        .onChange(of: shellVM.sidebarFocusTrigger) { _ in
            watchlistHighlight = true
            watchlistHighlightTask?.cancel()
            watchlistHighlightTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { watchlistHighlight = false }
            }
        }
        // v17.70 · 预警 mini section 启动加载（用户切回 Shell 时自然刷新）
        .task {
            await refreshAlertsAsync()
            await refreshWatchlistAsync()
        }
        // v17.88 · 启动时扫一次 + Timer 30s tick
        .onAppear {
            refreshAnomalies()
        }
        .onReceive(anomalyTimer) { _ in
            refreshAnomalies()
        }
    }

    private func refreshAnomalies() {
        let result = AnomalyDetector.scan()
        topAnomaliesCache = Array(result.events.prefix(5))
        lastAnomalyScanAt = Date()
    }

    /// v17.89 · 加载 watchlistBook 第一个 group 的合约（取前 5 · 与 ⌘K 命令面板同数据源）
    private func refreshWatchlistAsync() async {
        guard let store = storeManager?.watchlistBook else { return }
        let book = (try? await store.load()) ?? nil
        guard let book else { return }
        let firstGroupSymbols = book.groups.first?.instrumentIDs ?? []
        let top = Array(firstGroupSymbols.prefix(5))
        await MainActor.run { sidebarWatchSymbols = top }
    }

    @ViewBuilder
    private func section(for sec: SidebarSection) -> some View {
        switch sec {
        case .watchlist:    watchlistSection
        case .sector:       sectorSection
        case .position:     positionSection
        case .anomaly:      anomalySection
        case .training:     trainingSection
        case .alertHistory: alertHistorySection
        }
    }

    // MARK: - 自选 mini

    /// v17.89 · 自选 mini 实际显示数据（优先 watchlistBook 真自选 · 空时 fallback mock）
    private var effectiveWatchlist: [WatchItem] {
        if !sidebarWatchSymbols.isEmpty {
            // 真自选合约 · price/change 仍 mock（CTP 接入前无真行情 · 占位与 mockWatchlist 同风格）
            return sidebarWatchSymbols.map { sym in
                Self.fallbackWatchItem(for: sym)
            }
        }
        return mockWatchlist
    }

    private var watchlistSection: some View {
        Section {
            ForEach(effectiveWatchlist, id: \.symbol) { item in
                Button {
                    openWindow(id: "chart")
                    NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: item.symbol)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(item.symbol)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Text(item.price)
                            .font(DesignTokens.Typography.mono)
                        Text(item.change)
                            .font(DesignTokens.Typography.monoSm)
                            .foregroundColor(item.change.hasPrefix("+") ? .red : .green)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(item.symbol) · 点击切主图")
            }
        } header: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label("自选 (\(effectiveWatchlist.count))", systemImage: "star.fill")
                    .sidebarSectionHeader()
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary, DesignTokens.StatusColor.warning)
                Spacer()
                // F6 跳焦反馈 chip · 临时高亮 1.5s · 仅此场景保留 chip（"真"chip 已去除冗余）
                if watchlistHighlight {
                    Text("F6")
                        .chipStyle(background: DesignTokens.StatusColor.warning.opacity(0.85))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: watchlistHighlight)
        }
    }

    /// v17.89 · 真自选合约的 mock 价格占位（CTP 接入前 · 与 mockWatchlist 同风格）
    /// hash 派生稳定值 · 同合约每次显示一致 · 避免 view re-eval 抖动
    private static func fallbackWatchItem(for symbol: String) -> WatchItem {
        let hash = abs(symbol.hashValue)
        let priceVal = 1000 + (hash % 8000)
        let changeRaw = Double((hash % 400) - 200) / 100.0    // -2.00% ~ +2.00%
        let sign = changeRaw >= 0 ? "+" : ""
        let change = "\(sign)\(String(format: "%.2f", changeRaw))%"
        return WatchItem(symbol: symbol, price: "\(priceVal)", change: change)
    }

    // MARK: - 板块（v17.90 · 接 SectorPresets 真数据 · 11 板块按 |avg Δ%| desc 取前 6）

    private struct SectorRow: Identifiable {
        let sector: Sector
        let avgChangePct: Double
        var id: String { sector.id }
    }

    private var topSectorRows: [SectorRow] {
        let rows: [SectorRow] = Sector.allCases.compactMap { sec in
            let list = SectorPresets.instruments(in: sec)
            guard !list.isEmpty else { return nil }
            let avg = list.map(\.changePct).reduce(0, +) / Double(list.count)
            return SectorRow(sector: sec, avgChangePct: avg)
        }
        return Array(rows.sorted { abs($0.avgChangePct) > abs($1.avgChangePct) }.prefix(6))
    }

    private var sectorSection: some View {
        Section {
            ForEach(topSectorRows) { row in
                Button {
                    openWindow(id: "sector")
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: row.sector.icon)
                            .font(DesignTokens.Typography.label)
                            .foregroundColor(DesignTokens.StatusColor.muted)
                        Text(row.sector.displayName)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Text(Self.formatSectorChange(row.avgChangePct))
                            .font(DesignTokens.Typography.monoSm)
                            .foregroundColor(row.avgChangePct >= 0 ? .red : .green)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(row.sector.displayName) 板块均涨幅 \(Self.formatSectorChange(row.avgChangePct)) · 点击打开板块联动窗口")
            }
        } header: {
            Label("板块 (\(topSectorRows.count))", systemImage: "square.grid.2x2.fill")
                .sidebarSectionHeader()
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary, DesignTokens.StatusColor.info)
        }
    }

    /// 板块涨跌幅显示（+0.42% / -0.18%）
    private static func formatSectorChange(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    // MARK: - 持仓速览（v17.21 接 SimulatedTradingStore 真实数据）

    private var realPositions: [Position] {
        tradingSnapshot?.positions ?? []
    }

    private func positionPnL(_ pos: Position) -> Decimal {
        guard let lastPrice = tradingSnapshot?.instrumentLastPrice[pos.instrumentID] else { return 0 }
        return pos.floatingPnL(currentPrice: lastPrice)
    }

    /// v17.23 · 总浮盈（所有持仓求和 · header chip 显示）
    private var totalFloatingPnL: Double {
        realPositions.reduce(0.0) { acc, pos in
            acc + NSDecimalNumber(decimal: positionPnL(pos)).doubleValue
        }
    }

    private var positionSection: some View {
        Section {
            ForEach(realPositions, id: \.instrumentID) { pos in
                Button {
                    // v17.91 · 点击持仓 → 切主图 K 线（同 watchlistInstrumentSelected 通道）
                    openWindow(id: "chart")
                    NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: pos.instrumentID)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(pos.instrumentID)
                            .font(DesignTokens.Typography.mono)
                        Text(pos.direction.displayName)
                            .chipStyle(
                                foreground: pos.direction == .long ? .red : .green,
                                background: (pos.direction == .long ? Color.red : Color.green).opacity(0.18)
                            )
                        Text("\(pos.volume)")
                            .font(DesignTokens.Typography.monoSm)
                            .foregroundColor(DesignTokens.StatusColor.muted)
                        Spacer()
                        let pnl = positionPnL(pos)
                        let pnlVal = NSDecimalNumber(decimal: pnl).doubleValue
                        Text(String(format: "%@¥%.0f", pnlVal >= 0 ? "+" : "", pnlVal))
                            .font(DesignTokens.Typography.mono)
                            .foregroundColor(pnlVal >= 0 ? .red : .green)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(pos.instrumentID) · \(pos.direction.displayName) \(pos.volume) 手 · 点击切主图")
            }
            if realPositions.isEmpty {
                Button {
                    openWindow(id: "trading")
                } label: {
                    Text("无持仓 · 打开模拟交易→")
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(DesignTokens.StatusColor.muted)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开模拟交易窗口")
            }
        } header: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label("持仓 (\(realPositions.count))", systemImage: "briefcase.fill")
                    .sidebarSectionHeader()
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary, DesignTokens.StatusColor.purple)
                Spacer()
                if !realPositions.isEmpty {
                    // v17.23 · 总浮盈 chip（涨红跌绿）
                    Text(String(format: "%@¥%.0f", totalFloatingPnL >= 0 ? "+" : "", totalFloatingPnL))
                        .font(DesignTokens.Typography.monoBold)
                        .foregroundColor(totalFloatingPnL >= 0 ? .red : .green)
                }
            }
        }
    }

    // MARK: - 预警历史（v17.70 · 接 SQLiteAlertHistoryStore 真实数据 · 5 条最近）

    private var alertHistorySection: some View {
        Section {
            if recentAlerts.isEmpty {
                Text("尚无触发记录")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.StatusColor.muted)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            } else {
                ForEach(recentAlerts) { entry in
                    Button {
                        openWindow(id: "chart")
                        NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: entry.instrumentID)
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "bell.fill")
                                .font(DesignTokens.Typography.label)
                                .foregroundColor(DesignTokens.StatusColor.danger)
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                HStack(spacing: DesignTokens.Spacing.xs) {
                                    Text(entry.instrumentID)
                                        .font(DesignTokens.Typography.mono)
                                        .foregroundColor(DesignTokens.StatusColor.accent)
                                    Text(entry.alertName)
                                        .font(DesignTokens.Typography.body)
                                        .lineLimit(1)
                                }
                                Text(Self.alertTimeFormatter.string(from: entry.triggeredAt))
                                    .font(DesignTokens.Typography.hint)
                                    .foregroundColor(DesignTokens.StatusColor.muted)
                            }
                            Spacer()
                            Text(NSDecimalNumber(decimal: entry.triggerPrice).stringValue)
                                .font(DesignTokens.Typography.monoSm)
                                .foregroundColor(DesignTokens.StatusColor.muted)
                        }
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(entry.message) · 点击切主图")
                }
            }
        } header: {
            Label("预警 (\(recentAlerts.count))", systemImage: "bell.fill")
                .sidebarSectionHeader()
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary, DesignTokens.StatusColor.danger)
        }
    }

    private static let alertTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private func refreshAlertsAsync() async {
        guard let store = storeManager?.alertHistory,
              let all = try? await store.allHistory() else { return }
        let top = Array(all.prefix(5))
        await MainActor.run { recentAlerts = top }
    }

    // MARK: - 异动（v17.82 · 接 AnomalyDetector 真扫描 · v17.88 Timer 30s 刷新）

    private var anomalySection: some View {
        Section {
            let evts = topAnomaliesCache
            if evts.isEmpty {
                Text("无异常 · 全市场平稳")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(DesignTokens.StatusColor.muted)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            } else {
                ForEach(evts) { evt in
                    Button {
                        openWindow(id: "chart")
                        NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: evt.instrumentID)
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: evt.kind.icon)
                                .font(DesignTokens.Typography.label)
                                .foregroundColor(Self.anomalyKindColor(evt.kind))
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                HStack(spacing: DesignTokens.Spacing.xs) {
                                    Text(evt.instrumentID)
                                        .font(DesignTokens.Typography.mono)
                                        .foregroundColor(DesignTokens.StatusColor.accent)
                                    Text(evt.instrumentName)
                                        .font(DesignTokens.Typography.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                Text(evt.kind.displayName)
                                    .font(DesignTokens.Typography.hint)
                                    .foregroundColor(DesignTokens.StatusColor.muted)
                            }
                            Spacer()
                            Text(String(format: "%.0f", evt.severity))
                                .font(DesignTokens.Typography.monoBold)
                                .foregroundColor(Self.anomalyKindColor(evt.kind))
                        }
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(evt.instrumentName) · \(evt.description) · 点击切主图")
                }
            }
        } header: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label("异动 (\(topAnomaliesCache.count))", systemImage: "exclamationmark.triangle.fill")
                    .sidebarSectionHeader()
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary, DesignTokens.StatusColor.warning)
                Spacer()
                // v17.88 · 显示距离上次扫描的时间（trader 看"系统活着"）
                Text(Self.anomalyTimeAgo(from: lastAnomalyScanAt))
                    .font(DesignTokens.Typography.hint)
                    .foregroundColor(DesignTokens.StatusColor.dimmed)
            }
        }
    }

    /// 显示 "刚刚 / 30s 前 / 2m 前" · 与 Timer 30s tick 配套
    private static func anomalyTimeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds)s 前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m 前" }
        return "\(minutes / 60)h 前"
    }

    private static func anomalyKindColor(_ k: AnomalyKind) -> Color {
        switch k {
        case .priceSpike:        return .red
        case .oiSpike:           return .orange
        case .fundSurge:         return .yellow
        case .priceOIDivergence: return .purple
        case .sectorOutlier:     return .pink
        }
    }

    // MARK: - 训练

    // MARK: - 训练（v17.3 · 接 TrainingLogPersistence 真实数据）

    private var trainingSection: some View {
        Section {
            // v17.91 · 整个 section 块包成 Button · 点击切 PrimaryTab=.training（与 ⌘5 同效）
            Button {
                shellVM.primaryTab = .training
                shellVM.activateFirstWorkspaceOfPrimaryTab()
            } label: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    let streak = trainingLog.currentStreak
                    if streak.count >= 2 {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text(streak.isWinning ? "🔥" : "💧")
                            Text("\(streak.isWinning ? "连胜" : "连败") \(streak.count) 次")
                                .font(DesignTokens.Typography.body)
                            Spacer()
                        }
                    }
                    if let avg = thisMonthAvg {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text("📊")
                            Text("本月均分 \(avg)")
                                .font(DesignTokens.Typography.body)
                            Spacer()
                        }
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text("🎯")
                        Text("累计 \(trainingLog.sessions.count) 次训练")
                            .font(DesignTokens.Typography.body)
                        Spacer()
                    }
                    if let dim = focusDimension {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text("🎯")
                            Text("下次专项: \(dim)")
                                .font(DesignTokens.Typography.body)
                                .foregroundColor(DesignTokens.StatusColor.purple)
                            Spacer()
                        }
                    }
                    if trainingLog.sessions.isEmpty {
                        Text("尚未开始训练 · 点击进入训练模块 →")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(DesignTokens.StatusColor.muted)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击切到训练模块（⌘5）")
        } header: {
            Label("训练", systemImage: "target")
                .sidebarSectionHeader()
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary, DesignTokens.StatusColor.success)
        }
    }

    /// 本月均分（仅含 v2 score · 与 HistoryPanel 同算法）
    private var thisMonthAvg: Int? {
        let cal = Calendar(identifier: .gregorian)
        guard let monthStart = cal.dateInterval(of: .month, for: Date())?.start else { return nil }
        let scores = trainingLog.sessions
            .filter { $0.endedAt >= monthStart }
            .compactMap { trainingLog.score(for: $0.id)?.totalScore }
        guard !scores.isEmpty else { return nil }
        return Int(round(Double(scores.reduce(0, +)) / Double(scores.count)))
    }

    /// v16.213 专项维度（@AppStorage 读 raw → 中文）
    private var focusDimension: String? {
        guard let raw = UserDefaults.standard.string(forKey: "viewState.v1.training.focusDimension"),
              !raw.isEmpty,
              let dim = TrainingSubScores.Dimension(rawValue: raw) else { return nil }
        return "\(dim.emoji) \(dim.displayName)"
    }
}

// MARK: - Mock 数据（v17.0 PoC Step 6 · v17.1+ 接真实 ViewModel）

private struct WatchItem { let symbol: String; let price: String; let change: String }

private let mockWatchlist: [WatchItem] = [
    WatchItem(symbol: "rb2510",   price: "3225",   change: "+0.78%"),
    WatchItem(symbol: "IF2509",   price: "3870",   change: "-0.52%"),
    WatchItem(symbol: "i2510",    price: "780.5",  change: "+1.23%"),
    WatchItem(symbol: "ag2510",   price: "8520",   change: "+0.31%"),
    WatchItem(symbol: "MA2510",   price: "2450",   change: "-0.18%"),
]

#endif
