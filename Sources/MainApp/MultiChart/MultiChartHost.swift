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

    @State private var cells: [MultiChartCellState] = []

    private var preset: WindowGridPreset {
        WindowGridPreset(rawValue: presetRaw) ?? .grid2x2
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("📊 多图表").font(.headline)
            Divider().frame(height: 18)

            Picker("布局", selection: Binding(
                get: { preset },
                set: { newPreset in
                    presetRaw = newPreset.rawValue
                    syncCellsToPreset(newPreset)
                }
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

            Spacer()

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
            let frames = preset.layout(forWindowCount: preset.maxWindows)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { idx, frame in
                    let cellState = cellAt(idx)
                    cellView(state: cellState, idx: idx)
                        .frame(
                            width: max(0, geo.size.width * frame.width - 4),
                            height: max(0, geo.size.height * frame.height - 4)
                        )
                        .offset(
                            x: geo.size.width * frame.x + 2,
                            y: geo.size.height * frame.y + 2
                        )
                }
            }
        }
    }

    // MARK: - Cell stub view（batch51 替换为 mini-K 线）

    private func cellView(state: MultiChartCellState, idx: Int) -> some View {
        VStack(spacing: 0) {
            // cell 顶部 mini-toolbar（占位 · batch52 替换为合约 picker + 周期切换）
            HStack(spacing: 6) {
                Text(state.instrumentID)
                    .font(.system(size: 12, weight: .semibold))
                Text(state.period.rawValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Cell #\(idx + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
            // 占位主体（batch51 → mini K 线 Canvas）
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.05))
                Text("📈 \(state.instrumentID) · \(state.period.rawValue)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .cornerRadius(4)
    }

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
