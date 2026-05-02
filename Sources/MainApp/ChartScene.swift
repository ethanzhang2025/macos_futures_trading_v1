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
import AppKit
import Metal
import Shared
import DataCore
import ChartCore
import IndicatorCore
import ReplayCore
import StoreCore
import AlertCore
import TradingCore

// MARK: - v15.x · trackpad / 滚轮 scrollWheel 捕获（双指上下推 = K 线缩放）

/// NSViewRepresentable 包装 NSView · 用 NSEvent.addLocalMonitorForEvents 监听 scrollWheel
/// v15.16 hotfix：原 scrollWheel(with:) override 走 hit-test 链 · .background 在 z-order 后层
/// 兄弟 SwiftUI 前层 view 收到事件后不 bubble 到兄弟 → 永不触发
/// 改用 local monitor：按鼠标位置判断是否在 self.bounds 内 · 不依赖 hit-test 链
fileprivate struct ScrollWheelCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCaptureNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ScrollCaptureNSView)?.onScroll = onScroll
    }
}

/// scrollWheel 捕获 NSView · 通过 NSEvent local monitor 主动监听
/// scrollingDeltaY 单位：trackpad ≈ 5-30 / event · 鼠标滚轮 ≈ 1-3 / event
private final class ScrollCaptureNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var monitor: Any?

    /// AppKit 保证 view dealloc 前会先调 viewDidMoveToWindow(window=nil)
    /// 故卸载逻辑放此处即可 · 不在 deinit 卸载（Swift 6 nonisolated deinit 不能访问 @MainActor 属性）
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let win = self.window,
                  event.window === win else {
                return event
            }
            let pointInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(pointInView) else {
                return event
            }
            self.onScroll?(event.scrollingDeltaY)
            return nil
        }
    }
}

// MARK: - file-scope helpers（让 ChartScene + ChartContentView 都能访问 · 避免 cross-struct 访问错误）

/// v13.6 画线类型中文标签 · 多处用（drawingInspector / drawingContextMenu / 模板列表 / 模板命名）
fileprivate func drawingTypeLabel(_ type: DrawingType) -> String {
    switch type {
    case .trendLine:       return "趋势线"
    case .horizontalLine:  return "水平线"
    case .rectangle:       return "矩形"
    case .parallelChannel: return "平行通道"
    case .fibonacci:       return "斐波那契"
    case .text:            return "文字标注"
    case .ellipse:         return "椭圆"
    case .ruler:           return "测量工具"
    case .pitchfork:       return "Pitchfork"
    case .polygon:         return "多边形"
    }
}

// MARK: - HUD 4 角位置（v13.34 · file scope 让 ChartScene + ChartContentView 都能访问）

enum HUDCorner: String, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading:     return .topLeading
        case .topTrailing:    return .topTrailing
        case .bottomLeading:  return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var label: String {
        switch self {
        case .topLeading:     return "左上"
        case .topTrailing:    return "右上"
        case .bottomLeading:  return "左下"
        case .bottomTrailing: return "右下"
        }
    }
}

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
    /// v13.19 副图多选 · selectedSubIndicators Set 替代单选 · 默认 [.macd]
    /// vertical stack 渲染多个 SubChartView · 高度按数量等分（每个最少 80pt）
    @State private var selectedSubIndicators: Set<SubIndicatorKind> = [.macd]
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

    /// v13.0 画线工具状态 · WP-42（数据模型在 v9.0 完成 · 此处为 UI 激活）
    @State private var drawings: [Drawing] = []
    @State private var activeDrawingTool: DrawingType?  // nil = 浏览模式 · 非 nil = 当前选中的画线工具
    @State private var pendingDrawingPoint: DrawingPoint?  // 双点画线的第一点（hover 跟随预览第二点）
    /// v13.17 Pitchfork 中间点（A 用 pendingDrawingPoint · B 暂存这里 · C 完成时点击）
    @State private var pendingExtraPoints: [DrawingPoint] = []
    /// v13.9 多选 · 选中的画线集合（高亮 + Delete 批量删除 · ⇧ 加选）
    @State private var selectedDrawingIDs: Set<UUID> = []
    @State private var isDrawingsLoaded: Bool = false  // 守卫：load 完成前的 drawings = [] 不触发 save
    /// v15.16 hotfix #13：load 是否成功（区别于 load 完成但失败 fallback 空）· 失败时禁 save 防坏档被空覆盖
    @State private var isDrawingsLoadOK: Bool = false
    /// v13.8 工具栏当前画线颜色 · 新建画线时应用 · 默认黄（与趋势线类型默认色一致）
    @State private var currentStrokeColor: Color = Color(red: 1.00, green: 0.78, blue: 0.18)
    /// v13.8 工具栏当前画线线宽（pt · 范围 0.5~5.0 步进 0.5）· 默认 1.5（与渲染层 baseWidth 一致）
    @State private var currentStrokeWidth: Double = 1.5
    /// v13.12 工具栏当前文字字号（pt · 范围 8~32 步进 1）· 默认 12（与渲染层 default 一致）· 仅 .text 工具激活时显示
    @State private var currentFontSize: Double = 12
    /// v13.16 画线模板（保存常用画线 · 跨合约复用）· UserDefaults 持久化（全局共享 · 不按合约/周期隔离）
    @State private var drawingTemplates: [DrawingTemplate] = []
    /// v13.16 模板已加载守卫（避免初始 [] 误覆盖）
    @State private var isTemplatesLoaded: Bool = false
    /// v13.21 副图偏好已加载守卫（避免初始默认值覆盖用户偏好）
    @State private var isSubPrefsLoaded: Bool = false
    /// v13.34 HUD 位置 · 4 角切换 · 默认左上 · 通过 @Binding 传给 ChartContentView · UserDefaults 持久化
    @State private var hudCorner: HUDCorner = .topLeading
    @State private var isHUDPrefLoaded: Bool = false
    /// v15.2 自定义指标参数（主图 MA/BOLL · 副图 MACD/KDJ/RSI）· UserDefaults 全局共享
    @State private var indicatorParams: IndicatorParamsBook = .default
    @State private var isIndicatorParamsLoaded: Bool = false
    /// v15.2 指标参数编辑 Sheet 显隐
    @State private var showIndicatorParamsSheet: Bool = false
    /// v15.7 副图独立参数 overrides · key = 副图槽位 0~3 · 缺失 = 用全局 indicatorParams
    @State private var subParamsOverrides: [Int: IndicatorParamsBook] = [:]
    /// v15.7 当前编辑的副图槽位（弹 sheet 时设 · sheet 关闭后清）
    @State private var editingSubSlot: Int? = nil
    /// v15.2 参数变更触发 updateIndicatorsFull 的链式串行 task · 防快速连续变更产生重叠重算
    @State private var indicatorParamsRecomputeTask: Task<Void, Never>?
    /// v15.8 主图主题（深色 / 浅色）· UserDefaults 全局共享
    @State private var chartTheme: ChartTheme = .dark
    @State private var isChartThemeLoaded: Bool = false
    /// v15.14 HUD 自定义字段（OHLC / 涨跌 / 成交量 / 持仓量 / 时间 / 调试）· UserDefaults 全局共享
    @State private var hudFields: HUDFieldsBook = .default
    @State private var isHUDFieldsLoaded: Bool = false
    @State private var showHUDFieldsSheet: Bool = false
    /// v15.17 InAppOverlayChannel 接收的预警 toast（3 秒自动消失 · 多个仅显示最新）
    @State private var alertToast: AlertToastInfo?
    @State private var alertToastDismissTask: Task<Void, Never>?

    private static let drawingTemplatesKey = "drawingTemplates.v1"
    /// v13.21 副图偏好持久化（重启保留 · 跨合约/周期共享）
    private static let subIndicatorsKey = "subIndicators.v1"
    // v15.16 hotfix #12：subChartHeightKey 已移到 ChartContentView 内（line 1727）· 此处死代码已删
    /// v13.34 HUD 位置持久化（4 角偏好）
    private static let hudCornerKey = "hudCorner.v1"

    /// v15.7 sheet(item:) 需要 Identifiable · Int 不能直接用 · 包一层
    fileprivate struct SubSlotIdentified: Identifiable {
        let slot: Int
        var id: Int { slot }
    }

    /// v15.7 副图独立参数 binding · sheet 编辑 · 缺 override 时用 indicatorParams 作 fallback
    /// 用户首次为某 slot 改参数时 fallback 注入 → override 写盘 · 后续直接读 override
    /// 注意：fallback 后整本 IndicatorParamsBook 都被"凝固"成当时的全局值；后续全局 indicatorParams
    /// 变更不再传播到此 slot（v1 接受 · 用户场景 = "我要这个 slot 独立调"）
    private func bindingForSubSlot(_ slot: Int) -> Binding<IndicatorParamsBook> {
        Binding(
            get: { subParamsOverrides[slot] ?? indicatorParams },
            set: { subParamsOverrides[slot] = $0 }
        )
    }

    /// v13.22 viewport 缩放级别按合约+周期记忆 · UserDefaults JSON · key prefix
    static func viewportKey(instrumentID: String, period: KLinePeriod) -> String {
        "viewport.v1.\(instrumentID).\(period.rawValue)"
    }

    /// v13.22 加载持久化 viewport · 失败回退到默认（最新 120 根）· bars.count 改变时 clamp 防越界
    /// v15.16 hotfix #6：visibleCount 不再 clamp 到 barsCount · 否则回放刚加载 1 根 → visibleCount=1
    /// → 单根 bar 撑满整窗 → 大红块（K 线模式 saved.visibleCount > 0 已 check · barsCount 限制无意义）
    static func loadViewport(instrumentID: String, period: KLinePeriod, barsCount: Int) -> RenderViewport {
        let key = viewportKey(instrumentID: instrumentID, period: period)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(RenderViewport.self, from: data),
           saved.visibleCount > 0 {
            let clampedStart = max(0, min(max(0, barsCount - 1), saved.startIndex))
            return RenderViewport(
                startIndex: clampedStart,
                visibleCount: saved.visibleCount,
                startOffset: saved.startOffset
            )
        }
        return RenderViewport(startIndex: max(0, barsCount - 120), visibleCount: 120)
    }

    /// M5 持久化：StoreManager 注入 · loadAndStream fast-path 读磁盘缓存 · snapshot/completedBar 异步落库
    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics
    @Environment(\.alertEvaluator) private var alertEvaluator
    @Environment(\.simulatedTradingEngine) private var simulatedTradingEngine
    @Environment(\.openWindow) private var openWindow

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
        .overlay(alignment: .top) {
            // v15.17 · InAppOverlayChannel 预警 toast（3 秒自动消失）
            if let toast = alertToast {
                alertToastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: alertToast?.id)
        .onReceive(NotificationCenter.default.publisher(for: InAppOverlayChannel.alertNotification)) { note in
            handleAlertToastNotification(note)
        }
        .background(periodShortcuts)
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .task(id: PipelineKey(mode: chartMode, instrumentID: currentInstrumentID, period: selectedPeriod)) {
            await resetForNewPipeline()
            // v13.0 WP-42 画线状态切合约/周期重载 · 各 (instrumentID, period) 组合独立持久化
            // v13.2 升级 UserDefaults JSON → SQLiteDrawingStore（M5 持久化 8/8）
            isDrawingsLoaded = false
            isDrawingsLoadOK = false
            // v15.16 hotfix #13：区分"load 成功 vs load 失败"· 失败时 isDrawingsLoadOK=false 禁 save 防坏档被空覆盖
            if let store = storeManager?.drawings {
                do {
                    drawings = try await store.load(instrumentID: currentInstrumentID, period: selectedPeriod)
                    isDrawingsLoadOK = true
                } catch {
                    print("⚠️ DrawingStore load failed for \(currentInstrumentID).\(selectedPeriod): \(error) · 已禁用 save 防坏档被空覆盖 · 重启可重试")
                    drawings = []
                    isDrawingsLoadOK = false
                }
            } else {
                drawings = []
                isDrawingsLoadOK = true  // 无 store 时空数组是合法状态
            }
            pendingDrawingPoint = nil
            pendingExtraPoints = []
            selectedDrawingIDs.removeAll()
            activeDrawingTool = nil
            isDrawingsLoaded = true
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
        .onChange(of: selectedSubIndicators) { newValue in
            // 埋点：用户切换副图指标组合（v13.19 多选）· 记最新组合
            // v15.16 hotfix #11：加 isSubPrefsLoaded 守卫 · 防 onAppear 加载偏好误触发埋点（与下方持久化 onChange 守卫保持一致）
            guard isSubPrefsLoaded else { return }
            guard let service = analytics else { return }
            let kinds = newValue.map(\.rawValue).sorted().joined(separator: ",")
            Task {
                _ = try? await service.record(
                    .indicatorAdd,
                    userID: FuturesTerminalApp.anonymousUserID,
                    properties: ["kinds": kinds]
                )
            }
        }
        .onChange(of: drawings) { newValue in
            // v13.2 WP-42 画线 SQLite 持久化（接 StoreManager.drawings · M5 持久化 8/8）
            // isDrawingsLoaded 守卫：避免初始 [] 误覆盖（同 alerts/trades/history 模式）
            // v15.16 hotfix #13：加 isDrawingsLoadOK 守卫 · load 失败时禁 save 防坏档被空覆盖
            guard isDrawingsLoaded, isDrawingsLoadOK, let store = storeManager?.drawings else { return }
            let id = currentInstrumentID
            let p = selectedPeriod
            Task { try? await store.save(newValue, instrumentID: id, period: p) }
        }
        .onAppear {
            // v13.16 模板首次加载（全局共享 · UserDefaults）· 仅一次
            if !isTemplatesLoaded {
                if let data = UserDefaults.standard.data(forKey: Self.drawingTemplatesKey),
                   let list = try? JSONDecoder().decode([DrawingTemplate].self, from: data) {
                    drawingTemplates = list
                }
                isTemplatesLoaded = true
            }
            // v13.21 副图选择偏好首次加载（重启保留 · 多窗口共享）· 仅一次
            // v15.x · 副图高度（subChartTotalHeight）持久化已移到 ChartContentView 内 onAppear/onChange
            //         避免 cross-struct 访问 @State / 嵌套 enum SubChart（Mac 编译错误）
            if !isSubPrefsLoaded {
                if let arr = UserDefaults.standard.array(forKey: Self.subIndicatorsKey) as? [String] {
                    let kinds = arr.compactMap { SubIndicatorKind(rawValue: $0) }
                    if !kinds.isEmpty { selectedSubIndicators = Set(kinds) }
                }
                isSubPrefsLoaded = true
            }
            // v13.34 HUD 位置首次加载
            if !isHUDPrefLoaded {
                if let raw = UserDefaults.standard.string(forKey: Self.hudCornerKey),
                   let corner = HUDCorner(rawValue: raw) {
                    hudCorner = corner
                }
                isHUDPrefLoaded = true
            }
            // v15.2 自定义指标参数首次加载（全局 UserDefaults · 跨合约共享）
            if !isIndicatorParamsLoaded {
                if let book = IndicatorParamsStore.load() {
                    indicatorParams = book
                }
                // v15.7 副图独立 overrides 同时加载（与 indicatorParams 同一守卫 · 1 次）
                if let ov = SubChartParamsOverridesStore.load() {
                    subParamsOverrides = ov
                }
                isIndicatorParamsLoaded = true
            }
            // v15.8 主题加载（独立守卫 · 与 indicatorParams 解耦）
            if !isChartThemeLoaded {
                if let theme = ChartThemeStore.load() {
                    chartTheme = theme
                }
                isChartThemeLoaded = true
            }
            // v15.14 HUD 字段加载（独立守卫 · UserDefaults 不存在 fallback default 仅 .debug）
            if !isHUDFieldsLoaded {
                if let book = HUDFieldsStore.load() {
                    hudFields = book
                }
                isHUDFieldsLoaded = true
            }
        }
        // v15.16 hotfix #13：多窗口 UserDefaults 同步（⌘N 开第二窗口时 · A 改 chartTheme.dark → B 实时跟）
        // 监听 UserDefaults.didChangeNotification · 任意进程内 set 都触发 · 重 load 6 个全局 key
        // 与当前 @State 比较 · 不同才更新（防 ping-pong）
        // hotfix #14 hotfix：内联巨大 closure 让 SwiftUI body 类型推断爆炸 · Mac 编译失败 · 拆 helper
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            syncFromUserDefaults()
        }
        .onChange(of: drawingTemplates) { newValue in
            // v13.16 模板持久化 UserDefaults · 加载守卫避免初始 [] 误覆盖
            guard isTemplatesLoaded else { return }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.drawingTemplatesKey)
            }
        }
        .onChange(of: selectedSubIndicators) { newValue in
            // v13.21 副图选择持久化（覆盖之前 v13.19 onChange 埋点 · 此处合并 save）
            guard isSubPrefsLoaded else { return }
            let arr = newValue.map(\.rawValue).sorted()
            UserDefaults.standard.set(arr, forKey: Self.subIndicatorsKey)
        }
        // v15.x · 副图高度持久化已移到 ChartContentView 内（避免 cross-struct 访问 @State）
        .onChange(of: hudCorner) { newValue in
            // v13.34 HUD 位置持久化
            guard isHUDPrefLoaded else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.hudCornerKey)
        }
        .onChange(of: indicatorParams) { newValue in
            // v15.2 指标参数持久化 + 触发主图重算（副图 SubChartView 自己 onChange 触发）
            // 链式串行（前一个完成才跑下一个）防快速连续变更产生重叠 updateIndicatorsFull
            guard isIndicatorParamsLoaded else { return }
            IndicatorParamsStore.save(newValue)
            let prev = indicatorParamsRecomputeTask
            let snap = bars
            indicatorParamsRecomputeTask = Task {
                await prev?.value
                await updateIndicatorsFull(snap)
            }
        }
        .sheet(isPresented: $showIndicatorParamsSheet) {
            IndicatorParamsSheet(book: $indicatorParams)
        }
        .onChange(of: subParamsOverrides) { newValue in
            // v15.7 副图独立参数 overrides 持久化（仅副图重算 · 主图不受影响）
            guard isIndicatorParamsLoaded else { return }
            SubChartParamsOverridesStore.save(newValue)
        }
        .onChange(of: chartTheme) { newValue in
            // v15.8 主题持久化（颜色 SwiftUI Binding 自动重渲染 · 不需手动 refresh）
            guard isChartThemeLoaded else { return }
            ChartThemeStore.save(newValue)
        }
        .onChange(of: hudFields) { newValue in
            // v15.14 HUD 字段持久化（独立守卫 · UserDefaults JSON）
            guard isHUDFieldsLoaded else { return }
            HUDFieldsStore.save(newValue)
        }
        .sheet(isPresented: $showHUDFieldsSheet) {
            HUDFieldsSheet(book: $hudFields)
        }
        .sheet(item: Binding(
            get: { editingSubSlot.map { SubSlotIdentified(slot: $0) } },
            set: { editingSubSlot = $0?.slot }
        )) { ident in
            // v15.7 副图独立参数编辑 sheet · book binding 走 effectiveBindingForSlot
            IndicatorParamsSheet(book: bindingForSubSlot(ident.slot))
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
            // v15.16 hotfix #12：补 cancel indicatorParamsRecomputeTask · 之前关窗口后旧 task 仍跑数 ms
            // 注：inertiaTask 在 ChartContentView scope · 不能跨 struct 访问 · SwiftUI view 销毁时自动 cancel
            indicatorParamsRecomputeTask?.cancel()
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

    /// v15.16 hotfix #14：多窗口 UserDefaults 同步 helper · 拆出避免 SwiftUI body 类型推断爆炸（Mac 编译错）
    /// 任意进程内 UserDefaults set 触发 · reload 6 个全局 key · 与当前 @State 比较不同才 update（防 ping-pong）
    private func syncFromUserDefaults() {
        if isChartThemeLoaded, let theme = ChartThemeStore.load(), theme != chartTheme {
            chartTheme = theme
        }
        if isHUDFieldsLoaded, let book = HUDFieldsStore.load(), book != hudFields {
            hudFields = book
        }
        if isHUDPrefLoaded,
           let raw = UserDefaults.standard.string(forKey: Self.hudCornerKey),
           let corner = HUDCorner(rawValue: raw),
           corner != hudCorner {
            hudCorner = corner
        }
        if isIndicatorParamsLoaded {
            if let book = IndicatorParamsStore.load(), book != indicatorParams {
                indicatorParams = book
            }
            if let ov = SubChartParamsOverridesStore.load(), ov != subParamsOverrides {
                subParamsOverrides = ov
            }
        }
        if isSubPrefsLoaded,
           let arr = UserDefaults.standard.array(forKey: Self.subIndicatorsKey) as? [String] {
            let kinds = Set(arr.compactMap { SubIndicatorKind(rawValue: $0) })
            if !kinds.isEmpty && kinds != selectedSubIndicators {
                selectedSubIndicators = kinds
            }
        }
        if isTemplatesLoaded,
           let data = UserDefaults.standard.data(forKey: Self.drawingTemplatesKey),
           let list = try? JSONDecoder().decode([DrawingTemplate].self, from: data),
           list != drawingTemplates {
            drawingTemplates = list
        }
    }

    /// v15.17 · InAppOverlayChannel toast 信息（NotificationCenter userInfo 解码）
    struct AlertToastInfo: Equatable {
        let id: UUID  // 用于 transition 切换识别
        let alertName: String
        let instrumentID: String
        let triggerPrice: Decimal
        let message: String
    }

    /// v15.17 · 处理预警 toast 通知（InAppOverlayChannel.alertNotification）
    private func handleAlertToastNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let alertID = info["alertID"] as? UUID,
              let alertName = info["alertName"] as? String,
              let instrumentID = info["instrumentID"] as? String,
              let triggerPrice = info["triggerPrice"] as? Decimal,
              let message = info["message"] as? String else { return }
        alertToast = AlertToastInfo(
            id: alertID,
            alertName: alertName,
            instrumentID: instrumentID,
            triggerPrice: triggerPrice,
            message: message
        )
        // 3 秒自动消失（取消旧 task 防多 toast 提前消失）
        alertToastDismissTask?.cancel()
        alertToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            alertToast = nil
        }
    }

    /// v15.17 · 预警 toast view · 与主题色对齐（hudBackground + textPrimary）
    @ViewBuilder
    private func alertToastView(_ toast: AlertToastInfo) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .foregroundColor(chartTheme.candleBull)
                Text(toast.alertName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(chartTheme.textPrimary)
                Spacer()
                Button {
                    alertToast = nil
                    alertToastDismissTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(chartTheme.textSecondary)
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 6) {
                Text("\(toast.instrumentID) @ \(NSDecimalNumber(decimal: toast.triggerPrice).stringValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(chartTheme.textSecondary)
                Spacer()
            }
            if !toast.message.isEmpty {
                Text(toast.message)
                    .font(.system(size: 11))
                    .foregroundColor(chartTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 360)
        .background(chartTheme.hudBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(chartTheme.candleBull.opacity(0.35), lineWidth: 1)
        )
    }

    /// 模式/合约/周期切换前重置：先 stop player → driver → 再 cancel observe（避免 player emit 时 consumer 已退出）
    /// v15.16 hotfix #12：等 klineSaveTask 完成 · 防新合约 task 链式 await prev 阻塞 UI
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
        // 等旧合约链式落库完成 · 不延续到新合约 task
        await klineSaveTask?.value
        klineSaveTask = nil

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
        indicatorRunner = ChartIndicatorRunner.prime(bars: snap, params: indicatorParams)
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
    /// v13.1 加 Delete 键删除选中画线
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
            // v13.9 多选 · Delete 批量删除全部 selectedDrawingIDs · v13.11 跳过锁定的画线
            Button("") {
                let deletable = drawings.filter { selectedDrawingIDs.contains($0.id) && !$0.locked }.map(\.id)
                if !deletable.isEmpty {
                    let deletableSet = Set(deletable)
                    drawings.removeAll { deletableSet.contains($0.id) }
                    selectedDrawingIDs.subtract(deletableSet)
                }
            }
            .keyboardShortcut(.delete, modifiers: [])
            // v13.9 多选 · ⌘D 批量复制全部选中（每条偏移 +20 bar / 5% 价格）· v13.11 副本不继承 isLocked（让用户能用）
            Button("") {
                let toClone = drawings.filter { selectedDrawingIDs.contains($0.id) }
                if !toClone.isEmpty {
                    let copies = toClone.map { duplicatedDrawing($0) }
                    drawings.append(contentsOf: copies)
                    selectedDrawingIDs = Set(copies.map(\.id))
                }
            }
            .keyboardShortcut("d", modifiers: [.command])
            // v13.27 ⌘⇧S 一键保存选中画线为模板（仅 n=1 + 未锁时响应）
            Button("") {
                if selectedDrawingIDs.count == 1,
                   let id = selectedDrawingIDs.first,
                   let drawing = drawings.first(where: { $0.id == id }),
                   !drawing.locked {
                    saveCurrentAsTemplate(drawing)
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            // v13.28 ⌘⇧L 一键切换选中画线锁定状态（全锁 → 全解锁 · 否则 → 全锁）
            Button("") {
                guard !selectedDrawingIDs.isEmpty else { return }
                let selected = drawings.filter { selectedDrawingIDs.contains($0.id) }
                let allLocked = selected.allSatisfy { $0.locked }
                setLocked(!allLocked, for: selectedDrawingIDs)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - 画线工具组（v13.0 · WP-42 UI 激活 · v13.2 持久化升级 SQLiteDrawingStore）

    /// 工具条画线工具按钮组：选择 / 6 种画线 / 颜色 / 线宽 / 导出导入 / 清空
    /// v13.7 加导出/导入 · v13.8 加 ColorPicker + Stepper（颜色/线宽自定义）
    private var drawingTools: some View {
        HStack(spacing: 4) {
            drawingToolButton(icon: "cursorarrow", tool: nil, help: "浏览（取消画线工具）")
            drawingToolButton(icon: "line.diagonal", tool: .trendLine, help: "趋势线（双点）")
            drawingToolButton(icon: "minus", tool: .horizontalLine, help: "水平线（一点）")
            drawingToolButton(icon: "rectangle", tool: .rectangle, help: "矩形（双点对角）")
            drawingToolButton(icon: "lines.measurement.horizontal", tool: .parallelChannel, help: "平行通道（双点 · 默认 +1.0 偏移）")
            drawingToolButton(icon: "function", tool: .fibonacci, help: "斐波那契回调（双点）")
            drawingToolButton(icon: "circle", tool: .ellipse, help: "椭圆（双点对角）")
            drawingToolButton(icon: "ruler", tool: .ruler, help: "测量工具（双点 · 显示价格差/百分比/bar 数）")
            drawingToolButton(icon: "tuningfork", tool: .pitchfork, help: "Andrew's Pitchfork（3 点 · 中线 + 上下平行轨）")
            drawingToolButton(icon: "hexagon", tool: .polygon, help: "多边形（任意 N≥3 点 · 工具栏'完成'触发闭合）")
            drawingToolButton(icon: "textformat", tool: .text, help: "文字标注（一点）")
            // v13.31 多边形完成按钮 · 仅 polygon 工具激活 + 已点 ≥ 2 点（含起点 ≥ 3 点）时显示
            if activeDrawingTool == .polygon, pendingDrawingPoint != nil {
                let totalPoints = 1 + pendingExtraPoints.count
                Button(action: { finishPolygonFromToolbar() }) {
                    Text("完成（\(totalPoints) 点）")
                        .font(.system(size: 10, design: .monospaced))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(totalPoints < 3)
                .help("闭合多边形（至少 3 点）")
            }
            // v13.8 颜色 / 线宽自定义（仅作用于新建 · 已有画线通过右键菜单"应用当前颜色/线宽"修改）
            Divider().frame(height: 16)
            ColorPicker("", selection: $currentStrokeColor, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28)
                .help("画线颜色 + 透明度（v13.15 alpha 通道 · 新建生效 · 老画线右键应用）")
            Stepper(value: $currentStrokeWidth, in: 0.5...5.0, step: 0.5) {
                Text(String(format: "%.1f", currentStrokeWidth))
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 24)
            }
            .help("画线线宽 0.5~5.0 pt（新建生效 · 老画线右键应用）")
            // v13.12 字号 Stepper 仅 .text 工具激活时显示（节省工具栏空间）
            if activeDrawingTool == .text {
                Stepper(value: $currentFontSize, in: 8...32, step: 1) {
                    Text("\(Int(currentFontSize))pt")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 32)
                }
                .help("文字字号 8~32 pt（新建文字应用 · 老文字右键修改字号）")
            }
            Divider().frame(height: 16)
            // v13.16 画线模板 Menu（保存常用 · 跨合约复用）
            templatesMenu
            Divider().frame(height: 16)
            Button { exportDrawings() } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("导出当前合约+周期画线为 JSON")
            Button { importDrawings() } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("从 JSON 导入画线")
            Button {
                drawings.removeAll()
                pendingDrawingPoint = nil
                pendingExtraPoints = []
                selectedDrawingIDs.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("清空所有画线")
        }
    }

    // MARK: - v13.7 画线导出/导入 JSON

    /// 导出当前 (instrumentID, period) 的画线为 JSON 文件（NSSavePanel）
    private func exportDrawings() {
        guard !drawings.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无画线可导出"
            alert.informativeText = "当前合约 \(currentInstrumentID) \(selectedPeriod.displayName) 没有画线。"
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出画线"
        panel.allowedContentTypes = [.json]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "drawings_\(currentInstrumentID)_\(selectedPeriod.rawValue)_\(dateFormatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(drawings)
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    /// 导入 JSON 画线 · 弹 alert 询问覆盖/追加/取消
    private func importDrawings() {
        let panel = NSOpenPanel()
        panel.title = "导入画线"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([Drawing].self, from: data)
            let alert = NSAlert()
            alert.messageText = "导入画线"
            alert.informativeText = "解析到 \(imported.count) 个画线。当前已有 \(drawings.count) 个。\n\n选择操作："
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "追加")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                drawings = imported
            } else if response == .alertSecondButtonReturn {
                drawings.append(contentsOf: imported)
            }
            // 取消 → 不动
        } catch {
            let alert = NSAlert()
            alert.messageText = "导入失败"
            alert.informativeText = "JSON 解析失败：\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    /// v13.16 画线模板 Menu · 列出已存模板（点击即插入到当前合约）+ 保存当前选中 + 删全部
    private var templatesMenu: some View {
        Menu {
            if drawingTemplates.isEmpty {
                Text("（无模板 · 选中画线后点下方保存项）")
                    .foregroundColor(.secondary)
            } else {
                ForEach(drawingTemplates) { template in
                    Button("\(template.name) · \(drawingTypeLabel(template.drawing.type))") {
                        let d = instantiateTemplate(template)
                        drawings.append(d)
                        selectedDrawingIDs = [d.id]
                    }
                }
                Divider()
            }
            // 保存选中画线为模板（仅 n=1 + 未锁时可点）
            if selectedDrawingIDs.count == 1,
               let id = selectedDrawingIDs.first,
               let drawing = drawings.first(where: { $0.id == id }),
               !drawing.locked {
                Button("保存选中画线为模板…") {
                    saveCurrentAsTemplate(drawing)
                }
            }
            if !drawingTemplates.isEmpty {
                Button("删除全部模板（\(drawingTemplates.count) 个）", role: .destructive) {
                    confirmDeleteAllTemplates()
                }
            }
        } label: {
            Image(systemName: "star")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("画线模板（保存常用 / 一键插入 · 跨合约复用）")
    }

    /// v13.16 从模板实例化新画线 · 锚点重定位到最新 30 根 bar 区间（可见区附近）· 价格保留模板原值
    private func instantiateTemplate(_ template: DrawingTemplate) -> Drawing {
        var drawing = template.drawing
        drawing.id = UUID()
        drawing.isLocked = nil  // 模板不应继承锁
        let baseBar = max(0, bars.count - 30)
        if let end = drawing.endPoint {
            let deltaBars = end.barIndex - drawing.startPoint.barIndex
            drawing.startPoint = DrawingPoint(barIndex: baseBar, price: drawing.startPoint.price)
            drawing.endPoint = DrawingPoint(barIndex: baseBar + max(1, deltaBars), price: end.price)
        } else {
            drawing.startPoint = DrawingPoint(barIndex: baseBar, price: drawing.startPoint.price)
        }
        return drawing
    }

    /// v15.x · 在 ChartScene scope 内的画线复制简化版（不依赖 ChartContentView.currentPriceRange）
    /// 偏移：20 bar + startPoint.price 的 0.5% 作绝对偏移 · 原 ChartContentView 用 priceSpan*5% 更精准
    /// 当前 keyboardShortcut Button 在 ChartScene 内 · 必须 file scope 函数 · 折衷为用 startPoint 价格基准
    private func duplicatedDrawing(_ drawing: Drawing) -> Drawing {
        let barOffset = 20
        let priceOffset = drawing.startPoint.price * Decimal(string: "0.005")!
        let newStart = DrawingPoint(barIndex: drawing.startPoint.barIndex + barOffset,
                                    price: drawing.startPoint.price + priceOffset)
        let newEnd: DrawingPoint? = drawing.endPoint.map {
            DrawingPoint(barIndex: $0.barIndex + barOffset, price: $0.price + priceOffset)
        }
        let newExtras: [DrawingPoint]? = drawing.extraPoints?.map {
            DrawingPoint(barIndex: $0.barIndex + barOffset, price: $0.price + priceOffset)
        }
        return Drawing(
            id: UUID(),
            type: drawing.type,
            startPoint: newStart,
            endPoint: newEnd,
            text: drawing.text,
            channelOffset: drawing.channelOffset,
            strokeColorHex: drawing.strokeColorHex,
            strokeWidth: drawing.strokeWidth,
            isLocked: nil,
            fontSize: drawing.fontSize,
            strokeOpacity: drawing.strokeOpacity,
            extraPoints: newExtras,
            isBold: drawing.isBold,
            isItalic: drawing.isItalic,
            isUnderline: drawing.isUnderline
        )
    }

    /// v15.x · 在 ChartScene scope 内的批量锁定（直接 mutate drawings @State · 与 ChartContentView 同实现）
    private func setLocked(_ locked: Bool, for ids: Set<UUID>) {
        for i in drawings.indices where ids.contains(drawings[i].id) {
            drawings[i].isLocked = locked ? true : nil
        }
    }

    /// v13.16 保存选中画线为模板 · NSAlert 输入名称
    private func saveCurrentAsTemplate(_ drawing: Drawing) {
        let alert = NSAlert()
        alert.messageText = "保存为模板"
        alert.informativeText = "输入模板名称（已存 \(drawingTemplates.count) 个）："
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        let typeName = drawingTypeLabel(drawing.type)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MM-dd HH:mm"
        textField.stringValue = "\(typeName) \(dateFmt.string(from: Date()))"
        alert.accessoryView = textField
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.isEmpty ? typeName : textField.stringValue
            var clean = drawing
            clean.id = UUID()
            clean.isLocked = nil
            let template = DrawingTemplate(name: name, drawing: clean)
            drawingTemplates.append(template)
        }
    }

    /// v13.16 删全部模板（confirmation alert）
    private func confirmDeleteAllTemplates() {
        let alert = NSAlert()
        alert.messageText = "删除全部模板"
        alert.informativeText = "确认删除全部 \(drawingTemplates.count) 个画线模板？此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            drawingTemplates.removeAll()
        }
    }

    private func drawingToolButton(icon: String, tool: DrawingType?, help: String) -> some View {
        Button {
            activeDrawingTool = tool
            pendingDrawingPoint = nil
            pendingExtraPoints = []
        } label: {
            Image(systemName: icon)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .padding(2)
        .background(activeDrawingTool == tool ? Color.accentColor.opacity(0.3) : Color.clear)
        .cornerRadius(4)
        .help(help)
    }

    /// v13.31 工具栏"完成（n 点）"按钮 · 闭合多边形 · 至少 3 点（startPoint + ≥2 extra）
    /// ChartScene 入口（与 ChartContentView.finishPolygon 等价 · 工具栏 Button 在 ChartScene 范围内调用）
    private func finishPolygonFromToolbar() {
        guard let first = pendingDrawingPoint, pendingExtraPoints.count >= 2 else { return }
        let drawing = Drawing(
            type: .polygon,
            startPoint: first,
            strokeColorHex: ChartContentView.hexString(from: currentStrokeColor),
            strokeWidth: currentStrokeWidth,
            strokeOpacity: ChartContentView.alphaComponent(from: currentStrokeColor),
            extraPoints: pendingExtraPoints
        )
        drawings.append(drawing)
        pendingDrawingPoint = nil
        pendingExtraPoints = []
        activeDrawingTool = nil
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

            // v13.19 副图多选 · Menu 弹下拉显示 4 个 Toggle（用户可同时选 1~4 个 · vertical stack 显示）
            Menu {
                ForEach(SubIndicatorKind.allCases) { k in
                    Button(action: {
                        if selectedSubIndicators.contains(k) {
                            // 至少保留 1 个不允许全部取消（防 UI 空白）
                            if selectedSubIndicators.count > 1 {
                                selectedSubIndicators.remove(k)
                            }
                        } else {
                            selectedSubIndicators.insert(k)
                        }
                    }) {
                        Label(k.shortName, systemImage: selectedSubIndicators.contains(k) ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                let count = selectedSubIndicators.count
                Text(count == 1 ? selectedSubIndicators.first!.shortName : "副图 \(count)")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
            .help("副图指标多选（至少 1 · 最多 4 · vertical stack 显示）")

            Divider().frame(height: 16)
            drawingTools

            Divider().frame(height: 16)
            // v15.2 自定义指标参数齿轮按钮 · 右键/单击打开 Sheet 表单
            Button {
                showIndicatorParamsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("指标参数（MA / BOLL / MACD / KDJ / RSI 周期可调）")

            // v15.4 · 模拟交易快捷入口（⌘T · 与主菜单 OpenTradingButton 对齐）
            Button {
                openWindow(id: "trading")
            } label: {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("模拟交易（⌘T · SimNow 模拟训练）")

            // v15.8 · 主题切换（深色 ↔ 浅色 · UserDefaults 持久化）
            Button {
                chartTheme = (chartTheme == .dark) ? .light : .dark
            } label: {
                Image(systemName: chartTheme.icon)
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("切换 \(chartTheme == .dark ? "浅色" : "深色") 主题")

            // v15.14 · HUD 字段自定义按钮（OHLC / 涨跌 / 成交量 / 持仓量 / 时间 / 调试 全可选）
            Button {
                showHUDFieldsSheet = true
            } label: {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("HUD 显示字段（OHLC / 成交量 / 持仓量 / 时间 等可选）")

            Spacer()
            Text("⌘N 新窗口 · ⌘L 自选 · ⌘T 模拟交易")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 32)
        // v15.8 toolbar 背景跟随主题（深 #15171C / 浅 #ECEEF1 · 替代 .bar 系统默认 · 与主图协调）
        .background(chartTheme.toolbarBackground)
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
                subIndicatorKinds: Array(selectedSubIndicators).sorted(by: { $0.rawValue < $1.rawValue }),
                preSettle: preSettle,
                indicatorParams: indicatorParams,
                subParamsOverrides: subParamsOverrides,
                onEditSubSlot: { slot in editingSubSlot = slot },
                chartTheme: chartTheme,
                hudFields: hudFields,
                drawings: $drawings,
                activeDrawingTool: $activeDrawingTool,
                pendingDrawingPoint: $pendingDrawingPoint,
                pendingExtraPoints: $pendingExtraPoints,
                selectedDrawingIDs: $selectedDrawingIDs,
                currentStrokeColor: $currentStrokeColor,
                currentStrokeWidth: $currentStrokeWidth,
                currentFontSize: $currentFontSize,
                hudCorner: $hudCorner,
                viewportSaveKey: Self.viewportKey(instrumentID: currentInstrumentID, period: selectedPeriod),
                initialViewport: Self.loadViewport(
                    instrumentID: currentInstrumentID,
                    period: selectedPeriod,
                    barsCount: bars.count
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
                // v15.x · 同步喂 onBar 给指标条件预警评估（spec.period 不匹配的 alert evaluator 内部跳过）
                let simulatedTick = Self.simulatedTick(from: k)
                if let evaluator = alertEvaluator {
                    await evaluator.onTick(simulatedTick)
                    await evaluator.onBar(k, instrumentID: instrumentID, period: period)
                }
                // v15.4 · 模拟撮合引擎吃同一条假 Tick · 触发委托撮合 + 持仓盯市浮盈刷新
                if let trading = simulatedTradingEngine {
                    await trading.onTick(simulatedTick)
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
        let params = indicatorParams
        let result = await Task.detached(priority: .userInitiated) {
            let b = MockKLineData.generateBars(5_000)
            let i = MockKLineData.computeIndicators(bars: b, params: params)
            return (b, i)
        }.value
        bars = result.0
        indicators = result.1
        indicatorRunner = ChartIndicatorRunner.prime(bars: result.0, params: indicatorParams)
        // v15.16 hotfix #12：mock fallback 时同步 periodLabel · 之前 HUD 主标识行显示 "RB0 · — · ..."
        instrumentLabel = currentInstrumentID
        periodLabel = selectedPeriod.displayName
        dataSourceLabel = "Sina 不可达 · 已退回 Mock"
    }

    /// 200 根 ~10ms / 5k 根 ~50ms · 8× 回放速度下成为热路径瓶颈，下版本接 IndicatorCore 增量 API
    private func computeIndicatorsAsync(_ snap: [KLine]) async -> [IndicatorSeries] {
        let params = indicatorParams
        return await Task.detached(priority: .userInitiated) {
            MockKLineData.computeIndicators(bars: snap, params: params)
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
    let subIndicatorKinds: [SubIndicatorKind]  // v13.19 多副图（vertical stack · 至少 1 个）
    /// v12.1 真昨结算 · priceTopBar baseline · nil 时 fallback bars.first.close（由 ChartScene 父级注入）
    let preSettle: Decimal?
    /// v15.2 自定义指标参数（主图 MA/BOLL · 副图 MACD/KDJ/RSI）· 由 ChartScene 父级 onChange 触发重渲染
    let indicatorParams: IndicatorParamsBook
    /// v15.7 副图独立参数 overrides · 缺失 = 用 indicatorParams 全局
    let subParamsOverrides: [Int: IndicatorParamsBook]
    /// v15.7 用户右键副图选"参数..."时回调 · 通知父级 ChartScene 弹 sheet 编辑该 slot
    let onEditSubSlot: (Int) -> Void
    /// v15.8 主图主题（深色 / 浅色）· 影响背景 / 文字 / 网格 / candle 配色
    let chartTheme: ChartTheme
    /// v15.14 HUD 自定义字段（按 fields 渲染各可选项）
    let hudFields: HUDFieldsBook
    /// v13.0 WP-42 画线状态（绑定 ChartScene · 父子双向同步）
    @Binding var drawings: [Drawing]
    @Binding var activeDrawingTool: DrawingType?
    @Binding var pendingDrawingPoint: DrawingPoint?
    /// v13.17 Pitchfork B 点 / v13.31 多边形 N≥2 点（startPoint=第 1 点 · 这里是第 2~N 点）
    @Binding var pendingExtraPoints: [DrawingPoint]
    /// v13.9 多选 · selected 集合（替换 v13.0 单 UUID? · ⇧ 加选 + 批量删/复制）
    @Binding var selectedDrawingIDs: Set<UUID>
    /// v13.8 工具栏当前颜色 · 新建画线应用 · 右键"应用当前颜色"批量改已有
    @Binding var currentStrokeColor: Color
    /// v13.8 工具栏当前线宽 · 同上
    @Binding var currentStrokeWidth: Double
    /// v13.12 工具栏当前字号 · 新建文字标注应用（仅 .text 工具激活时显示 Stepper）
    @Binding var currentFontSize: Double
    /// v13.22 viewport 持久化 key（按 instrumentID + period 隔离）· onChange viewport 写 UserDefaults
    let viewportSaveKey: String
    /// v13.22 viewport save 节流 · 1s 间隔最多 1 次（避免 panGesture 60Hz 写盘）
    @State var lastViewportSaveTime: Date = .distantPast
    /// v13.3 hover 跟踪 · 双点画线第二点 hover 预览（虚线）
    @State var hoverDataPoint: DrawingPoint?
    /// v13.20 副图区总高度 · 用户拖分割条调整 · 范围 80~480pt（默认 160 = subChartHeight 单副图）
    /// v15.16 hotfix #13：init 时同步 load · 防 ChartContentView 切合约重建时 onAppear 异步加载导致 160→保存值闪烁
    @State var subChartTotalHeight: CGFloat = {
        let h = UserDefaults.standard.double(forKey: ChartContentView.subChartHeightKey)
        return (h >= SubChart.minHeight && h <= SubChart.maxHeight) ? CGFloat(h) : SubChart.defaultHeight
    }()
    /// v13.20 拖分割条时的起始高度 · onChanged 累加 translation 算新高度
    @State var dragStartSubHeight: CGFloat?
    /// v13.10 anchor 拖动目标 · onChanged 第一次落 · 释放清空
    @State var anchorDragTarget: AnchorDragTarget?
    /// v13.10 拖动状态 · 距离 ≥ 4 像素 + anchor 命中后置 true · 释放时 false 视为 tap
    @State var isDraggingAnchor: Bool = false
    /// v13.30 HUD 显隐切换（⌘⇧H · 截图前暂时隐藏可让画面更干净）· 默认显示
    @State var showHUD: Bool = true
    /// v13.34 HUD 显示位置（4 角切换 · @Binding 来自 ChartScene · UserDefaults 持久化）
    @Binding var hudCorner: HUDCorner
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?
    @State var inertiaTask: Task<Void, Never>?

    /// v13.10 拖动目标 · 唯一定位某 drawing 的某 anchor（startPoint vs endPoint）
    /// v13.33 加 extraIndex 支持 extraPoints[i] 拖动（多边形 N 顶点 / Pitchfork C 点）
    struct AnchorDragTarget: Equatable {
        let drawingID: UUID
        let isStart: Bool
        /// nil = startPoint(isStart=true) 或 endPoint(isStart=false)
        /// 非 nil = extraPoints[extraIndex]（v13.33）
        var extraIndex: Int? = nil
    }

    init(
        renderer: MetalKLineRenderer,
        bars: [KLine],
        indicators: [IndicatorSeries],
        instrumentLabel: String,
        periodLabel: String,
        dataSourceLabel: String,
        subIndicatorKinds: [SubIndicatorKind],
        preSettle: Decimal?,
        indicatorParams: IndicatorParamsBook,
        subParamsOverrides: [Int: IndicatorParamsBook],
        onEditSubSlot: @escaping (Int) -> Void,
        chartTheme: ChartTheme,
        hudFields: HUDFieldsBook,
        drawings: Binding<[Drawing]>,
        activeDrawingTool: Binding<DrawingType?>,
        pendingDrawingPoint: Binding<DrawingPoint?>,
        pendingExtraPoints: Binding<[DrawingPoint]>,
        selectedDrawingIDs: Binding<Set<UUID>>,
        currentStrokeColor: Binding<Color>,
        currentStrokeWidth: Binding<Double>,
        currentFontSize: Binding<Double>,
        hudCorner: Binding<HUDCorner>,
        viewportSaveKey: String,
        initialViewport: RenderViewport
    ) {
        self.renderer = renderer
        self.bars = bars
        self.indicators = indicators
        self.instrumentLabel = instrumentLabel
        self.periodLabel = periodLabel
        self.dataSourceLabel = dataSourceLabel
        self.subIndicatorKinds = subIndicatorKinds
        self.preSettle = preSettle
        self.indicatorParams = indicatorParams
        self.subParamsOverrides = subParamsOverrides
        self.onEditSubSlot = onEditSubSlot
        self.chartTheme = chartTheme
        self.hudFields = hudFields
        self._drawings = drawings
        self._activeDrawingTool = activeDrawingTool
        self._pendingDrawingPoint = pendingDrawingPoint
        self._pendingExtraPoints = pendingExtraPoints
        self._selectedDrawingIDs = selectedDrawingIDs
        self._currentStrokeColor = currentStrokeColor
        self._currentStrokeWidth = currentStrokeWidth
        self._currentFontSize = currentFontSize
        self._hudCorner = hudCorner
        self.viewportSaveKey = viewportSaveKey
        self._viewport = State(initialValue: initialViewport)
    }

    /// 副图高度（v13.20 改为可拖分割条调整 · subChartTotalHeight @State 替代）
    static let subChartHeight: CGFloat = 160

    /// v13.20 分割条配置（高度范围 + 默认）
    enum SubChart {
        static let defaultHeight: CGFloat = 160
        static let minHeight: CGFloat = 80
        static let maxHeight: CGFloat = 480
    }

    /// v13.20 主图 ↔ 副图可拖分割条 · 4pt 区域捕获 · DragGesture 改 subChartTotalHeight
    /// 拖动方向：向上拖 = 副图变高（dy < 0 → height +=） · 向下拖 = 副图变矮
    /// v15.10 用 chartTheme.gridLine 与副图分割条对齐
    /// v15.16 hotfix #8：Rectangle().fill(.clear) 也可能被 SwiftUI elide → 用 chartTheme.background
    /// 与主图同色（浅色白 / 深色黑）= 视觉上 4pt 是主图背景延伸 · overlay 1pt gridLine 居中显细线
    private var mainSubDivider: some View {
        chartTheme.background
            .frame(height: 4)
            .overlay(chartTheme.gridLine.frame(height: 1))
            .contentShape(Rectangle())
            .onHover { hovering in
                // 用 .set() 替代 push/pop · 避免 hovering 多次触发或 view 销毁导致 cursor 栈失衡
                // hovering=false 不主动还原 · macOS 指针离开 view 时会自动重新 resolve cursor
                if hovering {
                    NSCursor.resizeUpDown.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartSubHeight == nil {
                            dragStartSubHeight = subChartTotalHeight
                        }
                        let base = dragStartSubHeight ?? subChartTotalHeight
                        let delta = -value.translation.height  // 向上拖 = 副图变高
                        let newHeight = base + delta
                        subChartTotalHeight = max(SubChart.minHeight, min(SubChart.maxHeight, newHeight))
                    }
                    .onEnded { _ in
                        dragStartSubHeight = nil
                    }
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                chartMainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                KLineAxisView(
                    bars: bars,
                    viewport: viewport,
                    priceRange: currentPriceRange,
                    orientation: .price,
                    axisBackground: chartTheme.background,
                    axisTextColor: chartTheme.textSecondary
                )
                .frame(width: 60)
            }
            // 视觉迭代第 9 项：主图 ↔ 副图分割线 · v13.20 升级为可拖分割条（4pt 高度 · 鼠标 hover 显示 row cursor · 拖动改副图总高度）
            mainSubDivider
            // 副图区 v13.19 多副图 vertical stack · 共享主图 viewport · 总高度 v13.20 用户可拖
            // 副图之间分隔 v15.16 hotfix #9：与主副图分隔条统一视觉 · chartTheme.background 1pt 同色
            // 副图自身网格/柱状图有视觉边界 · 1pt 同色让副图自然紧贴 · 不显黑线
            let count = max(1, subIndicatorKinds.count)
            let perSubHeight: CGFloat = subChartTotalHeight / CGFloat(count)
            VStack(spacing: 0) {
                ForEach(Array(subIndicatorKinds.enumerated()), id: \.element) { idx, kind in
                    if idx > 0 {
                        chartTheme.background.frame(height: 1)
                    }
                    HStack(spacing: 0) {
                        SubChartView(
                            bars: bars,
                            viewport: viewport,
                            kind: kind,
                            params: subParamsOverrides[idx] ?? indicatorParams,
                            slotIndex: idx,
                            onEditParams: { onEditSubSlot(idx) },
                            chartTheme: chartTheme
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        chartTheme.background
                            .frame(width: 60)
                    }
                    .frame(height: perSubHeight)
                }
            }
            .frame(height: subChartTotalHeight)
            KLineAxisView(
                bars: bars,
                viewport: viewport,
                priceRange: currentPriceRange,
                orientation: .time,
                axisBackground: chartTheme.background,
                axisTextColor: chartTheme.textSecondary
            )
            .frame(height: 28)
        }
        .frame(minWidth: 800, idealWidth: 1280, minHeight: 480, idealHeight: 720)
        .background(viewportShortcuts)
        .onChange(of: viewport) { newValue in
            // v13.22 viewport 节流持久化（panGesture 60Hz · 1s 节流避免高频写盘）
            let now = Date()
            guard now.timeIntervalSince(lastViewportSaveTime) >= 1 else { return }
            lastViewportSaveTime = now
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: viewportSaveKey)
            }
        }
        // v15.x · 副图高度 onAppear 加载（从 UserDefaults · 历史 v13.21 此持久化在 ChartScene 内但跨 struct 错 · 本次修到 ChartContentView）
        .onAppear {
            let h = UserDefaults.standard.double(forKey: ChartContentView.subChartHeightKey)
            if h >= SubChart.minHeight && h <= SubChart.maxHeight {
                subChartTotalHeight = CGFloat(h)
            }
        }
        .onChange(of: subChartTotalHeight) { newValue in
            // v15.x · 副图高度 onChange 持久化（用户拖分割条改高度即时存）
            UserDefaults.standard.set(Double(newValue), forKey: ChartContentView.subChartHeightKey)
        }
        .onDisappear {
            // v15.16 hotfix #11：强制 flush 节流尾巴 · 防最后 1s 内拖动后停手切合约 viewport 不写盘
            if let data = try? JSONEncoder().encode(viewport) {
                UserDefaults.standard.set(data, forKey: viewportSaveKey)
            }
        }
        .task {
            // v15.16 hotfix #12：切合约 ChartContentView 重建时重置 · 防 HUD 残留旧 lastFrameMs
            lastFrameMs = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let stats = await renderer.lastStats
                lastFrameMs = stats.lastFrameDuration * 1000
            }
        }
    }

    /// v15.x · 副图高度 UserDefaults key（移自 ChartScene · 持久化在本 struct 内）
    fileprivate static let subChartHeightKey = "subChartHeight.v1"

    /// v13.23 viewport 键盘快捷键（仅 keyWindow 响应 · 多窗口隔离）
    /// ⌘= 放大 / ⌘- 缩小 / ⌘0 重置（默认 120 根） / ← 后退 5 / → 前进 5（带 ⇧ 键 25 根加速）
    private var viewportShortcuts: some View {
        Group {
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.zoomed(by: 0.7))
            }
            .keyboardShortcut("=", modifiers: [.command])
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.zoomed(by: 1.4))
            }
            .keyboardShortcut("-", modifiers: [.command])
            Button("") {
                inertiaTask?.cancel()
                viewport = RenderViewport(startIndex: max(0, bars.count - 120), visibleCount: 120)
            }
            .keyboardShortcut("0", modifiers: [.command])
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.pannedSmooth(byBars: -5))
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.pannedSmooth(byBars: 5))
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.pannedSmooth(byBars: -25))
            }
            .keyboardShortcut(.leftArrow, modifiers: [.shift])
            Button("") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.pannedSmooth(byBars: 25))
            }
            .keyboardShortcut(.rightArrow, modifiers: [.shift])
            // v13.30 ⌘⇧H 切换 HUD 显隐（截图前可隐藏）
            Button("") {
                showHUD.toggle()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// 主图区（K 线 + 网格 + 十字光标 + indicators + HUD · gesture 挂这里）
    var chartMainArea: some View {
        ZStack(alignment: .topLeading) {
            KLineMetalView(
                renderer: renderer,
                input: KLineRenderInput(bars: bars, indicators: indicators, viewport: viewport),
                clearColor: chartTheme.metalClearColor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 视觉迭代第 1 项：5×5 半透明网格 · 与右价格轴 / 底时间轴对齐
            KLineGridView()
            // 视觉迭代第 2 项：十字光标 + OHLC 浮窗 + 轴边价格/时间浮标（hover 跟随）
            KLineCrosshairView(
                bars: bars,
                viewport: viewport,
                priceRange: currentPriceRange,
                period: bars.first?.period ?? .minute15,
                tooltipBackground: chartTheme.hudBackground,
                tooltipPrimaryText: chartTheme.textPrimary,
                tooltipSecondaryText: chartTheme.textSecondary,
                crosshairLineColor: chartTheme.textSecondary.opacity(0.7)
            )
            // v13.0 WP-42 画线 overlay 渲染层（在十字光标上 · HUD 下）
            // v13.3 pendingDrawing 接 pendingDrawingPoint + hoverDataPoint 实时预览第二点（虚线）
            DrawingsOverlayView(
                bars: bars,
                viewport: viewport,
                priceRange: currentPriceRange,
                drawings: drawings,
                selectedIDs: selectedDrawingIDs,
                pendingDrawing: pendingPreviewDrawing,
                textDefaultColor: chartTheme.textPrimary
            )
            // v13.34 HUD 显示在 4 角之一（用户偏好 · UserDefaults 持久化）· 默认左上
            if showHUD {
                hudCornerOverlay
            }
            // v13.0 画线点击捕获层（仅 activeDrawingTool 非 nil 时启用 · 否则点击穿透到主图 gesture）
            if activeDrawingTool != nil {
                drawingClickCaptureLayer
            } else if !drawings.isEmpty {
                // v13.1 浏览模式 hit-test 层（点击 anchor ±15 像素阈值 selected）
                drawingHitTestLayer
            }
        }
        .overlay(alignment: .topTrailing) {
            // 视觉迭代第 6 项：顶部当前价大字号 + 涨跌（vs Sina 实时昨结算 preSettle · fallback visible 周期首根）
            priceTopBar
        }
        .overlay(alignment: .bottomTrailing) {
            // v13.6 选中画线 Inspector 浮窗（显示类型 / 起终点 / 文字 / 通道偏移）
            drawingInspector
        }
        .simultaneousGesture(panGesture)
        .simultaneousGesture(zoomGesture)
        .background(
            // v15.x · 监听 trackpad 双指上下推 / 鼠标滚轮 scrollWheel 事件 · 转 K 线缩放
            // .background 注入 NSView · 不影响 SwiftUI hit-testing（其他 gesture 仍正常）
            ScrollWheelCaptureView { dy in
                handleScrollWheelZoom(dy)
            }
        )
        .contextMenu {
            // v13.5 选中画线右键菜单（删除 / 编辑文字 / 取消选中）· v13.6 加复制
            drawingContextMenu
        }
    }

    /// v13.6 选中画线 Inspector 浮窗 · v13.9 多选适配（≥2 显示数量 / 1 显示详情）
    @ViewBuilder
    private var drawingInspector: some View {
        if selectedDrawingIDs.count >= 2 {
            // 多选模式：只显示数量 + 操作提示
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("已选 \(selectedDrawingIDs.count) 个画线")
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        selectedDrawingIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(chartTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
                Text("⌘D 全部复制 · Delete 全部删除 · 右键批量改色/线宽")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(chartTheme.textSecondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(chartTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(chartTheme.hudBackground)
            .cornerRadius(6)
            .padding(12)
        } else if let id = selectedDrawingIDs.first, let d = drawings.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(drawingTypeLabel(d.type))
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        selectedDrawingIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(chartTheme.textSecondary)
                    }
                    .buttonStyle(.borderless)
                }
                Text("起：bar \(d.startPoint.barIndex) · 价 \(formatPrice(d.startPoint.price))")
                    .foregroundColor(chartTheme.textSecondary)
                if let end = d.endPoint {
                    Text("终：bar \(end.barIndex) · 价 \(formatPrice(end.price))")
                        .foregroundColor(chartTheme.textSecondary)
                }
                if let text = d.text {
                    Text("文字：\(text)")
                        .foregroundColor(chartTheme.textSecondary)
                }
                if let offset = d.channelOffset {
                    Text("通道偏移：\(formatPrice(offset))")
                        .foregroundColor(chartTheme.textSecondary)
                }
                // v13.8 显示色 / 线宽 · v13.11 锁定 · v13.15 透明度
                HStack(spacing: 6) {
                    Text("色：\(d.strokeColorHex ?? "默认")")
                    Text("·")
                    Text("宽：\(String(format: "%.1f", d.strokeWidth ?? 1.5))")
                    if let op = d.strokeOpacity, op < 1.0 {
                        Text("·")
                        Text("透：\(String(format: "%.0f%%", op * 100))")
                    }
                    if d.locked {
                        Text("·")
                        Image(systemName: "lock.fill")
                        Text("已锁定")
                    }
                }
                .foregroundColor(chartTheme.textSecondary)
                Text(d.locked
                     ? "右键解锁后可拖动/删除"
                     : "⌘D 复制 · Delete 删除 · 拖动 anchor 改位置 · 右键编辑")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(chartTheme.textSecondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(chartTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(chartTheme.hudBackground)
            .cornerRadius(6)
            .padding(12)
        }
    }

    // v15.x · drawingTypeLabel 提到 file scope · ChartContentView 内调用直接用 file 顶部 fileprivate 函数

    private func formatPrice(_ p: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: p).doubleValue)
    }

    /// v13.5 画线右键上下文菜单 · v13.6 加复制 · v13.9 多选 · v13.8 改颜色/线宽 · v13.11 锁定/解锁
    @ViewBuilder
    private var drawingContextMenu: some View {
        if !selectedDrawingIDs.isEmpty {
            let n = selectedDrawingIDs.count
            let selected = drawings.filter { selectedDrawingIDs.contains($0.id) }
            let allLocked = selected.allSatisfy { $0.locked }
            let anyLocked = selected.contains { $0.locked }
            Button("删除选中画线（\(n) 个）", role: .destructive) {
                let deletableSet = Set(selected.filter { !$0.locked }.map(\.id))
                drawings.removeAll { deletableSet.contains($0.id) }
                selectedDrawingIDs.subtract(deletableSet)
            }
            .disabled(allLocked)
            Button("复制画线（⌘D · \(n) 个）") {
                let copies = selected.map { duplicatedDrawing($0) }
                drawings.append(contentsOf: copies)
                selectedDrawingIDs = Set(copies.map(\.id))
            }
            // 编辑文字仅当 selected 全部是单条 .text 类型时才有意义 · 锁定时禁用 · v13.12 加改字号
            if n == 1, let id = selectedDrawingIDs.first,
               let drawing = drawings.first(where: { $0.id == id }),
               drawing.type == .text {
                Button("编辑文字…") {
                    editTextDrawing(drawing)
                }
                .disabled(drawing.locked)
                Button("修改字号…") {
                    editFontSize(drawing)
                }
                .disabled(drawing.locked)
                // v13.26 文字加粗 / 斜体 toggle
                Button(drawing.isBold == true ? "取消加粗" : "加粗") {
                    if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
                        drawings[idx].isBold = (drawing.isBold == true) ? nil : true
                    }
                }
                .disabled(drawing.locked)
                Button(drawing.isItalic == true ? "取消斜体" : "斜体") {
                    if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
                        drawings[idx].isItalic = (drawing.isItalic == true) ? nil : true
                    }
                }
                .disabled(drawing.locked)
                Button(drawing.isUnderline == true ? "取消下划线" : "下划线") {
                    if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
                        drawings[idx].isUnderline = (drawing.isUnderline == true) ? nil : true
                    }
                }
                .disabled(drawing.locked)
            }
            // v13.18 水平线 → 一键创建价格触及预警（与 WP-52 AlertCore 联动）
            if n == 1, let id = selectedDrawingIDs.first,
               let drawing = drawings.first(where: { $0.id == id }),
               drawing.type == .horizontalLine {
                Button("为此画线创建预警…") {
                    createAlertForDrawing(drawing)
                }
                .disabled(drawing.locked)
            }
            Divider()
            // v13.11 锁定 / 解锁（互斥 · 全锁显示解锁 · 全未锁显示锁定 · 混合显示锁定全部）
            if allLocked {
                Button("解锁画线（\(n) 个）") {
                    setLocked(false, for: selectedDrawingIDs)
                }
            } else if anyLocked {
                Button("锁定全部（\(n) 个 · 含 \(selected.filter(\.locked).count) 已锁）") {
                    setLocked(true, for: selectedDrawingIDs)
                }
                Button("解锁全部（\(n) 个）") {
                    setLocked(false, for: selectedDrawingIDs)
                }
            } else {
                Button("锁定画线（\(n) 个）") {
                    setLocked(true, for: selectedDrawingIDs)
                }
            }
            Divider()
            // v13.8 应用工具栏当前颜色 / 线宽（批量改）· v13.11 锁定时禁用 · v13.15 同时应用透明度
            Button("应用当前颜色（\(n) 个）") {
                let hex = Self.hexString(from: currentStrokeColor)
                let alpha = Self.alphaComponent(from: currentStrokeColor)
                applyStrokeColor(hex, opacity: alpha, to: selectedDrawingIDs)
            }
            .disabled(allLocked)
            Button("应用当前线宽 \(String(format: "%.1f", currentStrokeWidth)) pt（\(n) 个）") {
                applyStrokeWidth(currentStrokeWidth, to: selectedDrawingIDs)
            }
            .disabled(allLocked)
            Button("恢复默认颜色/线宽（\(n) 个）") {
                resetStrokeStyle(for: selectedDrawingIDs)
            }
            .disabled(allLocked)
            Divider()
            Button("取消选中") {
                selectedDrawingIDs.removeAll()
            }
        } else {
            // v13.24 无选中画线 · 显示通用 chart 操作（重置缩放 / 复制可见区 CSV）
            Button("重置缩放（⌘0）") {
                inertiaTask?.cancel()
                viewport = RenderViewport(startIndex: max(0, bars.count - 120), visibleCount: 120)
            }
            Button("放大（⌘=）") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.zoomed(by: 0.7))
            }
            Button("缩小（⌘-）") {
                inertiaTask?.cancel()
                viewport = clamp(viewport.zoomed(by: 1.4))
            }
            Divider()
            Button("复制可见区 OHLC（CSV）") {
                copyVisibleBarsToCSV()
            }
            Button("导出主图截图（PNG）…") {
                exportChartScreenshot()
            }
            Button("复制主图截图到剪贴板") {
                copyChartScreenshotToClipboard()
            }
            Divider()
            // v13.34 HUD 位置切换（4 角）
            Menu("HUD 位置（当前：\(hudCorner.label)）") {
                ForEach(HUDCorner.allCases, id: \.rawValue) { corner in
                    Button(corner.label + (corner == hudCorner ? " ✓" : "")) {
                        hudCorner = corner
                    }
                }
            }
            Divider()
            Text("（按住 ⇧ 多选画线 · 右键画线弹更多操作）")
                .foregroundColor(chartTheme.textSecondary)
        }
    }

    /// v13.29 主图截图复制到剪贴板（不弹保存对话框 · 直接写 NSPasteboard）
    @MainActor
    private func copyChartScreenshotToClipboard() {
        let renderer = ImageRenderer(content: chartMainArea.frame(width: 1280, height: 720))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }

    /// v13.25 主图截图导出 PNG · ImageRenderer + NSSavePanel · macOS 13+
    @MainActor
    private func exportChartScreenshot() {
        let renderer = ImageRenderer(content: chartMainArea
            .frame(width: 1280, height: 720))
        renderer.scale = 2  // Retina 高清
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            let err = NSAlert()
            err.messageText = "截图失败"
            err.informativeText = "ImageRenderer 渲染未返回有效图片。"
            err.alertStyle = .warning
            err.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出主图截图"
        panel.allowedContentTypes = [.png]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "chart_\(instrumentLabel)_\(periodLabel)_\(dateFmt.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pngData.write(to: url)
    }

    /// v13.24 复制 viewport 可见区 K 线为 CSV 到 NSPasteboard
    private func copyVisibleBarsToCSV() {
        let endIdx = min(bars.count, viewport.startIndex + viewport.visibleCount)
        let startIdx = max(0, viewport.startIndex)
        guard startIdx < endIdx else { return }
        let slice = bars[startIdx..<endIdx]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"
        var lines: [String] = ["time,open,high,low,close,volume"]
        for bar in slice {
            let t = dateFmt.string(from: bar.openTime)
            let o = NSDecimalNumber(decimal: bar.open).stringValue
            let h = NSDecimalNumber(decimal: bar.high).stringValue
            let l = NSDecimalNumber(decimal: bar.low).stringValue
            let c = NSDecimalNumber(decimal: bar.close).stringValue
            lines.append("\(t),\(o),\(h),\(l),\(c),\(bar.volume)")
        }
        let csv = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(csv, forType: .string)
    }

    /// v13.11 批量改 isLocked
    private func setLocked(_ locked: Bool, for ids: Set<UUID>) {
        for i in drawings.indices where ids.contains(drawings[i].id) {
            drawings[i].isLocked = locked ? true : nil
        }
    }

    /// v13.8 批量改 strokeColorHex · v13.15 同时改 strokeOpacity（来自 ColorPicker alpha）
    private func applyStrokeColor(_ hex: String?, opacity: Double, to ids: Set<UUID>) {
        for i in drawings.indices where ids.contains(drawings[i].id) {
            drawings[i].strokeColorHex = hex
            drawings[i].strokeOpacity = opacity < 1.0 ? opacity : nil  // 1.0 视为默认 nil 节省字节
        }
    }

    /// v13.8 批量改 strokeWidth
    private func applyStrokeWidth(_ width: Double, to ids: Set<UUID>) {
        for i in drawings.indices where ids.contains(drawings[i].id) {
            drawings[i].strokeWidth = width
        }
    }

    /// v13.8 重置色 + 宽为 nil（用类型默认）· v13.15 同时重置 strokeOpacity
    private func resetStrokeStyle(for ids: Set<UUID>) {
        for i in drawings.indices where ids.contains(drawings[i].id) {
            drawings[i].strokeColorHex = nil
            drawings[i].strokeWidth = nil
            drawings[i].strokeOpacity = nil
        }
    }

    /// SwiftUI Color → 6 位 RGB hex（用 NSColor 桥）· 失败返回 nil（fallback 用类型默认）
    static func hexString(from color: Color) -> String? {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    /// v13.15 SwiftUI Color → alpha 通道 0~1 · 默认 1.0
    static func alphaComponent(from color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return Double(ns.alphaComponent)
    }

    /// v13.6 单条复制（兼容入口 · 内部走 duplicatedDrawing + append）· v13.9 多选时走 ⌘D shortcut 直接批量
    private func duplicateDrawing(_ drawing: Drawing) {
        let copy = duplicatedDrawing(drawing)
        drawings.append(copy)
        selectedDrawingIDs = [copy.id]
    }

    /// v13.6 克隆 helper · 偏移 20 bar / 价格区间 5%（避免完全重叠）· v13.8 复制色/线宽 · v13.9 多选用
    /// v13.11 副本不继承 isLocked · 让用户能立即拖动 / 删除新副本（防误改不应延续到副本）
    private func duplicatedDrawing(_ drawing: Drawing) -> Drawing {
        let barOffset = 20
        let priceSpan = currentPriceRange.upperBound - currentPriceRange.lowerBound
        let priceOffset = priceSpan * Decimal(string: "0.05")!
        let newStart = DrawingPoint(barIndex: drawing.startPoint.barIndex + barOffset, price: drawing.startPoint.price + priceOffset)
        let newEnd: DrawingPoint? = drawing.endPoint.map {
            DrawingPoint(barIndex: $0.barIndex + barOffset, price: $0.price + priceOffset)
        }
        // v13.17 extraPoints（Pitchfork 第 3 点等）也按相同 offset 平移 · 保持形状
        let newExtras: [DrawingPoint]? = drawing.extraPoints?.map {
            DrawingPoint(barIndex: $0.barIndex + barOffset, price: $0.price + priceOffset)
        }
        return Drawing(
            type: drawing.type,
            startPoint: newStart,
            endPoint: newEnd,
            text: drawing.text,
            channelOffset: drawing.channelOffset,
            strokeColorHex: drawing.strokeColorHex,
            strokeWidth: drawing.strokeWidth,
            isLocked: nil,
            fontSize: drawing.fontSize,
            strokeOpacity: drawing.strokeOpacity,
            extraPoints: newExtras,
            isBold: drawing.isBold,
            isItalic: drawing.isItalic,
            isUnderline: drawing.isUnderline
        )
    }

    /// v13.5 编辑文字画线内容（弹 NSAlert + NSTextField）
    private func editTextDrawing(_ drawing: Drawing) {
        guard drawing.type == .text else { return }
        let alert = NSAlert()
        alert.messageText = "编辑文字"
        alert.informativeText = "修改标注内容："
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = drawing.text ?? ""
        alert.accessoryView = textField
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let newText = textField.stringValue.isEmpty ? "标注" : textField.stringValue
            if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
                drawings[idx].text = newText
            }
        }
    }

    /// v13.18 为水平线画线创建价格触及预警（与 WP-52 AlertCore 联动 · 通过 NotificationCenter 通知 AlertWindow）
    private func createAlertForDrawing(_ drawing: Drawing) {
        guard drawing.type == .horizontalLine else { return }
        let price = drawing.startPoint.price
        let priceStr = formatPrice(price)
        let nsAlert = NSAlert()
        nsAlert.messageText = "为水平线创建预警"
        nsAlert.informativeText = "价格触及 \(priceStr) 时预警 · \(instrumentLabel)"
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = "\(instrumentLabel) 触及 \(priceStr)"
        nsAlert.accessoryView = textField
        nsAlert.addButton(withTitle: "创建")
        nsAlert.addButton(withTitle: "取消")
        if nsAlert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.isEmpty ? "水平线预警" : textField.stringValue
            let newAlert = Alert(
                name: name,
                instrumentID: instrumentLabel,
                condition: .horizontalLineTouched(drawingID: drawing.id, price: price)
            )
            // post 给 AlertWindow（自动 alerts.append → onChange save + evaluator sync）
            NotificationCenter.default.post(name: .alertAddedFromChart, object: newAlert)
            // 反馈提示
            let success = NSAlert()
            success.messageText = "预警已创建"
            success.informativeText = "在「预警」窗口可查看 / 编辑 / 暂停 / 删除。"
            success.addButton(withTitle: "好")
            success.runModal()
        }
    }

    /// v13.12 修改文字字号（NSAlert + NSTextField 输入数字 · 8~32 pt 范围 · 越界保留旧值）
    private func editFontSize(_ drawing: Drawing) {
        guard drawing.type == .text else { return }
        let alert = NSAlert()
        alert.messageText = "修改字号"
        alert.informativeText = "输入字号 pt（8~32）："
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        textField.stringValue = String(Int(drawing.fontSize ?? 12))
        alert.accessoryView = textField
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let raw = Double(textField.stringValue) ?? 12
            let clamped = max(8, min(32, raw))
            if let idx = drawings.firstIndex(where: { $0.id == drawing.id }) {
                drawings[idx].fontSize = clamped
            }
        }
    }

    /// 画线点击捕获层（v13.0 · 透明 contentShape · 拦截 onTapGesture · 仅工具激活时存在）
    /// v13.3 加 onContinuousHover 跟踪 · 双点画线第一点已设时实时预览第二点（虚线）
    private var drawingClickCaptureLayer: some View {
        GeometryReader { geom in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverDataPoint = screenToDataPoint(location, in: geom.size)
                    case .ended:
                        hoverDataPoint = nil
                    }
                }
                .onTapGesture { location in
                    handleDrawingTap(at: location, in: geom.size)
                }
        }
    }

    /// 画线 hit-test 层 · v13.1 单击选中 → v13.9 ⇧ 多选 → v13.10 拖动 anchor
    /// 用 DragGesture(minimumDistance: 0) 一手势包揽：
    /// - 起点击中 selected drawing 的 anchor → 拖动改 startPoint/endPoint
    /// - 释放距离 < 4 → 当 tap 处理（普通：单选替换 · ⇧：toggle 加选 / 取消选）
    private var drawingHitTestLayer: some View {
        GeometryReader { geom in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // 第一次 onChanged：探查起点是否击中已选画线的 anchor
                            if anchorDragTarget == nil && !isDraggingAnchor {
                                anchorDragTarget = findAnchorAt(value.startLocation, in: geom.size)
                                // 命中 anchor 时立即 cancel 主图惯性滑行（否则 viewport 会继续变 · anchor 漂移）
                                if anchorDragTarget != nil {
                                    inertiaTask?.cancel()
                                }
                            }
                            // 距离 ≥ 4 像素 + 起点击中 anchor → 进入拖动模式
                            let dist = hypot(value.translation.width, value.translation.height)
                            if dist >= 4, let target = anchorDragTarget {
                                isDraggingAnchor = true
                                let rawPoint = screenToDataPoint(value.location, in: geom.size)
                                // v13.32 snap to OHLC 价格（5 像素阈值 · 按 ⌥ 临时关闭吸附）
                                let snapped = NSEvent.modifierFlags.contains(.option)
                                    ? rawPoint
                                    : snapToOHLC(rawPoint, screenY: value.location.y, in: geom.size)
                                if let idx = drawings.firstIndex(where: { $0.id == target.drawingID }) {
                                    if let ei = target.extraIndex {
                                        // v13.33 extraPoints[i] 拖动（多边形 N 顶点 / Pitchfork C 点）
                                        if drawings[idx].extraPoints?.indices.contains(ei) == true {
                                            drawings[idx].extraPoints?[ei] = snapped
                                        }
                                    } else if target.isStart {
                                        drawings[idx].startPoint = snapped
                                    } else {
                                        drawings[idx].endPoint = snapped
                                    }
                                }
                            }
                        }
                        .onEnded { value in
                            let dist = hypot(value.translation.width, value.translation.height)
                            if !isDraggingAnchor && dist < 4 {
                                handleSelectionClick(at: value.startLocation, in: geom.size)
                            }
                            // 重置状态（允许下次拖动）
                            anchorDragTarget = nil
                            isDraggingAnchor = false
                        }
                )
        }
    }

    /// v13.10 起点击中已选 drawing 的 anchor 检测（±15 像素）· 仅 selected 的画线参与
    /// v13.11 锁定的画线跳过（不接受拖动）
    /// v13.33 支持 extraPoints[i] 拖动（多边形 N 顶点 / Pitchfork C 点）
    private func findAnchorAt(_ location: CGPoint, in size: CGSize) -> AnchorDragTarget? {
        guard !selectedDrawingIDs.isEmpty else { return nil }
        let threshold: CGFloat = 15
        for d in drawings.reversed() where selectedDrawingIDs.contains(d.id) && !d.locked {
            let s = anchorScreenPoint(d.startPoint, in: size)
            if hypot(location.x - s.x, location.y - s.y) < threshold {
                return AnchorDragTarget(drawingID: d.id, isStart: true)
            }
            if let end = d.endPoint {
                let e = anchorScreenPoint(end, in: size)
                if hypot(location.x - e.x, location.y - e.y) < threshold {
                    return AnchorDragTarget(drawingID: d.id, isStart: false)
                }
            }
            // v13.33 检查 extraPoints anchor（多边形顶点 / Pitchfork C）
            if let extras = d.extraPoints {
                for (i, p) in extras.enumerated() {
                    let ep = anchorScreenPoint(p, in: size)
                    if hypot(location.x - ep.x, location.y - ep.y) < threshold {
                        return AnchorDragTarget(drawingID: d.id, isStart: false, extraIndex: i)
                    }
                }
            }
        }
        return nil
    }

    /// v13.32 拖动 anchor 时 OHLC 价格吸附 · 5 像素阈值内最近的 K 线 OHLC 价格 → 自动 snap
    /// 实战场景：用户拖支撑/阻力线时自动对齐到关键 K 线高低点 · 提高画线精度
    /// 按 ⌥（option）键临时关闭吸附（自由模式）· 调用方判断
    private func snapToOHLC(_ rawPoint: DrawingPoint, screenY: CGFloat, in size: CGSize) -> DrawingPoint {
        let snapThreshold: CGFloat = 5
        // 仅检查 viewport 可见区 K 线（节约计算）· bars 空 / viewport 越界全部走 guard fallback
        let startIdx = max(0, min(bars.count, viewport.startIndex))
        let endIdx = min(bars.count, startIdx + max(0, viewport.visibleCount))
        guard startIdx < endIdx else { return rawPoint }
        let hi = NSDecimalNumber(decimal: currentPriceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: currentPriceRange.lowerBound).doubleValue
        let span = max(0.0001, hi - lo)
        var bestPrice = rawPoint.price
        var bestDist = snapThreshold
        for bar in bars[startIdx..<endIdx] {
            for candidate in [bar.open, bar.high, bar.low, bar.close] {
                let candidateD = NSDecimalNumber(decimal: candidate).doubleValue
                let candidateY = CGFloat((hi - candidateD) / span) * size.height
                let dist = abs(screenY - candidateY)
                if dist < bestDist {
                    bestDist = dist
                    bestPrice = candidate
                }
            }
        }
        return DrawingPoint(barIndex: rawPoint.barIndex, price: bestPrice)
    }

    /// 数据空间锚点 → 屏幕坐标（用 viewport + currentPriceRange · 与 distanceToDrawing 内实现一致）
    private func anchorScreenPoint(_ pt: DrawingPoint, in size: CGSize) -> CGPoint {
        let visibleCount = max(1, viewport.visibleCount)
        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)
        let hi = NSDecimalNumber(decimal: currentPriceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: currentPriceRange.lowerBound).doubleValue
        let span = max(0.0001, hi - lo)
        let x = (CGFloat(pt.barIndex - viewport.startIndex) + 0.5 - xOffset) * barWidth
        let priceD = NSDecimalNumber(decimal: pt.price).doubleValue
        let y = CGFloat((hi - priceD) / span) * size.height
        return CGPoint(x: x, y: y)
    }

    /// v13.9 选中点击处理 · 普通点击 = 单选替换 · ⇧ 点击 = toggle 加选 · 点空白 = 单击清空（⇧ 不动）
    private func handleSelectionClick(at location: CGPoint, in size: CGSize) {
        let isShift = NSEvent.modifierFlags.contains(.shift)
        if let id = findDrawingAt(location, in: size) {
            if isShift {
                if selectedDrawingIDs.contains(id) {
                    selectedDrawingIDs.remove(id)
                } else {
                    selectedDrawingIDs.insert(id)
                }
            } else {
                selectedDrawingIDs = [id]
            }
        } else if !isShift {
            selectedDrawingIDs.removeAll()
        }
    }

    /// 找点击位置最近的画线（v13.4 升级 · 点击线段任意位置 · 不只 anchor）
    /// 阈值 8 像素 · 6 种画线类型分别计算距离（线段 / 水平线 / 矩形 4 边 / 平行通道双轴 / fib 各档 / text 位置）
    private func findDrawingAt(_ location: CGPoint, in size: CGSize) -> UUID? {
        let threshold: CGFloat = 8
        var minDist: CGFloat = threshold
        var closestID: UUID?
        for d in drawings.reversed() {  // 最近画的在上层 · 优先选
            let dist = distanceToDrawing(location, drawing: d, in: size)
            if dist < minDist { minDist = dist; closestID = d.id }
        }
        return closestID
    }

    /// 屏幕点到画线的最近距离（按 type 分发计算）
    private func distanceToDrawing(_ p: CGPoint, drawing: Drawing, in size: CGSize) -> CGFloat {
        let visibleCount = max(1, viewport.visibleCount)
        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)
        let hi = NSDecimalNumber(decimal: currentPriceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: currentPriceRange.lowerBound).doubleValue
        let span = max(0.0001, hi - lo)
        func screenPoint(_ pt: DrawingPoint) -> CGPoint {
            let x = (CGFloat(pt.barIndex - viewport.startIndex) + 0.5 - xOffset) * barWidth
            let priceD = NSDecimalNumber(decimal: pt.price).doubleValue
            let y = CGFloat((hi - priceD) / span) * size.height
            return CGPoint(x: x, y: y)
        }

        switch drawing.type {
        case .trendLine:
            guard let end = drawing.endPoint else { return .infinity }
            return Self.pointToSegmentDistance(p, screenPoint(drawing.startPoint), screenPoint(end))

        case .horizontalLine:
            let y = screenPoint(drawing.startPoint).y
            return abs(p.y - y)

        case .rectangle:
            guard let end = drawing.endPoint else { return .infinity }
            let s = screenPoint(drawing.startPoint)
            let e = screenPoint(end)
            let xMin = min(s.x, e.x), xMax = max(s.x, e.x)
            let yMin = min(s.y, e.y), yMax = max(s.y, e.y)
            let topLeft = CGPoint(x: xMin, y: yMin)
            let topRight = CGPoint(x: xMax, y: yMin)
            let botLeft = CGPoint(x: xMin, y: yMax)
            let botRight = CGPoint(x: xMax, y: yMax)
            return min(
                Self.pointToSegmentDistance(p, topLeft, topRight),
                Self.pointToSegmentDistance(p, botLeft, botRight),
                Self.pointToSegmentDistance(p, topLeft, botLeft),
                Self.pointToSegmentDistance(p, topRight, botRight)
            )

        case .parallelChannel:
            guard let end = drawing.endPoint, let offset = drawing.channelOffset else { return .infinity }
            let s = screenPoint(drawing.startPoint)
            let e = screenPoint(end)
            let main = Self.pointToSegmentDistance(p, s, e)
            let offsetStart = screenPoint(DrawingPoint(barIndex: drawing.startPoint.barIndex, price: drawing.startPoint.price + offset))
            let offsetEnd = screenPoint(DrawingPoint(barIndex: end.barIndex, price: end.price + offset))
            let secondary = Self.pointToSegmentDistance(p, offsetStart, offsetEnd)
            return min(main, secondary)

        case .fibonacci:
            guard drawing.endPoint != nil else { return .infinity }
            let prices = DrawingGeometry.fibonacciPrices(for: drawing)
            var minD: CGFloat = .infinity
            for price in prices {
                let y = screenPoint(DrawingPoint(barIndex: drawing.startPoint.barIndex, price: price)).y
                minD = min(minD, abs(p.y - y))
            }
            return minD

        case .text:
            let pt = screenPoint(drawing.startPoint)
            return hypot(p.x - pt.x, p.y - pt.y)

        case .ellipse:
            // v13.13 椭圆 · 点 (px, py) 到椭圆周距离 ≈ |√((px-cx)²/a² + (py-cy)²/b²) - 1| × min(a, b)
            // 缺陷：在长短轴差异大时不严格 · 但够用（阈值 8 像素 + 用户实测可接受）
            guard let end = drawing.endPoint else { return .infinity }
            let s = screenPoint(drawing.startPoint)
            let e = screenPoint(end)
            let cx = (s.x + e.x) / 2
            let cy = (s.y + e.y) / 2
            let a = abs(e.x - s.x) / 2
            let b = abs(e.y - s.y) / 2
            guard a > 0, b > 0 else { return .infinity }
            let nx = (p.x - cx) / a
            let ny = (p.y - cy) / b
            let r = sqrt(nx * nx + ny * ny)
            return abs(r - 1) * min(a, b)

        case .ruler:
            // v13.14 测量工具 · 同 trendLine（点到线段距离）
            guard let end = drawing.endPoint else { return .infinity }
            return Self.pointToSegmentDistance(p, screenPoint(drawing.startPoint), screenPoint(end))

        case .polygon:
            // v13.31 多边形 · 取所有边的最小距离（闭合 N 点 · 包括首尾连接边）
            guard let extras = drawing.extraPoints, !extras.isEmpty else { return .infinity }
            let allPoints = [drawing.startPoint] + extras
            let screenPts = allPoints.map { screenPoint($0) }
            var minDist: CGFloat = .infinity
            for i in 0..<screenPts.count {
                let a = screenPts[i]
                let b = screenPts[(i + 1) % screenPts.count]
                minDist = min(minDist, Self.pointToSegmentDistance(p, a, b))
            }
            return minDist

        case .pitchfork:
            // v13.17 3 条线段距离最小（中线 / 上轨 / 下轨 · 与 DrawingsOverlayView 渲染共用同一 t · 保证 hit-test = 可见范围）
            guard let upper = drawing.endPoint,
                  let extras = drawing.extraPoints, let lower = extras.first else { return .infinity }
            let a = screenPoint(drawing.startPoint)
            let b = screenPoint(upper)
            let c = screenPoint(lower)
            let mid = CGPoint(x: (b.x + c.x) / 2, y: (b.y + c.y) / 2)
            let dx = mid.x - a.x
            let dy = mid.y - a.y
            guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return .infinity }
            let t = DrawingsOverlayView.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
            let centerEnd = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            let upperEnd = CGPoint(x: b.x + t * dx, y: b.y + t * dy)
            let lowerEnd = CGPoint(x: c.x + t * dx, y: c.y + t * dy)
            return min(
                Self.pointToSegmentDistance(p, a, centerEnd),
                Self.pointToSegmentDistance(p, b, upperEnd),
                Self.pointToSegmentDistance(p, c, lowerEnd)
            )
        }
    }

    /// 点到线段的最近距离（投影夹钳到 [0,1] 区间）
    private static func pointToSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 0.0001 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    /// v13.3 双点画线第二点 hover 实时预览 · pendingDrawingPoint + hoverDataPoint → 虚线 Drawing
    /// v13.17 Pitchfork phase 2 预览（A + B 已设 · 第 3 点 hover 完整 3 线显示）
    private var pendingPreviewDrawing: Drawing? {
        guard let firstPoint = pendingDrawingPoint,
              let hoverPoint = hoverDataPoint,
              let tool = activeDrawingTool,
              tool.pointsNeeded > 1 else { return nil }
        switch tool {
        case .parallelChannel:
            let offset = (currentPriceRange.upperBound - currentPriceRange.lowerBound) * Decimal(string: "0.05")!
            return Drawing.parallelChannel(from: firstPoint, to: hoverPoint, offset: offset)
        case .fibonacci:
            return Drawing.fibonacci(from: firstPoint, to: hoverPoint)
        case .rectangle:
            return Drawing.rectangle(from: firstPoint, to: hoverPoint)
        case .trendLine:
            return Drawing.trendLine(from: firstPoint, to: hoverPoint)
        case .ellipse:
            return Drawing.ellipse(from: firstPoint, to: hoverPoint)
        case .ruler:
            return Drawing.ruler(from: firstPoint, to: hoverPoint)
        case .pitchfork:
            // phase 1（B 未设）不预览 · phase 2（B 已设）显示完整 pitchfork
            guard !pendingExtraPoints.isEmpty else { return nil }
            return Drawing.pitchfork(handle: firstPoint, upper: pendingExtraPoints[0], lower: hoverPoint)
        case .polygon:
            // v13.31 实时预览：起点 + 已点 extraPoints + hover 当前位置 → 闭合多边形虚线
            let extrasWithHover = pendingExtraPoints + [hoverPoint]
            return Drawing(type: .polygon, startPoint: firstPoint, extraPoints: extrasWithHover)
        default:
            return nil
        }
    }

    /// 屏幕坐标 → 数据空间锚点（barIndex + price）
    private func screenToDataPoint(_ location: CGPoint, in size: CGSize) -> DrawingPoint {
        let visibleCount = max(1, viewport.visibleCount)
        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)
        let barIndex = viewport.startIndex + Int((location.x / barWidth) + xOffset)
        let hi = NSDecimalNumber(decimal: currentPriceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: currentPriceRange.lowerBound).doubleValue
        let span = max(0.0001, hi - lo)
        let priceRatio = (size.height - location.y) / size.height
        let price = lo + Double(priceRatio) * span
        return DrawingPoint(barIndex: barIndex, price: Decimal(price))
    }

    /// 处理画线工具激活下的点击：单点画线立即添加 / 双点画线第 1 点设 pending 第 2 点完成
    /// v13.8 新建画线时应用工具栏当前颜色 / 线宽（currentStrokeColor + currentStrokeWidth）
    /// v13.17 Pitchfork 走 3 点路径（独立分发）
    private func handleDrawingTap(at location: CGPoint, in size: CGSize) {
        guard let tool = activeDrawingTool else { return }
        let point = screenToDataPoint(location, in: size)

        // v13.17 Pitchfork 单独 3 点输入
        if tool == .pitchfork {
            handlePitchforkTap(point)
            return
        }

        // v13.31 多边形动态点输入 · 第 1 点 → pendingDrawingPoint · 后续 → pendingExtraPoints append · 工具栏"完成"触发闭合
        if tool == .polygon {
            if pendingDrawingPoint == nil {
                pendingDrawingPoint = point
            } else {
                pendingExtraPoints.append(point)
            }
            return
        }

        if tool.needsTwoPoints {
            if let firstPoint = pendingDrawingPoint {
                // 第二点：完成画线
                let endPoint: DrawingPoint? = point
                let channelOffset: Decimal? = (tool == .parallelChannel)
                    ? (currentPriceRange.upperBound - currentPriceRange.lowerBound) * Decimal(string: "0.05")!
                    : nil
                let drawing = Drawing(
                    type: tool,
                    startPoint: firstPoint,
                    endPoint: endPoint,
                    channelOffset: channelOffset,
                    strokeColorHex: Self.hexString(from: currentStrokeColor),
                    strokeWidth: currentStrokeWidth,
                    strokeOpacity: Self.alphaComponent(from: currentStrokeColor)
                )
                drawings.append(drawing)
                pendingDrawingPoint = nil
                activeDrawingTool = nil  // 完成后回浏览模式
            } else {
                // 第一点：记 pending（第二点击时使用）
                pendingDrawingPoint = point
            }
        } else {
            // 单点画线：立即完成
            if tool == .horizontalLine {
                let drawing = Drawing(
                    type: .horizontalLine,
                    startPoint: point,
                    strokeColorHex: Self.hexString(from: currentStrokeColor),
                    strokeWidth: currentStrokeWidth,
                    strokeOpacity: Self.alphaComponent(from: currentStrokeColor)
                )
                drawings.append(drawing)
                activeDrawingTool = nil
            } else if tool == .text {
                // v13.1 弹 NSAlert 让用户输入文字（之前 v13.0 hardcode "标注"）
                promptTextInput(at: point)
            } else {
                let drawing = Drawing(
                    type: tool,
                    startPoint: point,
                    strokeColorHex: Self.hexString(from: currentStrokeColor),
                    strokeWidth: currentStrokeWidth,
                    strokeOpacity: Self.alphaComponent(from: currentStrokeColor)
                )
                drawings.append(drawing)
                activeDrawingTool = nil
            }
        }
    }

    /// v13.17 Pitchfork 3 点输入：A handle / B upper / C lower → 完成
    private func handlePitchforkTap(_ point: DrawingPoint) {
        if pendingDrawingPoint == nil {
            pendingDrawingPoint = point  // A
        } else if pendingExtraPoints.isEmpty {
            pendingExtraPoints = [point]  // B
        } else {
            // C → 完成
            let drawing = Drawing(
                type: .pitchfork,
                startPoint: pendingDrawingPoint!,
                endPoint: pendingExtraPoints[0],
                strokeColorHex: Self.hexString(from: currentStrokeColor),
                strokeWidth: currentStrokeWidth,
                strokeOpacity: Self.alphaComponent(from: currentStrokeColor),
                extraPoints: [point]
            )
            drawings.append(drawing)
            pendingDrawingPoint = nil
            pendingExtraPoints = []
            activeDrawingTool = nil
        }
    }

    /// v13.1 文字标注输入 · NSAlert + NSTextField · 取消则不添加
    /// v13.8 应用工具栏当前色 / 线宽
    private func promptTextInput(at point: DrawingPoint) {
        let alert = NSAlert()
        alert.messageText = "文字标注"
        alert.informativeText = "输入要在主图标注的文字："
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = "标注"
        alert.accessoryView = textField
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let raw = textField.stringValue
            let text = raw.isEmpty ? "标注" : raw
            let drawing = Drawing(
                type: .text,
                startPoint: point,
                text: text,
                strokeColorHex: Self.hexString(from: currentStrokeColor),
                strokeWidth: currentStrokeWidth,
                fontSize: currentFontSize,
                strokeOpacity: Self.alphaComponent(from: currentStrokeColor)
            )
            drawings.append(drawing)
        }
        activeDrawingTool = nil
    }

    /// 顶部当前价大字号 + 涨跌幅 · 红涨绿跌 · baseline 用 Sina 实时昨结算 preSettle · fallback visible 周期首根
    /// v15.16 hotfix #10：用户开 HUD .change 时隐藏右侧涨跌副栏（避免与 HUD 视觉重复）· 大字号保留 + 染色保留
    private var priceTopBar: some View {
        HStack(spacing: 10) {
            if let last = bars.last, let first = bars.first {
                let close = NSDecimalNumber(decimal: last.close).doubleValue
                let baselineDecimal = preSettle ?? first.close
                let baseline = NSDecimalNumber(decimal: baselineDecimal).doubleValue
                let diff = close - baseline
                let pct = baseline > 0 ? diff / baseline * 100 : 0
                let isUp = diff >= 0
                let color: Color = isUp ? chartTheme.candleBull : chartTheme.candleBear
                Text(String(format: "%.2f", close))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                if !hudFields.fields.contains(.change) {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(chartTheme.hudBackground)
        .cornerRadius(6)
        .padding(12)
    }

    /// 拖拽平移 + 松手惯性滑行
    /// v13.10 · 起点击中 anchor（anchorDragTarget != nil）时短路 onChanged ·
    /// onEnded 通过 dragStartViewport == nil 判定 pan 是否实际跑过（避免触发误惯性）
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if anchorDragTarget != nil { return }
                inertiaTask?.cancel()
                let base = dragStartViewport ?? viewport
                dragStartViewport = base
                let perBar = Self.assumedViewWidth / CGFloat(max(1, base.visibleCount))
                let deltaBars = Float(-value.translation.width / perBar)
                viewport = clamp(base.pannedSmooth(byBars: deltaBars))
            }
            .onEnded { value in
                let didPan = (dragStartViewport != nil)
                dragStartViewport = nil
                guard didPan else { return }
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

    /// v15.x · trackpad 双指上下推（= scrollWheel 事件）→ K 线缩放
    /// 双指上推 / 鼠标滚轮上 → deltaY > 0 → 放大（visibleCount 减小 · 看更少根更细节）
    /// 双指下拉 / 鼠标滚轮下 → deltaY < 0 → 缩小（visibleCount 增大 · 看更多根全貌）
    /// 系数 0.01：trackpad 单次 deltaY ≈ 5-30 · 折算 5%~30% 缩放 · 平滑跟手
    fileprivate func handleScrollWheelZoom(_ deltaY: CGFloat) {
        inertiaTask?.cancel()
        let factor = 1.0 - Double(deltaY) * 0.01
        // factor 限幅 [0.5, 2.0] 防单次极端值（罕见 momentum spike）
        let clampedFactor = max(0.5, min(2.0, factor))
        viewport = clamp(viewport.zoomed(by: clampedFactor))
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

    /// v13.34 HUD 用 frame(maxWidth/Height: .infinity, alignment: hudCorner.alignment) 在 ZStack 内贴 4 角之一
    var hudCornerOverlay: some View {
        hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hudCorner.alignment)
    }

    var hud: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 主标识行：合约 + 周期 + 数据源（核心信息 · 醒目 · 始终显示不可关）
            Text("\(instrumentLabel) · \(periodLabel) · \(dataSourceLabel)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(chartTheme.textPrimary)
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
            // v15.14 自定义字段（按 hudFields 渲染 · 用户主动选才显 · 取 visible 末位 K 线）
            if let lastBar = visibleLastBar {
                if hudFields.fields.contains(.timestamp) {
                    Text("时间 \(formatBarTime(lastBar))")
                }
                if hudFields.fields.contains(.ohlc) {
                    Text("O \(fmt(lastBar.open))  H \(fmt(lastBar.high))  L \(fmt(lastBar.low))  C \(fmt(lastBar.close))")
                }
                if hudFields.fields.contains(.change) {
                    let baseline = preSettle ?? bars.first?.close ?? lastBar.close
                    let diff = lastBar.close - baseline
                    let pct = baseline != 0 ? (NSDecimalNumber(decimal: diff).doubleValue / NSDecimalNumber(decimal: baseline).doubleValue * 100) : 0
                    Text("涨跌 \(fmt(diff)) (\(String(format: "%+.2f%%", pct)))")
                        .foregroundColor(diff >= 0 ? chartTheme.candleBull : chartTheme.candleBear)
                }
                if hudFields.fields.contains(.volume) {
                    Text("量 \(lastBar.volume)")
                }
                if hudFields.fields.contains(.openInterest) {
                    Text("持仓 \(fmt(lastBar.openInterest))")
                }
            }
            // 视觉迭代第 4 项：调试信息（视野/帧时）· v15.14 用户可关 · 默认开
            if hudFields.fields.contains(.debug) {
                Text("可见 \(viewport.visibleCount) · 起点 \(viewport.startIndex)/\(bars.count) · 帧 \(String(format: "%.1f", lastFrameMs))ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(chartTheme.textSecondary)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(chartTheme.textPrimary)
        .padding(8)
        .background(chartTheme.hudBackground)
        .cornerRadius(6)
        .padding(12)
    }

    /// v15.14 visible window 末位 K 线（HUD 自定义字段所有"最新"语义都基于此 · 与画面对齐）
    private var visibleLastBar: KLine? {
        let end = min(viewport.startIndex + viewport.visibleCount, bars.count) - 1
        guard end >= 0, end < bars.count else { return nil }
        return bars[end]
    }

    /// v15.14 价格 / OI 数字格式（保 2 位小数）
    private func fmt(_ d: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: d).doubleValue)
    }

    /// v15.14 K 线时间戳格式（按 period 跨度选不同格式 · 与 KLineCrosshairView 风格对齐）
    /// v15.16 hotfix #10：加 zh_CN locale + Asia/Shanghai timeZone（与 KLineCrosshairView 一致 · 防跨时区偏移）
    private func formatBarTime(_ bar: KLine) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        switch bar.period {
        case .second1, .second3, .second5, .second10, .second15, .second30:
            formatter.dateFormat = "MM-dd HH:mm:ss"
        case .minute1, .minute3, .minute5, .minute15:
            formatter.dateFormat = "MM-dd HH:mm"
        case .minute30, .hour1, .hour2, .hour4:
            formatter.dateFormat = "yy-MM-dd HH:mm"
        case .daily, .weekly:
            formatter.dateFormat = "yyyy-MM-dd"
        case .monthly:
            formatter.dateFormat = "yyyy-MM"
        }
        return formatter.string(from: bar.openTime)
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
    /// N 条 MA 的增量 state（按 params.mainMAPeriods 顺序 · 默认 [5, 20, 60] = 3 条）
    var maStates: [MA.IncrementalState]
    var boll: BOLL.IncrementalState
    private(set) var series: [IndicatorSeries]   // 与 ChartScene.indicators 同步快照

    /// 用 history + params 初始化全部 state 与 series（与 MockKLineData.computeIndicators 完全一致）
    static func prime(bars: [KLine], params: IndicatorParamsBook = .default) -> ChartIndicatorRunner? {
        let kline = makeKLineSeries(from: bars)
        var maStates: [MA.IncrementalState] = []
        for p in params.mainMAPeriodsDecimal {
            guard let s = try? MA.makeIncrementalState(kline: kline, params: p) else { return nil }
            maStates.append(s)
        }
        guard let bollState = try? BOLL.makeIncrementalState(kline: kline, params: params.mainBOLLParamsDecimal) else {
            return nil
        }
        let series = MockKLineData.computeIndicators(bars: bars, params: params)
        return ChartIndicatorRunner(maStates: maStates, boll: bollState, series: series)
    }

    /// 推进 1 根新 K · 返回更新后的 series（顺序：N 条 MA + BOLL-UPPER + BOLL-LOWER · 与 computeIndicators 输出一致）
    mutating func step(newBar: KLine) -> [IndicatorSeries] {
        var appended: [Decimal?] = []
        for i in maStates.indices {
            appended.append(MA.stepIncremental(state: &maStates[i], newBar: newBar)[0])
        }
        let bollVals = BOLL.stepIncremental(state: &boll, newBar: newBar)   // [MID, UPPER, LOWER]
        appended.append(bollVals[1])
        appended.append(bollVals[2])
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

    /// 5 条不重合：3 条 MA（params.mainMAPeriods · 默认 5/20/60）+ BOLL UPPER + BOLL LOWER（过滤 BOLL-MID 与 MA(20) 重合）
    static func computeIndicators(bars: [KLine], params: IndicatorParamsBook = .default) -> [IndicatorSeries] {
        let series = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        let maSeries: [IndicatorSeries] = params.mainMAPeriodsDecimal.flatMap { p in
            (try? MA.calculate(kline: series, params: p)) ?? []
        }
        let boll = (try? BOLL.calculate(kline: series, params: params.mainBOLLParamsDecimal)) ?? []
        let bollBands = boll.filter { $0.name != "BOLL-MID" }
        return maSeries + bollBands
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
