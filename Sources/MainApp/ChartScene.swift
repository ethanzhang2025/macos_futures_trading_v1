// MainApp · K 线图表 Scene（WindowGroup 内容）
//
// 职责：
// - 每个 WindowGroup 实例独立初始化 renderer / pipeline / replay player（Cmd+N 多窗口隔离）
// - 工具条 4 Picker：模式（实盘/回放）· 合约 · 周期 · 副图
// - 实盘模式：Sina 真行情管线（snapshot + 实时增量）
// - 回放模式：拉历史 K 线 → ReplayPlayer + ReplayDriver 驱动逐根 emit · 底部播放控制条

#if canImport(SwiftUI) && os(macOS)

import Foundation
import SwiftUI
import Metal
import Shared
import DataCore
import ChartCore
import IndicatorCore
import ReplayCore
import StoreCore
import AlertCore

// MARK: - 模式（实盘 / 回放）

enum ChartMode: String, CaseIterable, Identifiable {
    case live   = "实盘"
    case replay = "回放"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - Scene 容器（每窗口独立 state）

struct ChartScene: View {

    // 共享 state
    @State private var renderer: MetalKLineRenderer?
    @State private var bars: [KLine] = []
    @State private var indicators: [IndicatorSeries] = []
    @State private var loadError: String?
    @State private var instrumentLabel: String = "—"
    @State private var periodLabel: String = "—"
    @State private var dataSourceLabel: String = "加载中…"
    @State private var currentInstrumentID: String = MarketDataPipeline.defaultInstrumentID
    @State private var selectedPeriod: KLinePeriod = MarketDataPipeline.defaultPeriod
    @State private var selectedSubIndicator: SubIndicatorKind = .macd
    @State private var chartMode: ChartMode = .live

    // 实盘 state
    @State private var pipeline: MarketDataPipeline?

    // 增量指标推进器（WP-41 v2 commit 4/4 · 解决回放 8× 重算瓶颈）
    @State private var indicatorRunner: ChartIndicatorRunner?

    // 回放 state（mode = .replay 时活跃）
    @State private var replayPlayer: ReplayPlayer?
    @State private var replayDriver: ReplayDriver?
    @State private var replayAllBars: [KLine] = []
    @State private var replay: ReplaySnapshot = ReplaySnapshot()
    @State private var replayObserveTask: Task<Void, Never>?

    /// M5 持久化串行写：snapshot save / completedBar append 链式 await · 防多 Task 并发提交导致顺序乱
    /// 风险：高频 completedBar（1 秒级）+ maxBars 截断时 · 无序写入可能丢中间根
    @State private var klineSaveTask: Task<Void, Never>?

    /// 实时报价的昨结算 · priceTopBar baseline · nil 时 fallback bars.first.close
    @State private var preSettle: Decimal?

    /// M5 持久化：StoreManager 注入 · loadAndStream fast-path 读磁盘缓存 · snapshot/completedBar 异步落库
    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics
    @Environment(\.alertEvaluator) private var alertEvaluator

    /// 回放 player 的 UI 镜像（cursor + state + speed 派生于 player · 通过 observe() 同步）
    private struct ReplaySnapshot: Equatable {
        var cursor: ReplayCursor = ReplayCursor(currentIndex: -1, totalCount: 0)
        var state: ReplayState = .stopped
        var speed: ReplaySpeed = .x1
    }

    /// 触发 pipeline 重启的复合 key（模式/合约/周期 任一变化都触发）
    private struct PipelineKey: Equatable {
        let mode: ChartMode
        let instrumentID: String
        let period: KLinePeriod
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            mainContent
            if chartMode == .replay {
                replayControlBar
            }
        }
        .background(periodShortcuts)
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task(id: PipelineKey(mode: chartMode, instrumentID: currentInstrumentID, period: selectedPeriod)) {
            await resetForNewPipeline()
            await fetchPreSettle(instrumentID: currentInstrumentID)
            switch chartMode {
            case .live:   await loadAndStream(instrumentID: currentInstrumentID, period: selectedPeriod)
            case .replay: await loadReplay(instrumentID: currentInstrumentID, period: selectedPeriod)
            }
            // 埋点：每次 task(id:) 重启都记 chart_open（mode/instrument/period 切换均算"打开新图"）
            if let service = analytics {
                _ = try? await service.record(
                    .chartOpen,
                    userID: FuturesTerminalApp.anonymousUserID,
                    properties: [
                        "mode": chartMode.rawValue,
                        "instrument": currentInstrumentID,
                        "period": selectedPeriod.displayName
                    ]
                )
            }
        }
        .onChange(of: selectedSubIndicator) { newValue in
            // 埋点：用户切换副图指标（MACD / KDJ / RSI ...）· chart_open 之外的细粒度行为
            guard let service = analytics else { return }
            Task {
                _ = try? await service.record(
                    .indicatorAdd,
                    userID: FuturesTerminalApp.anonymousUserID,
                    properties: ["kind": newValue.rawValue]
                )
            }
        }
        .onChange(of: chartMode) { newValue in
            // 埋点：切到回放模式 = replay_start（chart_open 已含 mode 属性 · 这里只在切到 replay 时额外发细粒度）
            guard newValue == .replay, let service = analytics else { return }
            Task {
                _ = try? await service.record(
                    .replayStart,
                    userID: FuturesTerminalApp.anonymousUserID,
                    properties: [
                        "instrument": currentInstrumentID,
                        "period": selectedPeriod.displayName
                    ]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { notification in
            // WP-43 commit 4 · WatchlistWindow 双击合约 → 同步切到当前主图（task(id:) 自动重启 pipeline）
            // 双重防护：WatchlistWindow 已本地 alert 拦截不支持的合约，这里再校验一次防外部直接 post
            guard let id = notification.object as? String,
                  MarketDataPipeline.supportedContracts.contains(id),
                  id != currentInstrumentID
            else { return }
            currentInstrumentID = id
        }
        .onDisappear {
            Task {
                await pipeline?.stop()
                await replayPlayer?.stop()
                await replayDriver?.stop()
                replayObserveTask?.cancel()
                // 等链式 K 线落库完成 · 防窗口关闭时最后一根丢失
                await klineSaveTask?.value
            }
        }
    }

    /// 模式/合约/周期切换前重置：先 stop player → driver → 再 cancel observe（避免 player emit 时 consumer 已退出）
    private func resetForNewPipeline() async {
        await pipeline?.stop()
        pipeline = nil

        await replayPlayer?.stop()
        await replayDriver?.stop()
        replayObserveTask?.cancel()
        replayObserveTask = nil
        replayDriver = nil
        replayPlayer = nil
        replayAllBars = []
        replay = ReplaySnapshot()

        bars = []
        indicators = []
        indicatorRunner = nil
        preSettle = nil
        dataSourceLabel = "加载中…"
        instrumentLabel = currentInstrumentID
    }

    /// 拉一次实时报价取 priceBaseline · priceTopBar baseline · 失败/未拉到保持 nil 由 priceTopBar fallback 周期首根
    /// 仅 supportedContracts 拉 · 不阻塞 K 线流程（即使失败 K 线照常显示）
    /// v12.15 用 SinaQuote.priceBaseline 替代直接 .preSettlement · 商品昨结算 / 金融昨收近似 语义统一
    private func fetchPreSettle(instrumentID: String) async {
        guard MarketDataPipeline.supportedContracts.contains(instrumentID) else { return }
        let sina = SinaMarketData()
        guard let quote = try? await sina.fetchQuote(symbol: instrumentID),
              quote.priceBaseline > 0 else { return }
        preSettle = quote.priceBaseline
    }

    /// 全量计算 indicators + 重建 indicatorRunner（commit 4/4 · snapshot / seek / Mock fallback 路径）
    /// 增量推进路径走 stepIndicators(newBar:)
    private func updateIndicatorsFull(_ snap: [KLine]) async {
        indicators = await computeIndicatorsAsync(snap)
        indicatorRunner = ChartIndicatorRunner.prime(bars: snap)
    }

    /// 增量推进 indicators · 仅在新 K 单调追加时调（barEmitted / completedBar 两条路径）
    /// runner 不可用时 fallback 全量
    private func stepIndicators(newBar: KLine) async {
        if var runner = indicatorRunner {
            indicators = runner.step(newBar: newBar)
            indicatorRunner = runner
        } else {
            await updateIndicatorsFull(bars)
        }
    }

    // MARK: - 周期键盘快捷键 ⌘1~6（v12.19 · WP-44 · 隐藏 Button + .keyboardShortcut）

    /// 隐藏按钮组绑定 ⌘1~6 切到对应周期 · zero-frame + 0 透明度不显示但 SwiftUI 仍处理 shortcut
    private var periodShortcuts: some View {
        Group {
            Button("") { selectedPeriod = .minute1 }
                .keyboardShortcut("1", modifiers: [.command])
            Button("") { selectedPeriod = .minute5 }
                .keyboardShortcut("2", modifiers: [.command])
            Button("") { selectedPeriod = .minute15 }
                .keyboardShortcut("3", modifiers: [.command])
            Button("") { selectedPeriod = .minute30 }
                .keyboardShortcut("4", modifiers: [.command])
            Button("") { selectedPeriod = .hour1 }
                .keyboardShortcut("5", modifiers: [.command])
            Button("") { selectedPeriod = .daily }
                .keyboardShortcut("6", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 14) {
            // 视觉迭代第 8 项：模式 / 副图 2 项 segmented 直接可见 · 合约 / 周期保留 menu（项多 segmented 挤）
            Picker("", selection: $chartMode) {
                ForEach(ChartMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .labelsHidden()

            Picker("", selection: $currentInstrumentID) {
                ForEach(MarketDataPipeline.supportedContracts, id: \.self) { sym in
                    Text(sym).tag(sym)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .labelsHidden()

            Picker("", selection: $selectedPeriod) {
                ForEach(MarketDataPipeline.supportedPeriods, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            .labelsHidden()

            Picker("", selection: $selectedSubIndicator) {
                ForEach(SubIndicatorKind.allCases) { k in
                    Text(k.shortName).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .labelsHidden()

            Spacer()
            Text("⌘N 新窗口 · ⌘L 自选 · ⌘, 设置")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 32)
        // 视觉迭代第 11 项：toolbar 显式深色 #15171C 与主图 #11141A 协调 · 替代 .bar 系统默认
        .background(Color(red: 0.082, green: 0.090, blue: 0.110))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let renderer, !bars.isEmpty {
            ChartContentView(
                renderer: renderer,
                bars: bars,
                indicators: indicators,
                instrumentLabel: instrumentLabel,
                periodLabel: periodLabel,
                dataSourceLabel: dataSourceLabel,
                subIndicatorKind: selectedSubIndicator,
                preSettle: preSettle,
                initialViewport: RenderViewport(
                    startIndex: max(0, bars.count - 120),
                    visibleCount: 120
                )
            )
        } else if let loadError {
            errorView(loadError)
        } else {
            ProgressView(chartMode == .replay
                         ? "加载 \(currentInstrumentID) 历史回放…"
                         : "加载 \(currentInstrumentID) 真行情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - v11.0+1 · K 线 close 假 Tick（evaluator wiring）

    /// 用 K 线收尾构造模拟 Tick · 仅评估器需要的字段（lastPrice/volume/instrumentID）填真实值
    /// 其余字段 0 / [] 占位 · 真 Tick Stage B CTP 接入后整体替换
    private static func simulatedTick(from k: KLine) -> Tick {
        Tick(
            instrumentID: k.instrumentID,
            lastPrice: k.close,
            volume: k.volume,
            openInterest: k.openInterest,
            turnover: k.turnover,
            bidPrices: [], askPrices: [], bidVolumes: [], askVolumes: [],
            highestPrice: k.high,
            lowestPrice: k.low,
            openPrice: k.open,
            preClosePrice: 0, preSettlementPrice: 0,
            upperLimitPrice: 0, lowerLimitPrice: 0,
            updateTime: "", updateMillisec: 0,
            tradingDay: "", actionDay: ""
        )
    }

    // MARK: - 实盘加载

    private func loadAndStream(instrumentID: String, period: KLinePeriod) async {
        if !(await ensureRenderer()) { return }

        // M5 持久化 fast-path：网络 fetch 前先 load 磁盘缓存 · 立即显示 · 后续 snapshot 来后会替换
        // 协议返 [KLine] 非 Optional · 单层 try? · isEmpty 跳过空缓存（与 Alert/Journal 同模式）
        if let store = storeManager?.kline,
           let cached = try? await store.load(instrumentID: instrumentID, period: period),
           !cached.isEmpty {
            bars = cached
            await updateIndicatorsFull(cached)
            dataSourceLabel = "本地缓存（\(cached.count) 根）"
        }

        let pipe = MarketDataPipeline(instrumentID: instrumentID, period: period)
        pipeline = pipe
        instrumentLabel = pipe.instrumentID
        periodLabel = pipe.periodLabel
        let stream = await pipe.start()

        var snapshotReceived = false
        for await update in stream {
            switch update {
            case .snapshot(let snapBars):
                if snapBars.isEmpty && !snapshotReceived {
                    // 首次 snapshot 拉空 → Sina 不可达 / 节假日
                    // 无缓存（bars 空）→ 退回 Mock；有缓存 → 保留并打离线 label · 等下次 snapshot
                    if bars.isEmpty {
                        await pipe.stop()
                        pipeline = nil
                        await loadMockFallback()
                        return
                    }
                    dataSourceLabel = "本地缓存（离线）"
                    continue
                }
                snapshotReceived = true
                bars = snapBars
                await updateIndicatorsFull(snapBars)
                dataSourceLabel = "Sina 真行情"
                // M5 持久化：snapshot 后异步 save 全量 · 链式串行（前一个 task 完成后再写）
                if let store = storeManager?.kline {
                    let prev = klineSaveTask
                    klineSaveTask = Task {
                        await prev?.value
                        try? await store.save(snapBars, instrumentID: instrumentID, period: period)
                    }
                }
            case .completedBar(let k):
                bars.append(k)
                await stepIndicators(newBar: k)
                // M5 持久化：完成的单根 K 线异步 append · maxBars 按 period 动态（v12.9）· 链式串行保 K 线时间序
                if let store = storeManager?.kline {
                    let prev = klineSaveTask
                    let maxBars = MarketDataPipeline.cacheMaxBars(for: period)
                    klineSaveTask = Task {
                        await prev?.value
                        try? await store.append([k], instrumentID: instrumentID, period: period, maxBars: maxBars)
                    }
                }
                // v11.0+1 · evaluator 用 K 线 close 模拟 Tick · 真 Tick Stage B 接 CTP 后替换
                if let evaluator = alertEvaluator {
                    await evaluator.onTick(Self.simulatedTick(from: k))
                }
            }
        }
    }

    // MARK: - 回放加载

    /// 拉历史 K 线 → 创建 ReplayPlayer + ReplayDriver → 监听 ReplayUpdate · 等用户按 ▶ 启动
    private func loadReplay(instrumentID: String, period: KLinePeriod) async {
        if !(await ensureRenderer()) { return }

        let history: [KLine]
        do {
            history = try await fetchHistoricalKLines(instrumentID: instrumentID, period: period)
        } catch {
            loadError = "回放历史拉取失败：\(error)"
            return
        }
        guard !history.isEmpty else {
            loadError = "回放数据为空（节假日 / Sina 不可达）"
            return
        }

        // baseInterval=1.0s · 1× 速度下每根 1 秒（speed.multiplier 缩放）
        let player = ReplayPlayer()
        await player.load(bars: history)
        let driver = ReplayDriver(player: player, baseInterval: 1.0)
        replayPlayer = player
        replayDriver = driver
        replayAllBars = history

        // 初始 cursor 在 0（仅显示第一根 · 等用户按 ▶ 推进）
        replay = ReplaySnapshot(
            cursor: await player.cursor,
            state: await player.currentState,
            speed: await player.currentSpeed
        )

        bars = Array(history.prefix(replay.cursor.currentIndex + 1))
        await updateIndicatorsFull(bars)
        instrumentLabel = instrumentID
        periodLabel = period.displayName
        dataSourceLabel = "回放 \(history.count) 根 · 按 ▶ 启动"

        replayObserveTask = Task { @MainActor in
            let stream = await player.observe()
            for await update in stream {
                await handleReplayUpdate(update)
            }
        }
    }

    /// Sina 历史 K 线 type=1/5/15/30/60min + 日 全部支持（v12.6 SinaKLineGranularityDemo 实测验证）
    /// 之前 default fallback 15min 是错误结论 · 已扩 minute1 / minute15 / minute30 真 type 路径
    private func fetchHistoricalKLines(instrumentID: String, period: KLinePeriod) async throws -> [KLine] {
        let sina = SinaMarketData()
        let historical: [HistoricalKLine]
        switch period {
        case .daily, .weekly, .monthly:
            historical = try await sina.historicalDaily(symbol: instrumentID)
        case .minute1:
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 1)
        case .minute5:
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 5)
        case .minute15:
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 15)
        case .minute30:
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 30)
        case .hour1:
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 60)
        default:  // 周/月已在第一 case · 此分支理论不会进 · 安全 fallback 15min
            historical = try await sina.historicalMinute(symbol: instrumentID, intervalMinutes: 15)
        }
        return historical.compactMap { hist -> KLine? in
            guard let date = Self.parseHistoricalDate(hist.date) else { return nil }
            return KLine(
                instrumentID: instrumentID,
                period: period,
                openTime: date,
                open: hist.open,
                high: hist.high,
                low: hist.low,
                close: hist.close,
                volume: hist.volume,
                openInterest: Decimal(hist.openInterest),
                turnover: 0
            )
        }
    }

    /// 解析 Sina 历史 K 线 date 字符串
    /// `en_US_POSIX` locale 防系统中文 locale 解析失败 · 3 格式 fallback 兼容秒级/分钟/日 K
    private static func parseHistoricalDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// 处理 ReplayPlayer emit 的事件 · 同步更新 bars / cursor / state 给 UI
    @MainActor
    private func handleReplayUpdate(_ update: ReplayUpdate) async {
        switch update {
        case .barEmitted(let bar, let cursor):
            replay.cursor = cursor
            // 单调递增（stepForward / 正常播放）走增量 append；倒退/异常走全量重建
            if cursor.currentIndex == bars.count {
                bars.append(bar)
                await stepIndicators(newBar: bar)
            } else {
                await rebuildBarsToCursor(cursor)
            }
        case .stateChanged(let state, let speed, _):
            replay.state = state
            replay.speed = speed
        case .seekFinished(let cursor):
            replay.cursor = cursor
            await rebuildBarsToCursor(cursor)
        case .tradeMarks:
            break  // 成交点叠加 v1 不显示
        }
    }

    /// seek / stepBackward 时从 replayAllBars 全量重建 visible bars 到 cursor 位置
    private func rebuildBarsToCursor(_ cursor: ReplayCursor) async {
        guard cursor.currentIndex >= 0, cursor.currentIndex < replayAllBars.count else { return }
        bars = Array(replayAllBars.prefix(cursor.currentIndex + 1))
        await updateIndicatorsFull(bars)
    }

    // MARK: - 回放控制条（仅 .replay 模式）

    private var replayControlBar: some View {
        HStack(spacing: 14) {
            Button { Task { await onTapStop() } } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(ReplayBarButtonStyle())
            .help("停止 · 重置到第 1 根")

            Button { Task { await onTapStepBackward() } } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(ReplayBarButtonStyle())
            .help("单步后退 1 根")

            Button { Task { await onTapPlayPause() } } label: {
                Image(systemName: replay.state == .playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(ReplayBarButtonStyle(active: replay.state == .playing))
            .keyboardShortcut(.space, modifiers: [])
            .help(replay.state == .playing ? "暂停（空格）" : "播放（空格）")

            Button { Task { await onTapStepForward() } } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(ReplayBarButtonStyle())
            .help("单步前进 1 根")

            Divider().frame(height: 18)

            Picker("", selection: Binding(
                get: { replay.speed },
                set: { newSpeed in Task { await replayPlayer?.setSpeed(newSpeed) } }
            )) {
                ForEach(ReplaySpeed.allCases, id: \.self) { sp in
                    Text(speedLabel(sp)).tag(sp)
                }
            }
            .pickerStyle(.segmented)
            .tint(.accentColor)
            .frame(width: 240)
            .labelsHidden()

            Spacer()

            Text(progressText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var progressText: String {
        guard replay.cursor.totalCount > 0 else { return "—" }
        let pct = Int(replay.cursor.progress * 100)
        return "\(replay.cursor.currentIndex + 1) / \(replay.cursor.totalCount) · \(pct)%"
    }

    private func speedLabel(_ s: ReplaySpeed) -> String {
        switch s {
        case .x05: return "0.5×"
        case .x1:  return "1×"
        case .x2:  return "2×"
        case .x4:  return "4×"
        case .x8:  return "8×"
        }
    }

    // MARK: - 回放控制 actions（共享 player/driver guard）

    @MainActor
    private func withReplay(_ action: (ReplayPlayer, ReplayDriver) async -> Void) async {
        guard let player = replayPlayer, let driver = replayDriver else { return }
        await action(player, driver)
    }

    private func onTapPlayPause() async {
        await withReplay { player, driver in
            switch await player.currentState {
            case .playing:
                await player.pause()
                await driver.stop()
            case .paused, .stopped:
                await player.play()
                await driver.start()
            }
        }
    }

    private func onTapStop() async {
        await withReplay { player, driver in
            await driver.stop()
            await player.stop()
        }
    }

    private func onTapStepForward() async {
        await withReplay { player, driver in
            await driver.stop()
            await player.pause()
            await player.stepForward(count: 1)
        }
    }

    private func onTapStepBackward() async {
        await withReplay { player, driver in
            await driver.stop()
            await player.pause()
            await player.stepBackward(count: 1)
        }
    }

    // MARK: - 共享 helper

    /// 仅首次 init renderer · 跨模式/合约/周期复用（renderer 与数据无关）
    @MainActor
    private func ensureRenderer() async -> Bool {
        if renderer != nil { return true }
        do {
            renderer = try await Task.detached(priority: .userInitiated) {
                try MetalKLineRenderer()
            }.value
            return true
        } catch {
            loadError = "渲染器初始化失败：\(error)"
            return false
        }
    }

    /// Sina 不可达兜底：5000 根 random walk Mock
    private func loadMockFallback() async {
        let result = await Task.detached(priority: .userInitiated) {
            let b = MockKLineData.generateBars(5_000)
            let i = MockKLineData.computeIndicators(bars: b)
            return (b, i)
        }.value
        bars = result.0
        indicators = result.1
        indicatorRunner = ChartIndicatorRunner.prime(bars: result.0)
        dataSourceLabel = "Sina 不可达 · 已退回 Mock"
    }

    /// 200 根 ~10ms / 5k 根 ~50ms · 8× 回放速度下成为热路径瓶颈，下版本接 IndicatorCore 增量 API
    private func computeIndicatorsAsync(_ snap: [KLine]) async -> [IndicatorSeries] {
        await Task.detached(priority: .userInitiated) {
            MockKLineData.computeIndicators(bars: snap)
        }.value
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("❌ 加载失败").font(.headline)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 图表内容视图（复用 demo · 5 indicator 折线 + 时间轴 + 价格刻度 + 惯性滚动）

struct ChartContentView: View {

    /// 默认窗口宽度（用于计算 dynamic pixelsPerBar · 让 pan 灵敏度跟随 zoom 自动调整）
    static let assumedViewWidth: CGFloat = 1280
    /// visibleCount 范围（防止 zoom 越界）
    static let minVisible = 20
    static let maxVisible = 5000

    /// 惯性衰减率（每帧）· 0.97 ≈ 2 秒衰减
    static let inertiaDecayPerFrame: Float = 0.97
    /// 最小速度阈值（K 数 / 帧 · 低于停止）
    static let inertiaStopThreshold: Float = 0.02
    /// 初始速度分摊帧数
    static let inertiaSpreadFrames: Float = 20

    let renderer: MetalKLineRenderer
    let bars: [KLine]
    let indicators: [IndicatorSeries]
    let instrumentLabel: String
    let periodLabel: String
    let dataSourceLabel: String
    let subIndicatorKind: SubIndicatorKind
    /// v12.1 真昨结算 · priceTopBar baseline · nil 时 fallback bars.first.close（由 ChartScene 父级注入）
    let preSettle: Decimal?
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?
    @State var inertiaTask: Task<Void, Never>?

    init(
        renderer: MetalKLineRenderer,
        bars: [KLine],
        indicators: [IndicatorSeries],
        instrumentLabel: String,
        periodLabel: String,
        dataSourceLabel: String,
        subIndicatorKind: SubIndicatorKind,
        preSettle: Decimal?,
        initialViewport: RenderViewport
    ) {
        self.renderer = renderer
        self.bars = bars
        self.indicators = indicators
        self.instrumentLabel = instrumentLabel
        self.periodLabel = periodLabel
        self.dataSourceLabel = dataSourceLabel
        self.subIndicatorKind = subIndicatorKind
        self.preSettle = preSettle
        self._viewport = State(initialValue: initialViewport)
    }

    /// 副图高度（spike 阶段固定 · 后续 WP 加可拖分割条）
    static let subChartHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                chartMainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                KLineAxisView(bars: bars, viewport: viewport, priceRange: currentPriceRange, orientation: .price)
                    .frame(width: 60)
            }
            // 视觉迭代第 9 项：主图 ↔ 副图分割线增强 · 1.5pt 深灰条 · 比默认 Divider 醒目
            Color.white.opacity(0.18)
                .frame(height: 1)
            // 副图区（指数平滑异同移动平均线 MACD · 共享主图 viewport · 拖拽缩放主图时副图同步）
            HStack(spacing: 0) {
                SubChartView(bars: bars, viewport: viewport, kind: subIndicatorKind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color(red: 0.07, green: 0.08, blue: 0.10)
                    .frame(width: 60)  // 占位 · 与主图右侧价格轴对齐
            }
            .frame(height: Self.subChartHeight)
            KLineAxisView(bars: bars, viewport: viewport, priceRange: currentPriceRange, orientation: .time)
                .frame(height: 28)
        }
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let stats = await renderer.lastStats
                lastFrameMs = stats.lastFrameDuration * 1000
            }
        }
    }

    /// 主图区（K 线 + 网格 + 十字光标 + indicators + HUD · gesture 挂这里）
    var chartMainArea: some View {
        ZStack(alignment: .topLeading) {
            KLineMetalView(
                renderer: renderer,
                input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 视觉迭代第 1 项：5×5 半透明网格 · 与右价格轴 / 底时间轴对齐
            KLineGridView()
            // 视觉迭代第 2 项：十字光标 + OHLC 浮窗 + 轴边价格/时间浮标（hover 跟随）
            KLineCrosshairView(bars: bars, viewport: viewport, priceRange: currentPriceRange, period: bars.first?.period ?? .minute15)
            hud
        }
        .overlay(alignment: .topTrailing) {
            // 视觉迭代第 6 项：顶部当前价大字号 + 涨跌（vs Sina 实时昨结算 preSettle · fallback visible 周期首根）
            priceTopBar
        }
        .simultaneousGesture(panGesture)
        .simultaneousGesture(zoomGesture)
    }

    /// 顶部当前价大字号 + 涨跌幅 · 红涨绿跌 · baseline 用 Sina 实时昨结算 preSettle · fallback visible 周期首根
    private var priceTopBar: some View {
        HStack(spacing: 10) {
            if let last = bars.last, let first = bars.first {
                let close = NSDecimalNumber(decimal: last.close).doubleValue
                let baselineDecimal = preSettle ?? first.close
                let baseline = NSDecimalNumber(decimal: baselineDecimal).doubleValue
                let diff = close - baseline
                let pct = baseline > 0 ? diff / baseline * 100 : 0
                let isUp = diff >= 0
                let color: Color = isUp
                    ? Color(red: 0.96, green: 0.27, blue: 0.27)
                    : Color(red: 0.18, green: 0.74, blue: 0.42)
                Text(String(format: "%.2f", close))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(isUp ? "▲" : "▼") \(String(format: "%+.2f", diff))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(color)
                    Text(String(format: "%+.2f%%", pct))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(color)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .padding(12)
    }

    /// 拖拽平移 + 松手惯性滑行
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                inertiaTask?.cancel()
                let base = dragStartViewport ?? viewport
                dragStartViewport = base
                let perBar = Self.assumedViewWidth / CGFloat(max(1, base.visibleCount))
                let deltaBars = Float(-value.translation.width / perBar)
                viewport = clamp(base.pannedSmooth(byBars: deltaBars))
            }
            .onEnded { value in
                dragStartViewport = nil
                let perBar = Self.assumedViewWidth / CGFloat(max(1, viewport.visibleCount))
                let predictedExtraPx = value.predictedEndTranslation.width - value.translation.width
                let initialVelocity = Float(-predictedExtraPx / perBar) / Self.inertiaSpreadFrames
                if abs(initialVelocity) > Self.inertiaStopThreshold {
                    startInertia(velocity: initialVelocity)
                }
            }
    }

    /// 双指捏合缩放（visibleCount 反向缩放）
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                inertiaTask?.cancel()
                let base = zoomStartViewport ?? viewport
                zoomStartViewport = base
                let factor = 1.0 / Double(scale)
                viewport = clamp(base.zoomed(by: factor))
            }
            .onEnded { _ in zoomStartViewport = nil }
    }

    var currentPriceRange: ClosedRange<Decimal> {
        if let r = viewport.priceRange { return r }
        let visible = min(viewport.visibleCount, max(0, bars.count - viewport.startIndex))
        guard visible > 0 else { return Decimal(0)...Decimal(1) }
        let slice = bars[viewport.startIndex..<(viewport.startIndex + visible)]
        let lo = slice.map(\.low).min() ?? Decimal(0)
        let hi = slice.map(\.high).max() ?? Decimal(1)
        return lo...max(hi, lo + Decimal(1))
    }

    var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 主标识行：合约 + 周期 + 数据源（核心信息 · 醒目）
            Text("\(instrumentLabel) · \(periodLabel) · \(dataSourceLabel)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            // 视觉迭代第 3 项：MA / BOLL 数值彩色圆点 + 染色（与 Metal 折线 5 色调色板对齐 · 黄/紫/蓝/橙/粉）
            ForEach(Array(indicators.enumerated()), id: \.offset) { idx, series in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.indicatorTextColor(at: idx))
                        .frame(width: 8, height: 8)
                    Text("\(series.name): \(latestText(series))")
                        .foregroundColor(Self.indicatorTextColor(at: idx))
                }
            }
            // 视觉迭代第 4 项：调试信息（视野/帧时）淡化 · 字号缩小 + 灰色 · 不抢主信息
            Text("可见 \(viewport.visibleCount) · 起点 \(viewport.startIndex)/\(bars.count) · 帧 \(String(format: "%.1f", lastFrameMs))ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(6)
        .padding(12)
    }

    /// 与 MetalKLineRenderer.indicatorPalette 同步（黄/紫/蓝/橙/粉 · MA5/MA20/MA60/BOLL-UP/BOLL-DN）
    private static func indicatorTextColor(at idx: Int) -> Color {
        let palette: [Color] = [
            Color(red: 1.00, green: 0.78, blue: 0.18),
            Color(red: 0.63, green: 0.42, blue: 0.84),
            Color(red: 0.20, green: 0.60, blue: 0.86),
            Color(red: 0.95, green: 0.61, blue: 0.07),
            Color(red: 0.91, green: 0.30, blue: 0.55)
        ]
        return palette[idx % palette.count]
    }

    /// 取 visible window 末位的 indicator 值（与画面对齐 · 不取全段末位）
    private func latestText(_ series: IndicatorSeries) -> String {
        let end = min(series.values.count, viewport.startIndex + viewport.visibleCount)
        let prefix = series.values.prefix(end)
        guard let value = prefix.compactMap({ $0 }).last else { return "—" }
        return String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    /// 惯性滚动（onEnded 调 · 速度逐帧衰减直到低于阈值或触底）
    private func startInertia(velocity initialVelocity: Float) {
        inertiaTask?.cancel()
        inertiaTask = Task { @MainActor in
            var v = initialVelocity
            while !Task.isCancelled && abs(v) > Self.inertiaStopThreshold {
                try? await Task.sleep(nanoseconds: 16_666_666)
                if Task.isCancelled { break }
                let prev = viewport
                viewport = clamp(viewport.pannedSmooth(byBars: v))
                if viewport.startIndex == prev.startIndex && viewport.startOffset == prev.startOffset {
                    break
                }
                v *= Self.inertiaDecayPerFrame
            }
        }
    }

    func clamp(_ v: RenderViewport) -> RenderViewport {
        let visible = min(max(Self.minVisible, v.visibleCount), Self.maxVisible)
        let maxStart = max(0, bars.count - visible)
        let start = min(maxStart, max(0, v.startIndex))
        let offset = (start >= maxStart || start <= 0) ? 0 : v.startOffset
        return RenderViewport(startIndex: start, visibleCount: visible, priceRange: v.priceRange, startOffset: offset)
    }
}

// MARK: - Mock 数据（spike 阶段占位 · 后续 WP 接 MarketDataProvider）

// MARK: - 增量指标推进器（WP-41 v2 commit 4/4 · 解决回放每帧全量重算瓶颈）

/// 4 个 IncrementalState（MA5 / MA20 / MA60 / BOLL）· 与 MockKLineData.computeIndicators 一致
/// - prime(bars:) 用 history 全量初始化（一次 O(N)）
/// - step(newBar:) 推进所有 state · 返回 series 末尾追加新值（每步 O(N) 主要来自 BOLL stddev）
/// - 单调递增 append（barEmitted / completedBar）调 step · seek/重建走全量 prime
fileprivate struct ChartIndicatorRunner {
    var ma5: MA.IncrementalState
    var ma20: MA.IncrementalState
    var ma60: MA.IncrementalState
    var boll: BOLL.IncrementalState
    private(set) var series: [IndicatorSeries]   // 与 ChartScene.indicators 同步快照

    /// 用 history 初始化全部 state 与 series（与 MockKLineData.computeIndicators 完全一致）
    static func prime(bars: [KLine]) -> ChartIndicatorRunner? {
        let kline = makeKLineSeries(from: bars)
        guard
            let ma5State  = try? MA.makeIncrementalState(kline: kline, params: [5]),
            let ma20State = try? MA.makeIncrementalState(kline: kline, params: [20]),
            let ma60State = try? MA.makeIncrementalState(kline: kline, params: [60]),
            let bollState = try? BOLL.makeIncrementalState(kline: kline, params: [20, 2])
        else { return nil }
        let series = MockKLineData.computeIndicators(bars: bars)
        return ChartIndicatorRunner(ma5: ma5State, ma20: ma20State, ma60: ma60State, boll: bollState, series: series)
    }

    /// 推进 1 根新 K · 返回更新后的 series（顺序：MA5 / MA20 / MA60 / BOLL-UPPER / BOLL-LOWER · 与 computeIndicators 输出一致）
    mutating func step(newBar: KLine) -> [IndicatorSeries] {
        let ma5Val  = MA.stepIncremental(state: &ma5,  newBar: newBar)[0]
        let ma20Val = MA.stepIncremental(state: &ma20, newBar: newBar)[0]
        let ma60Val = MA.stepIncremental(state: &ma60, newBar: newBar)[0]
        let bollVals = BOLL.stepIncremental(state: &boll, newBar: newBar)   // [MID, UPPER, LOWER]
        let appended: [Decimal?] = [ma5Val, ma20Val, ma60Val, bollVals[1], bollVals[2]]
        precondition(series.count == appended.count, "series count must match appended count")
        for i in series.indices {
            series[i] = IndicatorSeries(name: series[i].name, values: series[i].values + [appended[i]])
        }
        return series
    }

    private static func makeKLineSeries(from bars: [KLine]) -> KLineSeries {
        KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
    }
}

// MARK: - Mock 数据生成（spike 占位 · 后续 WP 接 MarketDataProvider）

enum MockKLineData {

    static func generateBars(_ count: Int, basePrice: Double = 3000) -> [KLine] {
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price = basePrice
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count {
            let drift = Double.random(in: -2...2, using: &rng)
            let open = price
            let close = max(100, price + drift)
            let high = max(open, close) + Double.random(in: 0...3, using: &rng)
            let low = min(open, close) - Double.random(in: 0...3, using: &rng)
            bars.append(KLine(
                instrumentID: "RB",
                period: .minute1,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: 100,
                openInterest: 0,
                turnover: 0
            ))
            price = close
        }
        return bars
    }

    /// 5 条不重合：MA(5) + MA(20) + MA(60) + BOLL UPPER + BOLL LOWER（过滤 BOLL-MID = MA(20)）
    static func computeIndicators(bars: [KLine]) -> [IndicatorSeries] {
        let series = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        let ma5 = (try? MA.calculate(kline: series, params: [5])) ?? []
        let ma20 = (try? MA.calculate(kline: series, params: [20])) ?? []
        let ma60 = (try? MA.calculate(kline: series, params: [60])) ?? []
        let boll = (try? BOLL.calculate(kline: series, params: [20, 2])) ?? []
        let bollBands = boll.filter { $0.name != "BOLL-MID" }
        return ma5 + ma20 + ma60 + bollBands
    }
}

/// 回放控制条按钮统一样式（v12.13 · 用户反馈：所有按钮点击瞬间蓝底白字 · 播放按钮 playing 态持续蓝底白字）
/// active=true 时持续高亮（用于 play/pause 在 playing 状态时的持续表现）
private struct ReplayBarButtonStyle: ButtonStyle {
    var active: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        let highlight = configuration.isPressed || active
        return configuration.label
            .frame(width: 18, height: 18)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(highlight ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(highlight ? .white : .primary)
            .cornerRadius(6)
    }
}

#endif
