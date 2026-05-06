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
import Foundation
import Shared

struct MultiChartHost: View {

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
        }
        .frame(minWidth: 720, idealWidth: 1080, minHeight: 480, idealHeight: 720)
        .onAppear {
            loadCellsIfNeeded()
        }
        // v15.23 batch55 · 保存预设 sheet
        .sheet(isPresented: $showSaveSheet) {
            saveLayoutSheet
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
            } label: {
                Label("布局预设", systemImage: "square.grid.3x3.square")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .help("保存 / 加载 / 删除自定义多图表布局")

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

    // MARK: - Cell view（batch52 加每 cell toolbar · 合约 picker + 周期切换 + 量开关）

    private func cellView(state: MultiChartCellState, idx: Int) -> some View {
        VStack(spacing: 0) {
            cellToolbar(state: state, idx: idx)
            // K 线 Canvas（mock data · 后续 batch 接 SinaMarketDataProvider 真数据）
            MultiChartCellCanvas(
                bars: MultiChartMockData.bars(instrumentID: state.instrumentID,
                                              period: state.period),
                showVolume: state.showVolume
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .cornerRadius(4)
    }

    /// v15.23 batch52 · 每 cell 独立 toolbar
    private func cellToolbar(state: MultiChartCellState, idx: Int) -> some View {
        HStack(spacing: 4) {
            // 合约 picker
            Menu {
                ForEach(Self.instrumentPool, id: \.self) { id in
                    Button(id) {
                        updateCell(idx) { $0.instrumentID = id }
                    }
                }
            } label: {
                Text(state.instrumentID)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 40)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 60)
            .help("切换合约")

            // 周期切换 segmented
            Menu {
                ForEach(Self.periodPool, id: \.self) { p in
                    Button(p.rawValue) {
                        updateCell(idx) { $0.period = p }
                    }
                }
            } label: {
                Text(state.period.rawValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 50)
            .help("切换周期")

            Spacer()

            // 末根 close（mock）
            lastPriceText(state: state)

            // 量开关
            Button {
                updateCell(idx) { $0.showVolume.toggle() }
            } label: {
                Image(systemName: state.showVolume ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help(state.showVolume ? "隐藏成交量" : "显示成交量")

            Text("#\(idx + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
    }

    /// 末根 K 线 close 显示在标题栏（mock）
    @ViewBuilder
    private func lastPriceText(state: MultiChartCellState) -> some View {
        let bars = MultiChartMockData.bars(instrumentID: state.instrumentID, period: state.period)
        if let last = bars.last {
            let close = (last.close as NSDecimalNumber).doubleValue
            let prev = bars.count >= 2 ? (bars[bars.count - 2].close as NSDecimalNumber).doubleValue : close
            let isUp = close >= prev
            Text(String(format: "%.2f", close))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isUp ? .red : .green)
        }
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

    // MARK: - 默认值（按 cell index · 不同 cell 不同合约/周期 · trader 一开就有对比效果）

    private func defaultInstrument(forIndex idx: Int) -> String {
        let pool = ["RB0", "IF0", "AU0", "CU0", "I0", "MA0"]
        return pool[idx % pool.count]
    }

    private func defaultPeriod(forIndex idx: Int) -> KLinePeriod {
        let pool: [KLinePeriod] = [.minute15, .minute5, .hour1, .daily, .minute1, .minute30]
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
