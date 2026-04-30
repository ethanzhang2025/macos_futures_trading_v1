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

    private static let drawingTemplatesKey = "drawingTemplates.v1"

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
            // v13.0 WP-42 画线状态切合约/周期重载 · 各 (instrumentID, period) 组合独立持久化
            // v13.2 升级 UserDefaults JSON → SQLiteDrawingStore（M5 持久化 8/8）
            isDrawingsLoaded = false
            if let store = storeManager?.drawings {
                drawings = (try? await store.load(instrumentID: currentInstrumentID, period: selectedPeriod)) ?? []
            } else {
                drawings = []
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
            guard isDrawingsLoaded, let store = storeManager?.drawings else { return }
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
        }
        .onChange(of: drawingTemplates) { newValue in
            // v13.16 模板持久化 UserDefaults · 加载守卫避免初始 [] 误覆盖
            guard isTemplatesLoaded else { return }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.drawingTemplatesKey)
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
            drawingToolButton(icon: "textformat", tool: .text, help: "文字标注（一点）")
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
                    Button("\(template.name) · \(Self.drawingTypeLabel(template.drawing.type))") {
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

    /// v13.16 保存选中画线为模板 · NSAlert 输入名称
    private func saveCurrentAsTemplate(_ drawing: Drawing) {
        let alert = NSAlert()
        alert.messageText = "保存为模板"
        alert.informativeText = "输入模板名称（已存 \(drawingTemplates.count) 个）："
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        let typeName = Self.drawingTypeLabel(drawing.type)
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

            Spacer()
            Text("⌘N 新窗口 · ⌘L 自选")
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
                subIndicatorKinds: Array(selectedSubIndicators).sorted(by: { $0.rawValue < $1.rawValue }),
                preSettle: preSettle,
                drawings: $drawings,
                activeDrawingTool: $activeDrawingTool,
                pendingDrawingPoint: $pendingDrawingPoint,
                selectedDrawingIDs: $selectedDrawingIDs,
                currentStrokeColor: $currentStrokeColor,
                currentStrokeWidth: $currentStrokeWidth,
                currentFontSize: $currentFontSize,
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
    let subIndicatorKinds: [SubIndicatorKind]  // v13.19 多副图（vertical stack · 至少 1 个）
    /// v12.1 真昨结算 · priceTopBar baseline · nil 时 fallback bars.first.close（由 ChartScene 父级注入）
    let preSettle: Decimal?
    /// v13.0 WP-42 画线状态（绑定 ChartScene · 父子双向同步）
    @Binding var drawings: [Drawing]
    @Binding var activeDrawingTool: DrawingType?
    @Binding var pendingDrawingPoint: DrawingPoint?
    /// v13.9 多选 · selected 集合（替换 v13.0 单 UUID? · ⇧ 加选 + 批量删/复制）
    @Binding var selectedDrawingIDs: Set<UUID>
    /// v13.8 工具栏当前颜色 · 新建画线应用 · 右键"应用当前颜色"批量改已有
    @Binding var currentStrokeColor: Color
    /// v13.8 工具栏当前线宽 · 同上
    @Binding var currentStrokeWidth: Double
    /// v13.12 工具栏当前字号 · 新建文字标注应用（仅 .text 工具激活时显示 Stepper）
    @Binding var currentFontSize: Double
    /// v13.3 hover 跟踪 · 双点画线第二点 hover 预览（虚线）
    @State var hoverDataPoint: DrawingPoint?
    /// v13.20 副图区总高度 · 用户拖分割条调整 · 范围 80~480pt（默认 160 = subChartHeight 单副图）
    @State var subChartTotalHeight: CGFloat = SubChart.defaultHeight
    /// v13.20 拖分割条时的起始高度 · onChanged 累加 translation 算新高度
    @State var dragStartSubHeight: CGFloat?
    /// v13.10 anchor 拖动目标 · onChanged 第一次落 · 释放清空
    @State var anchorDragTarget: AnchorDragTarget?
    /// v13.10 拖动状态 · 距离 ≥ 4 像素 + anchor 命中后置 true · 释放时 false 视为 tap
    @State var isDraggingAnchor: Bool = false
    @State var viewport: RenderViewport
    @State var lastFrameMs: Double = 0
    @State var dragStartViewport: RenderViewport?
    @State var zoomStartViewport: RenderViewport?
    @State var inertiaTask: Task<Void, Never>?

    /// v13.10 拖动目标 · 唯一定位某 drawing 的某 anchor（startPoint vs endPoint）
    struct AnchorDragTarget: Equatable {
        let drawingID: UUID
        let isStart: Bool
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
        drawings: Binding<[Drawing]>,
        activeDrawingTool: Binding<DrawingType?>,
        pendingDrawingPoint: Binding<DrawingPoint?>,
        selectedDrawingIDs: Binding<Set<UUID>>,
        currentStrokeColor: Binding<Color>,
        currentStrokeWidth: Binding<Double>,
        currentFontSize: Binding<Double>,
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
        self._drawings = drawings
        self._activeDrawingTool = activeDrawingTool
        self._pendingDrawingPoint = pendingDrawingPoint
        self._selectedDrawingIDs = selectedDrawingIDs
        self._currentStrokeColor = currentStrokeColor
        self._currentStrokeWidth = currentStrokeWidth
        self._currentFontSize = currentFontSize
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
    private var mainSubDivider: some View {
        Color.white.opacity(0.18)
            .frame(height: 4)
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
                KLineAxisView(bars: bars, viewport: viewport, priceRange: currentPriceRange, orientation: .price)
                    .frame(width: 60)
            }
            // 视觉迭代第 9 项：主图 ↔ 副图分割线 · v13.20 升级为可拖分割条（4pt 高度 · 鼠标 hover 显示 row cursor · 拖动改副图总高度）
            mainSubDivider
            // 副图区 v13.19 多副图 vertical stack · 共享主图 viewport · 总高度 v13.20 用户可拖
            // 副图之间用 1pt 分割线 · 每个副图右侧占位 60pt 与主图价格轴对齐
            let count = max(1, subIndicatorKinds.count)
            let perSubHeight: CGFloat = subChartTotalHeight / CGFloat(count)
            VStack(spacing: 0) {
                ForEach(Array(subIndicatorKinds.enumerated()), id: \.element) { idx, kind in
                    if idx > 0 {
                        Color.white.opacity(0.10).frame(height: 1)
                    }
                    HStack(spacing: 0) {
                        SubChartView(bars: bars, viewport: viewport, kind: kind)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Color(red: 0.07, green: 0.08, blue: 0.10)
                            .frame(width: 60)
                    }
                    .frame(height: perSubHeight)
                }
            }
            .frame(height: subChartTotalHeight)
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
            // v13.0 WP-42 画线 overlay 渲染层（在十字光标上 · HUD 下）
            // v13.3 pendingDrawing 接 pendingDrawingPoint + hoverDataPoint 实时预览第二点（虚线）
            DrawingsOverlayView(
                bars: bars,
                viewport: viewport,
                priceRange: currentPriceRange,
                drawings: drawings,
                selectedIDs: selectedDrawingIDs,
                pendingDrawing: pendingPreviewDrawing
            )
            hud
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
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Text("⌘D 全部复制 · Delete 全部删除 · 右键批量改色/线宽")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65))
            .cornerRadius(6)
            .padding(12)
        } else if let id = selectedDrawingIDs.first, let d = drawings.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(Self.drawingTypeLabel(d.type))
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        selectedDrawingIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Text("起：bar \(d.startPoint.barIndex) · 价 \(formatPrice(d.startPoint.price))")
                    .foregroundColor(.secondary)
                if let end = d.endPoint {
                    Text("终：bar \(end.barIndex) · 价 \(formatPrice(end.price))")
                        .foregroundColor(.secondary)
                }
                if let text = d.text {
                    Text("文字：\(text)")
                        .foregroundColor(.secondary)
                }
                if let offset = d.channelOffset {
                    Text("通道偏移：\(formatPrice(offset))")
                        .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
                Text(d.locked
                     ? "右键解锁后可拖动/删除"
                     : "⌘D 复制 · Delete 删除 · 拖动 anchor 改位置 · 右键编辑")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65))
            .cornerRadius(6)
            .padding(12)
        }
    }

    private static func drawingTypeLabel(_ type: DrawingType) -> String {
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
        }
    }

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
            Text("（无选中画线 · 点击画线选中后再右键 · 按住 ⇧ 多选）")
                .foregroundColor(.secondary)
        }
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
            extraPoints: newExtras
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
        nsAlert.informativeText = "价格触及 \(priceStr) 时预警 · \(currentInstrumentID)"
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = "\(currentInstrumentID) 触及 \(priceStr)"
        nsAlert.accessoryView = textField
        nsAlert.addButton(withTitle: "创建")
        nsAlert.addButton(withTitle: "取消")
        if nsAlert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.isEmpty ? "水平线预警" : textField.stringValue
            let newAlert = Alert(
                name: name,
                instrumentID: currentInstrumentID,
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
                                let newPoint = screenToDataPoint(value.location, in: geom.size)
                                if let idx = drawings.firstIndex(where: { $0.id == target.drawingID }) {
                                    if target.isStart {
                                        drawings[idx].startPoint = newPoint
                                    } else {
                                        drawings[idx].endPoint = newPoint
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
    /// v13.17 v1 仅支持 startPoint / endPoint 拖动 · extraPoints 暂不支持拖（未来扩展 · backlog）
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
        }
        return nil
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
                extraPoints: [point],
                strokeColorHex: Self.hexString(from: currentStrokeColor),
                strokeWidth: currentStrokeWidth,
                strokeOpacity: Self.alphaComponent(from: currentStrokeColor)
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
