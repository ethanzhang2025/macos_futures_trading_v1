// WP-44 v15.23 batch50 · 多窗口图表 host 窗口（grid preset 渲染框架 · stub cells）
//
// 入口：⌘⌥M · 文件菜单"多图表"
//
// 布局：
// - 顶部 toolbar：grid preset Picker（1×1 / 1×2 / 2×1 / 2×2 / 2×3 / 3×2）+ cell 数指示
// - 主体：GeometryReader + WindowGridPreset.layout 渲染 N 个 cell（先 stub Color view）
// - 后续 batch51 把 stub 替换为简化 K 线 mini-view · batch52 加每 cell toolbar + 持久化
//
// 设计要点：
// - 仅 macOS · 不动 ChartScene 4558 行 · 完全独立的多图表入口
// - 数据持久化用 @AppStorage（preset + cells JSON · 跨会话恢复）
// - cell id 稳定 · ForEach 用 \.id 不重建 view（性能 + 状态保留）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Shared

struct MultiChartHost: View {

    @Environment(\.openWindow) private var openWindow

    // MARK: - 持久化状态

    @AppStorage("viewState.v1.multiChart.preset") private var presetRaw: String = WindowGridPreset.grid2x2.rawValue
    @AppStorage("viewState.v1.multiChart.cellsJSON") private var cellsJSON: String = ""
    /// v15.23 batch55 · 命名布局预设 JSON（trader 自定义命名组合）
    @AppStorage("viewState.v1.multiChart.layoutsJSON") private var layoutsJSON: String = ""

    @State private var cells: [MultiChartCellState] = []
    /// 保存预设 sheet
    @State private var showSaveSheet: Bool = false
    @State private var newLayoutName: String = ""
    /// v15.23 batch53 · 双击 focus 时记下原 preset · 再次双击/Esc 恢复
    @State private var focusedIdx: Int? = nil
    @State private var presetBeforeFocus: WindowGridPreset? = nil
    /// v15.23 batch56 · auto-tick · 每秒递增 · 注入 mock data 让末根 K 线微动
    @State private var tickSeed: UInt64 = 1
    @AppStorage("viewState.v1.multiChart.autoTick") private var autoTickEnabled: Bool = true
    /// v15.23 batch60 · 帮助面板（⌘⇧? · 22+ 操作清单 · trader 学习入口）
    @State private var showHelpSheet: Bool = false
    /// v15.23 batch68 · 共享悬停 K 线索引 · 跨 cell 联动十字线
    @State private var sharedHoveredIndex: Int? = nil
    /// v15.23 batch70 · cell 真行情 bars 镜像（uuid → bars · cell 上报 · statusBar hoverOHLC 用）
    @State private var cellLiveBars: [UUID: [KLine]] = [:]

    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var preset: WindowGridPreset {
        WindowGridPreset(rawValue: presetRaw) ?? .grid2x2
    }

    /// 当前实际渲染的 preset（focus 时强制 single · 不持久化）
    private var effectivePreset: WindowGridPreset {
        focusedIdx == nil ? preset : .single
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            grid
            Divider()
            statusBar
        }
        .frame(minWidth: 720, idealWidth: 1080, minHeight: 480, idealHeight: 720)
        .onAppear {
            loadCellsIfNeeded()
        }
        .onReceive(tickTimer) { _ in
            // v15.23 batch56 · auto-tick · 每秒抖动末根 K 线（仅当 autoTickEnabled 时）
            if autoTickEnabled {
                tickSeed &+= 1
            }
        }
        // v15.23 batch55 · 保存预设 sheet
        .sheet(isPresented: $showSaveSheet) {
            saveLayoutSheet
        }
        // v15.23 batch60 · 帮助面板
        .sheet(isPresented: $showHelpSheet) {
            helpSheet
        }
        // v15.23 batch53 · grid preset 快捷键 ⌘⌥1-6（隐藏 button 触发）
        .background(
            Group {
                Button("") { applyPreset(.single) }
                    .keyboardShortcut("1", modifiers: [.command, .option]).opacity(0)
                Button("") { applyPreset(.horizontal2) }
                    .keyboardShortcut("2", modifiers: [.command, .option]).opacity(0)
                Button("") { applyPreset(.vertical2) }
                    .keyboardShortcut("3", modifiers: [.command, .option]).opacity(0)
                Button("") { applyPreset(.grid2x2) }
                    .keyboardShortcut("4", modifiers: [.command, .option]).opacity(0)
                Button("") { applyPreset(.grid2x3) }
                    .keyboardShortcut("5", modifiers: [.command, .option]).opacity(0)
                Button("") { applyPreset(.grid3x2) }
                    .keyboardShortcut("6", modifiers: [.command, .option]).opacity(0)
                Button("") { exitFocus() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
            }
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("📊 多图表").font(.headline)
            Divider().frame(height: 18)

            Picker("布局", selection: Binding(
                get: { preset },
                set: { applyPreset($0) }
            )) {
                ForEach(WindowGridPreset.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            Text("\(activeCellCount) / \(preset.maxWindows) cell")
                .font(.caption)
                .foregroundColor(.secondary)

            // v15.23 batch53 · focus 模式提示
            if let idx = focusedIdx {
                HStack(spacing: 4) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.accentColor)
                    Text("聚焦 #\(idx + 1) · Esc 或双击退出")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()

            // v15.23 batch59 · 批量同步 Menu（trader 一键多周期/多合约比对）
            Menu {
                Section("全部设为周期") {
                    ForEach(Self.periodPool, id: \.self) { p in
                        Button(p.rawValue) { applyPeriodToAll(p) }
                    }
                }
                Divider()
                Section("全部设为合约") {
                    ForEach(Self.instrumentPool, id: \.self) { id in
                        Button(id) { applyInstrumentToAll(id) }
                    }
                }
            } label: {
                Label("批量", systemImage: "rectangle.3.group")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            .help("一键把所有 cell 设为同周期（多合约比对）/ 同合约（多周期比对）")

            // v15.23 batch55 · 布局预设 Menu
            Menu {
                Button {
                    newLayoutName = "我的布局 \(savedLayouts.count + 1)"
                    showSaveSheet = true
                } label: {
                    Label("保存当前为预设…", systemImage: "square.and.arrow.down")
                }
                let layouts = savedLayouts
                if !layouts.isEmpty {
                    Divider()
                    Section("加载") {
                        ForEach(layouts) { layout in
                            Button(layout.name) {
                                applyLayout(layout)
                            }
                            .help("\(layout.preset.label) · \(layout.cells.count) cell")
                        }
                    }
                    Divider()
                    Menu("删除预设") {
                        ForEach(layouts) { layout in
                            Button(layout.name, role: .destructive) {
                                deleteLayout(layout.id)
                            }
                        }
                    }
                }
                Divider()
                Button {
                    exportCurrentLayout()
                } label: {
                    Label("导出当前布局…", systemImage: "square.and.arrow.up")
                }
                Button {
                    importLayout()
                } label: {
                    Label("导入布局…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("布局预设", systemImage: "square.grid.3x3.square")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .help("保存 / 加载 / 删除自定义多图表布局")

            // v15.23 batch56 · auto-tick toggle
            Button {
                autoTickEnabled.toggle()
            } label: {
                Image(systemName: autoTickEnabled ? "play.circle.fill" : "pause.circle")
                    .foregroundColor(autoTickEnabled ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(autoTickEnabled ? "实时抖动开（每秒 mock tick）" : "已暂停 mock tick")

            // v15.23 batch60 · 帮助面板
            Button {
                showHelpSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("?", modifiers: [.command, .shift])
            .help("显示所有功能与快捷键（⌘⇧?）")

            // v15.23 batch53 · 快捷键提示（hover 显示）
            Text("⌘⌥1-6 切布局")
                .font(.caption2)
                .foregroundColor(.secondary)
                .help("⌘⌥1=单图 / 2=横 / 3=纵 / 4=四宫 / 5=2×3 / 6=3×2 · 双击 cell 全屏 · Esc 退出")

            Button {
                resetAllCells()
            } label: {
                Label("重置 cells", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("把所有 cell 还原为默认合约 + 周期")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - v15.23 batch65 · 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(preset.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 12)
            Text("\(activeCellCount) 活跃 / \(cells.count) 总 cell")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Divider().frame(height: 12)
            HStack(spacing: 4) {
                Circle()
                    .fill(autoTickEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(autoTickEnabled ? "tick 实时" : "tick 暂停")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 12)
            Text("\(savedLayouts.count) 个已保存预设")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            // v15.23 batch69 · hover 时显示 active cell 的完整 OHLC + volume
            if let hidx = sharedHoveredIndex, focusedIdx == nil {
                hoverOHLCText(idx: hidx)
            } else if let idx = focusedIdx {
                if let hidx = sharedHoveredIndex {
                    hoverOHLCText(idx: hidx, focusedCellIdx: idx)
                } else {
                    Text("聚焦 #\(idx + 1) · \(cellAt(idx).instrumentID) · \(cellAt(idx).period.rawValue)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
            } else {
                Text("⌘⇧? 查看全部功能 · 鼠标悬停 cell 联动十字线")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.06))
    }

    /// v15.23 batch69 · hover 时显示某 cell 的 K 线 [idx] OHLC + volume
    /// v15.23 batch70 · 优先使用 cell 上报的真行情 bars · 无则 mock 兜底
    /// v15.23 batch75 · 加 MA5/MA20/MA60 hover 数值（trader 看 K 线同时判断均线位置）
    @ViewBuilder
    private func hoverOHLCText(idx: Int, focusedCellIdx: Int? = nil) -> some View {
        // 显示哪个 cell 的数据：focus 模式 → focused cell · 否则 → cell #1（参考）
        let cellIdx = focusedCellIdx ?? 0
        let state = cellAt(cellIdx)
        let bars: [KLine] = {
            if let live = cellLiveBars[state.id], !live.isEmpty { return live }
            return MultiChartMockData.bars(instrumentID: state.instrumentID,
                                            period: state.period,
                                            tickSeed: autoTickEnabled ? tickSeed : 0)
        }()
        if idx < bars.count {
            let b = bars[idx]
            let o = (b.open as NSDecimalNumber).doubleValue
            let h = (b.high as NSDecimalNumber).doubleValue
            let l = (b.low as NSDecimalNumber).doubleValue
            let c = (b.close as NSDecimalNumber).doubleValue
            let isUp = c >= o
            let ma5 = Self.maAt(bars: bars, idx: idx, period: 5)
            let ma20 = Self.maAt(bars: bars, idx: idx, period: 20)
            let ma60 = Self.maAt(bars: bars, idx: idx, period: 60)
            HStack(spacing: 6) {
                Text("[\(idx + 1)/\(bars.count)]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("O \(String(format: "%.2f", o))").font(.system(size: 10, design: .monospaced))
                Text("H \(String(format: "%.2f", h))").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red.opacity(0.8))
                Text("L \(String(format: "%.2f", l))").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                Text("C \(String(format: "%.2f", c))").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isUp ? .red : .green)
                Text("V \(b.volume)").font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                if state.showIndicators {
                    if let m = ma5 {
                        Text("M5 \(String(format: "%.2f", m))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.9))
                    }
                    if let m = ma20 {
                        Text("M20 \(String(format: "%.2f", m))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.9))
                    }
                    if let m = ma60 {
                        Text("M60 \(String(format: "%.2f", m))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.blue.opacity(0.9))
                    }
                }
                // v15.23 batch81 · 副图数值（KDJ K/D/J 或 MACD DIF/DEA/M）· trader 顶/底背离判断
                switch state.subChart {
                case .kdj:
                    if let kdj = Self.kdjAt(bars: bars, idx: idx) {
                        Text(String(format: "K %.1f", kdj.k))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Text(String(format: "D %.1f", kdj.d))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.85))
                        Text(String(format: "J %.1f", kdj.j))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.purple.opacity(0.85))
                    }
                case .macd:
                    if let m = Self.macdAt(bars: bars, idx: idx) {
                        let mIsUp = m.macd >= 0
                        Text(String(format: "DIF %.2f", m.dif))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Text(String(format: "DEA %.2f", m.dea))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.85))
                        Text(String(format: "M %+.2f", m.macd))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(mIsUp ? .red.opacity(0.85) : .green.opacity(0.85))
                    }
                case .volume, .none:
                    EmptyView()
                }
            }
        }
    }

    /// v15.23 batch75 · 计算 bars[idx] 的 SMA(period) · 历史不足返 nil
    static func maAt(bars: [KLine], idx: Int, period: Int) -> Double? {
        guard period > 0, idx < bars.count, idx >= period - 1 else { return nil }
        var sum: Double = 0
        for i in (idx - period + 1)...idx {
            sum += (bars[i].close as NSDecimalNumber).doubleValue
        }
        return sum / Double(period)
    }

    /// v15.23 batch81 · KDJ 9-3-3 标准算法 · bars[idx] 处的 (K, D, J)
    static func kdjAt(bars: [KLine], idx: Int) -> (k: Double, d: Double, j: Double)? {
        let N = 9
        guard idx < bars.count, idx >= N - 1 else { return nil }
        var prevK = 50.0
        var prevD = 50.0
        for i in (N - 1)...idx {
            var hh = -Double.infinity
            var ll = Double.infinity
            for j in (i - N + 1)...i {
                let h = (bars[j].high as NSDecimalNumber).doubleValue
                let l = (bars[j].low as NSDecimalNumber).doubleValue
                if h > hh { hh = h }
                if l < ll { ll = l }
            }
            let close = (bars[i].close as NSDecimalNumber).doubleValue
            let rsv = hh - ll > 0 ? (close - ll) / (hh - ll) * 100 : 50
            let k = (2.0 / 3.0) * prevK + (1.0 / 3.0) * rsv
            let d = (2.0 / 3.0) * prevD + (1.0 / 3.0) * k
            prevK = k
            prevD = d
            if i == idx {
                let j = 3 * k - 2 * d
                return (k, d, j)
            }
        }
        return nil
    }

    /// v15.23 batch81 · MACD 12-26-9 · bars[idx] 处的 (DIF, DEA, MACD)
    static func macdAt(bars: [KLine], idx: Int) -> (dif: Double, dea: Double, macd: Double)? {
        guard idx >= 26 + 9 - 1, idx < bars.count else { return nil }
        let closes = bars[0...idx].map { ($0.close as NSDecimalNumber).doubleValue }
        var ema12 = closes[0]
        var ema26 = closes[0]
        let a12 = 2.0 / 13
        let a26 = 2.0 / 27
        let a9 = 2.0 / 10
        var dea: Double? = nil
        var lastDif: Double = 0
        for i in 0...idx {
            let c = closes[i]
            ema12 = c * a12 + ema12 * (1 - a12)
            ema26 = c * a26 + ema26 * (1 - a26)
            let dif = ema12 - ema26
            lastDif = dif
            if let d = dea {
                dea = dif * a9 + d * (1 - a9)
            } else {
                dea = dif
            }
        }
        guard let d = dea else { return nil }
        return (lastDif, d, (lastDif - d) * 2)
    }

    // MARK: - Grid

    private var grid: some View {
        GeometryReader { geo in
            let p = effectivePreset
            let frames = p.layout(forWindowCount: p.maxWindows)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { idx, frame in
                    // focus 时仅渲染 focused cell 内容（idx=0 槽 → focusedIdx 那个 state）
                    let realIdx = focusedIdx ?? idx
                    let cellState = cellAt(realIdx)
                    cellView(state: cellState, idx: realIdx)
                        .frame(
                            width: max(0, geo.size.width * frame.width - 4),
                            height: max(0, geo.size.height * frame.height - 4)
                        )
                        .offset(
                            x: geo.size.width * frame.x + 2,
                            y: geo.size.height * frame.y + 2
                        )
                        .onTapGesture(count: 2) {
                            toggleFocus(idx: realIdx)
                        }
                        // v15.23 batch54 · cell 右键菜单
                        .contextMenu {
                            cellContextMenu(idx: realIdx)
                        }
                }
            }
        }
    }

    /// v15.23 batch54 · 单 cell 右键菜单
    @ViewBuilder
    private func cellContextMenu(idx: Int) -> some View {
        let total = effectivePreset.maxWindows
        Button {
            toggleFocus(idx: idx)
        } label: {
            Label(focusedIdx == idx ? "退出聚焦" : "聚焦此 cell（双击）",
                  systemImage: focusedIdx == idx ? "viewfinder.slash" : "viewfinder")
        }
        Divider()
        // 与下一个 cell 交换
        if total > 1 {
            Button {
                swapCells(idx, with: (idx + 1) % total)
            } label: {
                Label("与 #\((idx + 1) % total + 1) 交换", systemImage: "arrow.left.arrow.right")
            }
            Button {
                swapCells(idx, with: (idx - 1 + total) % total)
            } label: {
                Label("与 #\((idx - 1 + total) % total + 1) 交换", systemImage: "arrow.left.arrow.right.circle")
            }
        }
        // 复制到指定 slot（下拉子菜单）
        if total > 1 {
            Menu("复制配置到…") {
                ForEach(0..<total, id: \.self) { target in
                    if target != idx {
                        Button("Cell #\(target + 1)（\(cellAt(target).instrumentID) · \(cellAt(target).period.rawValue)）") {
                            copyCell(from: idx, to: target)
                        }
                    }
                }
            }
        }
        Divider()
        Button(role: .destructive) {
            resetCellToDefault(idx)
        } label: {
            Label("重置此 cell", systemImage: "arrow.counterclockwise")
        }
    }

    // MARK: - v15.23 batch54 · cell 操作

    private func swapCells(_ a: Int, with b: Int) {
        guard a != b, a < cells.count, b < cells.count else { return }
        cells.swapAt(a, b)
        persistCells()
    }

    private func copyCell(from src: Int, to dest: Int) {
        guard src < cells.count, dest < cells.count, src != dest else { return }
        cells[dest].instrumentID = cells[src].instrumentID
        cells[dest].period = cells[src].period
        cells[dest].showVolume = cells[src].showVolume
        persistCells()
    }

    private func resetCellToDefault(_ idx: Int) {
        guard idx < cells.count else { return }
        cells[idx] = MultiChartCellState(
            id: cells[idx].id,
            instrumentID: defaultInstrument(forIndex: idx),
            period: defaultPeriod(forIndex: idx)
        )
        persistCells()
    }

    /// v15.23 batch58 · 推送 cell 到主 ChartScene（复用 WatchlistWindow 的 .watchlistInstrumentSelected 通道）
    private func pushToMainChart(_ state: MultiChartCellState) {
        openWindow(id: "chart")
        NotificationCenter.default.post(name: .watchlistInstrumentSelected,
                                        object: state.instrumentID)
    }

    // MARK: - v15.23 batch59 · 批量同步 cells

    private func applyPeriodToAll(_ period: KLinePeriod) {
        for i in 0..<cells.count {
            cells[i].period = period
        }
        persistCells()
    }

    private func applyInstrumentToAll(_ instrumentID: String) {
        for i in 0..<cells.count {
            cells[i].instrumentID = instrumentID
        }
        persistCells()
    }

    // MARK: - v15.23 batch55 · 命名布局预设操作

    private var savedLayouts: [MultiChartLayoutPreset] {
        guard !layoutsJSON.isEmpty,
              let data = layoutsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([MultiChartLayoutPreset].self, from: data) else {
            return []
        }
        return arr
    }

    private func persistLayouts(_ layouts: [MultiChartLayoutPreset]) {
        if let data = try? JSONEncoder().encode(layouts),
           let s = String(data: data, encoding: .utf8) {
            layoutsJSON = s
        }
    }

    private func saveCurrentAsLayout(name: String) {
        var layouts = savedLayouts
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // 同名覆盖
        layouts.removeAll { $0.name == trimmed }
        layouts.append(MultiChartLayoutPreset(
            name: trimmed,
            preset: preset,
            cells: cells
        ))
        persistLayouts(layouts)
    }

    private func applyLayout(_ layout: MultiChartLayoutPreset) {
        focusedIdx = nil
        presetBeforeFocus = nil
        presetRaw = layout.preset.rawValue
        cells = layout.cells
        persistCells()
    }

    private func deleteLayout(_ id: UUID) {
        var layouts = savedLayouts
        layouts.removeAll { $0.id == id }
        persistLayouts(layouts)
    }

    // MARK: - v15.23 batch62 · 布局 JSON 导出/导入（trader 分享同事 · 跨设备同步）

    private func exportCurrentLayout() {
        let snapshot = MultiChartLayoutPreset(
            name: "导出布局 \(currentDateText())",
            preset: preset,
            cells: cells
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出多图表布局"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "multichart_layout_\(currentDateText()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.title = "导入多图表布局"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(MultiChartLayoutPreset.self, from: data) else {
            return
        }
        // 加入到已保存预设（去重 by name）+ 立即应用
        var layouts = savedLayouts
        layouts.removeAll { $0.name == layout.name }
        layouts.append(layout)
        persistLayouts(layouts)
        applyLayout(layout)
    }

    private func currentDateText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }

    // v15.23 batch60 · 帮助面板内容
    private static let helpGroups: [(String, [(String, String)])] = [
        ("📐 布局切换", [
            ("⌘⌥1", "单图（全屏）"),
            ("⌘⌥2", "1×2 横向"),
            ("⌘⌥3", "2×1 纵向"),
            ("⌘⌥4", "2×2 四宫"),
            ("⌘⌥5", "2×3 六宫横"),
            ("⌘⌥6", "3×2 六宫竖"),
            ("toolbar 布局 Picker", "鼠标点选 6 种布局 · 与快捷键等同"),
        ]),
        ("🔍 cell 操作", [
            ("双击 cell", "聚焦该 cell（临时全屏 · 不动 preset）"),
            ("Esc / 再次双击", "退出聚焦"),
            ("右键 cell", "聚焦/交换/复制配置/重置 4 类操作"),
            ("点击 #↗ 按钮", "推送到主 ChartScene 深入分析"),
            ("点击 cell 合约名/周期", "Menu 切换"),
            ("点击副图图标（batch79-80）", "切换副图：量 / KDJ 9-3-3 超买超卖 / MACD 12-26-9 趋势量能 / 无（主图全屏）"),
            ("副图金叉/死叉点（batch82）", "KDJ K↑D 或 MACD DIF↑DEA = 红点（金叉买点）· 反向 = 绿点（死叉卖点）· 一眼定位"),
            ("点击 chart.line 图标（batch72-74）", "切换 MA5（黄）+ MA10（粉）+ MA20（紫）+ MA60（蓝）四均线 · 中国期货短线经典标配"),
            ("点击 waveform 图标（batch78）", "切换 BOLL 上下轨（period=20 · k=2σ · 默认关 · 青色虚线 · 突破信号）"),
            ("鼠标悬停 cell（v15.23）", "全部 cell 同步显示同 index K 线虚线 + close 价（跨周期/合约比对杀手键）"),
            ("hover 时状态栏（batch75）", "OHLCV + M5/M20/M60 三条均线值（参考 cell #1 / focused cell · 当 cell 开启均线时显示）"),
        ]),
        ("📦 批量操作", [
            ("toolbar 批量 Menu", "全部 cell 设为同一周期（多合约比对）"),
            ("toolbar 批量 Menu", "全部 cell 设为同一合约（多周期比对）"),
            ("toolbar 重置 cells", "全部还原为默认合约 + 周期"),
        ]),
        ("📚 布局预设", [
            ("toolbar 布局预设 → 保存", "命名当前布局（如\"日内全屏六宫\"）"),
            ("toolbar 布局预设 → 加载", "一键还原已保存布局"),
            ("toolbar 布局预设 → 删除", "清理过期预设"),
        ]),
        ("📡 数据源状态（v15.23 batch70-71）", [
            ("🟢 绿点", "Sina 真行情接入成功（每 5s 轮询 · 自动合成 K 线）/ 本地缓存离线兜底（重启秒回）"),
            ("🟡 黄点", "Mock 兜底（行情不可达 + 无本地缓存 / 合约暂不在 supported 列表 · 仅 UI 演示）"),
            ("⚪️ 灰点", "加载中（首次启动 / 切合约/周期时短暂出现）"),
            ("toolbar play/pause", "Mock tick 抖动开关（不影响真行情 · 仅在黄点时让末根 K 线动起来）"),
            ("v15.23 batch71", "K 线 cache 持久化 · 重启不再黑屏 · 节假日断网保留最后真行情数据"),
        ]),
        ("💡 常用工作流", [
            ("默认开局（batch73）", "首次打开 = RB0 多周期共振（1m/5m/15m/30m/1h/D · 教科书场景）· 立即看真行情"),
            ("场景 A", "继续保留默认（同合约多周期共振 · 短线 trader 必看）"),
            ("场景 B", "toolbar 批量 → 全部设为 15m → 6 主流商品横向比对趋势"),
            ("场景 C", "保存常用组合为预设 → 一键切换日内/夜盘"),
            ("场景 D", "看到异动 cell → 点 ↗ 按钮 → 主图深入"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 多图表全功能").font(.title2).bold()
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
                            Text(group.0)
                                .font(.headline)
                            ForEach(group.1, id: \.0) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(item.0)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 160, alignment: .leading)
                                    Text(item.1)
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 540, idealWidth: 620, minHeight: 480, idealHeight: 600)
    }

    @ViewBuilder
    private var saveLayoutSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("保存当前布局为预设")
                .font(.title3).fontWeight(.semibold)
            HStack {
                Text("名称").frame(width: 60, alignment: .leading)
                TextField("如：日内全屏六宫", text: $newLayoutName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("将保存当前 \(preset.label) + \(cells.count) cell 配置")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            HStack {
                Spacer()
                Button("取消") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    saveCurrentAsLayout(name: newLayoutName)
                    showSaveSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newLayoutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360, height: 180)
    }

    // MARK: - Cell view（v15.23 batch70 · 拆为独立 MultiChartCellView · 每 cell 独立 pipeline 接真行情）

    private func cellView(state: MultiChartCellState, idx: Int) -> some View {
        MultiChartCellView(
            state: state,
            idx: idx,
            autoTickEnabled: autoTickEnabled,
            tickSeed: tickSeed,
            sharedHoveredIndex: sharedHoveredIndex,
            onHoverIndexChange: { hidx in sharedHoveredIndex = hidx },
            onBarsChange: { uuid, bars in cellLiveBars[uuid] = bars },
            onContractTap: { id in updateCell(idx) { $0.instrumentID = id } },
            onPeriodTap: { p in updateCell(idx) { $0.period = p } },
            onVolumeToggle: { updateCell(idx) { $0.showVolume.toggle() } },
            onIndicatorsToggle: { updateCell(idx) { $0.showIndicators.toggle() } },
            onBollToggle: { updateCell(idx) { $0.showBoll.toggle() } },
            onSubChartTap: { sub in updateCell(idx) {
                $0.subChart = sub
                $0.showVolume = (sub == .volume)  // 同步 legacy 字段（兼容旧 path）
            } },
            onPushToMain: { pushToMainChart(state) }
        )
    }

    // MARK: - Cell 状态更新（持久化）

    private func updateCell(_ idx: Int, mutate: (inout MultiChartCellState) -> Void) {
        guard idx < cells.count else { return }
        mutate(&cells[idx])
        persistCells()
    }

    private static let instrumentPool: [String] = [
        "RB0", "IF0", "AU0", "CU0", "I0", "MA0",
        "AG0", "TA0", "ZN0", "AL0",
    ]

    private static let periodPool: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30, .hour1, .hour4, .daily,
    ]

    // MARK: - State 操作

    private func cellAt(_ idx: Int) -> MultiChartCellState {
        guard idx < cells.count else {
            return MultiChartCellState(
                instrumentID: defaultInstrument(forIndex: idx),
                period: defaultPeriod(forIndex: idx)
            )
        }
        return cells[idx]
    }

    private var activeCellCount: Int {
        min(cells.count, preset.maxWindows)
    }

    /// 切换 preset 时同步 cells 数（不删 · 只补足）
    private func syncCellsToPreset(_ preset: WindowGridPreset) {
        let needed = preset.maxWindows
        if cells.count < needed {
            for i in cells.count..<needed {
                cells.append(MultiChartCellState(
                    instrumentID: defaultInstrument(forIndex: i),
                    period: defaultPeriod(forIndex: i)
                ))
            }
        }
        persistCells()
    }

    /// v15.23 batch53 · 应用 preset（菜单 + 快捷键共用）
    private func applyPreset(_ p: WindowGridPreset) {
        // 切 preset 时退出 focus
        focusedIdx = nil
        presetBeforeFocus = nil
        presetRaw = p.rawValue
        syncCellsToPreset(p)
    }

    /// v15.23 batch53 · cell 双击 toggle focus（focus 时该 cell 全屏）
    private func toggleFocus(idx: Int) {
        if focusedIdx == idx {
            exitFocus()
        } else {
            presetBeforeFocus = preset
            focusedIdx = idx
        }
    }

    /// 退出 focus 模式（Esc 或再次双击）· 不改 preset 只清 focus
    private func exitFocus() {
        focusedIdx = nil
        presetBeforeFocus = nil
    }

    /// 还原所有 cell 为默认配置（不删 cells · 只重置 instrumentID/period）
    private func resetAllCells() {
        for i in 0..<cells.count {
            cells[i] = MultiChartCellState(
                id: cells[i].id,
                instrumentID: defaultInstrument(forIndex: i),
                period: defaultPeriod(forIndex: i)
            )
        }
        persistCells()
    }

    private func loadCellsIfNeeded() {
        guard cells.isEmpty else { return }
        if !cellsJSON.isEmpty,
           let data = cellsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([MultiChartCellState].self, from: data),
           !decoded.isEmpty {
            cells = decoded
        } else {
            // 初始化默认 6 cells（最大 preset 6 窗 · 切换不再补足）
            cells = (0..<6).map { i in
                MultiChartCellState(
                    instrumentID: defaultInstrument(forIndex: i),
                    period: defaultPeriod(forIndex: i)
                )
            }
            persistCells()
        }
    }

    private func persistCells() {
        if let data = try? JSONEncoder().encode(cells),
           let s = String(data: data, encoding: .utf8) {
            cellsJSON = s
        }
    }

    // MARK: - 默认值（v15.23 batch73 · 全 RB0 多周期共振 · 短线 trader 教科书场景）
    // 6 cell 同合约不同周期 · 首次打开即可立即看真行情趋势 · 老用户 cellsJSON 已有则不覆盖
    // 想看多合约对比 → toolbar"批量 Menu → 全部设为合约"一键切换（< 1 秒）

    private func defaultInstrument(forIndex idx: Int) -> String {
        // RB0 ∈ MarketDataPipeline.supportedContracts · 真行情立即生效
        return "RB0"
    }

    private func defaultPeriod(forIndex idx: Int) -> KLinePeriod {
        // 6 周期梯度：1m → 5m → 15m → 30m → 1h → 日 · 短中长全栈共振
        let pool: [KLinePeriod] = [.minute1, .minute5, .minute15, .minute30, .hour1, .daily]
        return pool[idx % pool.count]
    }
}

// MARK: - WindowGridPreset 显示名扩展

private extension WindowGridPreset {
    var label: String {
        switch self {
        case .single:      return "1×1（单图）"
        case .horizontal2: return "1×2（横向）"
        case .vertical2:   return "2×1（纵向）"
        case .grid2x2:     return "2×2（四宫）"
        case .grid2x3:     return "2×3（六宫横）"
        case .grid3x2:     return "3×2（六宫竖）"
        }
    }
}

#endif
