// 价格关联性矩阵窗口（v15.48 · ⌘⌥C · 跨品种相关性热力图）
//
// 核心价值（trader 套利+对冲核心工具）：
//   - 找跨品种套利对：高正相关品种价差稳定 · 适合 mean-reverting
//   - 找对冲品种：高负相关 · 反向头寸自然对冲
//   - 板块异动：板块内某品种相关性骤降 = 异动信号
//
// 设计：
//   - 板块过滤（默认 全部 7+ 品种 黑色 / 板块切换显示该板块 N×N）
//   - 矩阵 cell 颜色：橙色=正相关（深=强）/ 蓝色=负相关 / 灰=无关
//   - 对角线深灰（自相关 = 1 · 不重要）
//   - hover：显示完整品种对 + 实际值 + 类型说明（强/中/弱/反向）
//
// 数据：CorrelationMockSeries 生成 200 点 mock 时序 · 板块因子注入 · 同板块自然高相关

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct CorrelationWindow: View {

    @State private var sectorFilter: SectorFilter = .sector(.黑色)
    @State private var hoveredCell: (row: Int, col: Int)?
    @State private var seriesCount: Int = 200    // 时序长度（trader 可调）
    @Environment(\.openWindow) private var openWindow

    enum SectorFilter: Hashable, Identifiable {
        case all
        case sector(Sector)

        var id: String {
            switch self {
            case .all: return "all"
            case .sector(let s): return s.id
            }
        }

        var displayName: String {
            switch self {
            case .all: return "全市场"
            case .sector(let s): return s.displayName
            }
        }
    }

    private var pool: [SectorInstrument] {
        switch sectorFilter {
        case .all: return SectorPresets.all
        case .sector(let s): return SectorPresets.instruments(in: s)
        }
    }

    private var matrix: CorrelationMatrix {
        let series = CorrelationMockSeries.generate(for: pool, count: seriesCount)
        return CorrelationMatrixCalculator.compute(
            seriesByID: series,
            orderedIDs: pool.map { $0.id }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                matrixView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                hoverPanel
                    .frame(width: 280)
            }
            Divider()
            legendBar
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时自动切到该合约的板块（让矩阵显示该板块）
            if let id = note.object as? String, let sec = SectorPresets.byID[id]?.sector {
                sectorFilter = .sector(sec)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("板块").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $sectorFilter) {
                    Text("全市场").tag(SectorFilter.all)
                    ForEach(Sector.allCases) { sec in
                        Text(sec.displayName).tag(SectorFilter.sector(sec))
                    }
                }
                .frame(width: 130)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("时序长度").font(.callout).foregroundColor(.secondary)
                Stepper(value: $seriesCount, in: 50...500, step: 50) {
                    Text("\(seriesCount)").font(.callout.monospaced()).frame(minWidth: 32)
                }
                .frame(width: 140)
            }

            Spacer()

            Text("\(pool.count) × \(pool.count) cell · v1 mock 板块因子（v2 接 CTP 真历史 K 线）")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 矩阵主视图

    private var matrixView: some View {
        GeometryReader { geom in
            let n = pool.count
            let labelW: CGFloat = 60
            let labelH: CGFloat = 28
            let availW = geom.size.width - labelW
            let availH = geom.size.height - labelH
            let cellSize = max(20, min(availW / CGFloat(n), availH / CGFloat(n)))
            let m = matrix
            ZStack(alignment: .topLeading) {
                ChartTheme.dark.background
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 顶部 column header（旋转 45° 不容易实现 · 直接横排）
                        HStack(spacing: 0) {
                            Color.clear.frame(width: labelW, height: labelH)
                            ForEach(0..<n, id: \.self) { j in
                                Text(pool[j].id)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: cellSize, height: labelH)
                            }
                        }
                        // 行 · row label + N cells
                        ForEach(0..<n, id: \.self) { i in
                            HStack(spacing: 0) {
                                Text(pool[i].id)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: labelW, height: cellSize, alignment: .trailing)
                                    .padding(.trailing, 4)
                                ForEach(0..<n, id: \.self) { j in
                                    correlationCell(value: m.values[i][j],
                                                    row: i, col: j,
                                                    size: cellSize)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func correlationCell(value: Double, row: Int, col: Int, size: CGFloat) -> some View {
        let isHovered = hoveredCell?.row == row && hoveredCell?.col == col
        let isDiag = row == col
        let bg = colorFor(correlation: value, isDiag: isDiag)
        let textColor: Color = abs(value) >= 0.5 ? .white : .white.opacity(0.7)
        return ZStack {
            Rectangle().fill(bg)
                .overlay(
                    Rectangle()
                        .stroke(isHovered ? Color.white : Color.clear, lineWidth: 1.5)
                )
            if size >= 32 {
                Text(String(format: "%.2f", value))
                    .font(.system(size: 9, design: .monospaced).bold())
                    .foregroundColor(textColor)
            }
        }
        .frame(width: size, height: size)
        .onHover { isOver in
            hoveredCell = isOver ? (row, col) : nil
        }
    }

    /// 相关系数 → 颜色映射
    /// - +0.7 ~ +1.0：深橙
    /// - +0.3 ~ +0.7：浅橙
    /// - -0.3 ~ +0.3：灰
    /// - -0.7 ~ -0.3：浅蓝
    /// - -1.0 ~ -0.7：深蓝
    /// - 对角线：深灰（突出非自相关数据）
    private func colorFor(correlation r: Double, isDiag: Bool) -> Color {
        if isDiag { return Color.white.opacity(0.15) }
        let absR = abs(r)
        let intensity = min(absR, 1.0)
        if r > 0 {
            // 橙系：浅 → 深
            return Color.orange.opacity(0.20 + intensity * 0.65)
        } else {
            // 蓝系：浅 → 深
            return Color.blue.opacity(0.20 + intensity * 0.65)
        }
    }

    // MARK: - Hover panel（右侧详情）

    private var hoverPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 hover 详情")
                .font(.headline)
                .foregroundColor(.secondary)

            if let h = hoveredCell {
                let id1 = pool[h.row].id
                let id2 = pool[h.col].id
                let name1 = pool[h.row].name
                let name2 = pool[h.col].name
                let r = matrix.values[h.row][h.col]
                let category = correlationCategory(r: r, isDiag: h.row == h.col)
                Divider()
                hoverRow("行", "\(name1)（\(id1)）", color: .primary)
                hoverRow("列", "\(name2)（\(id2)）", color: .primary)
                Divider()
                hoverRow("r 值", String(format: "%.4f", r), color: r > 0 ? .orange : .blue)
                hoverRow("类型", category.label, color: category.color)
                hoverRow("解读", category.description, color: .secondary)
                if h.row != h.col {
                    Divider()
                    HStack(spacing: 8) {
                        Button("\(id1) → 主图") {
                            openWindow(id: "chart")
                            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: id1)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("\(id2) → 主图") {
                            openWindow(id: "chart")
                            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: id2)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
            } else {
                Divider()
                Text("将鼠标移到矩阵 cell 上 · 查看品种对相关系数 + 类型解读")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                trader_tips
            }
            Spacer()
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.04))
    }

    private var trader_tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trader 用法").font(.subheadline.bold()).foregroundColor(.secondary)
            tipRow(symbol: "→", text: "强正相关（r > 0.7）：套利候选（mean-reverting 价差）", color: .orange)
            tipRow(symbol: "→", text: "强负相关（r < -0.7）：自然对冲（反向头寸抵消风险）", color: .blue)
            tipRow(symbol: "→", text: "板块异动：板块内某 cell 突然变浅 = 该品种异动", color: .yellow)
            tipRow(symbol: "→", text: "宏观分散：跨板块矩阵 cell 越蓝/越淡，组合越分散", color: .secondary)
        }
    }

    private func tipRow(symbol: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(symbol).font(.caption.bold()).foregroundColor(color)
            Text(text).font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hoverRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
            Text(value).font(.caption.monospaced()).foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private struct CorrCategory {
        let label: String
        let description: String
        let color: Color
    }

    private func correlationCategory(r: Double, isDiag: Bool) -> CorrCategory {
        if isDiag { return CorrCategory(label: "自相关", description: "r=1（自身）", color: .secondary) }
        switch r {
        case 0.7...:    return CorrCategory(label: "强正", description: "高度同向 · 套利候选", color: .orange)
        case 0.3..<0.7: return CorrCategory(label: "中正", description: "同向 · 部分关联", color: .orange.opacity(0.7))
        case -0.3..<0.3: return CorrCategory(label: "无关", description: "独立运行 · 分散组合", color: .secondary)
        case -0.7..<(-0.3): return CorrCategory(label: "中负", description: "反向 · 部分对冲", color: .blue.opacity(0.7))
        default:        return CorrCategory(label: "强负", description: "反向 · 对冲候选", color: .blue)
        }
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 16) {
            Text("色阶").font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 0) {
                ForEach([-0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9], id: \.self) { r in
                    let absR = abs(r)
                    let bg: Color = r > 0
                        ? Color.orange.opacity(0.20 + absR * 0.65)
                        : (r < 0
                           ? Color.blue.opacity(0.20 + absR * 0.65)
                           : Color.secondary.opacity(0.20))
                    Rectangle()
                        .fill(bg)
                        .frame(width: 42, height: 16)
                        .overlay(
                            Text(String(format: "%+.1f", r))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white)
                        )
                }
            }
            .cornerRadius(2)
            Spacer()
            Text("· 橙=正相关 · 蓝=负相关 · 灰=无关 · hover 看详情 · 点品种 → 主图")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }
}

#endif
