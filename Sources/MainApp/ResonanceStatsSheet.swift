// v17.184 · 多周期共振信号历史回测 sheet（v17.183 UI 闭环 · ⌘⌥⇧Y）
//
// 触发：⌘⌥⇧Y 主图（与 ⌘⇧Y 多周期共振 overlay toggle 配对的统计版）
// 内容：当前 bars + defaultTargets 跑 detect · 跑 performanceStats · 按 (kind, sourcePeriod) 排表

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import IndicatorCore
import Shared

struct ResonanceStatsSheet: View {

    let stats: [ResonanceSignalPerformanceStats]
    let chartTheme: ChartTheme
    let candleColorMode: CandleColorMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("多周期共振 · 历史回测")
                    .font(.title2).bold()
                Spacer()
                Text("共 \(stats.count) 组")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            Text("trader 看哪种共振信号在自家数据上更准 · 区分 sourcePeriod · 后 20 根 close 变化 + 与 direction 一致胜率")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            if stats.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("当前 K 线无共振信号或后续 bars 不足回测")
                        .foregroundColor(.secondary)
                    Text("尝试加载更长历史（≥ 20 根 lookForward）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 表头
                HStack(spacing: 0) {
                    cellH("信号", w: 110, align: .leading)
                    cellH("周期", w: 60)
                    cellH("命中", w: 50)
                    cellH("均价变化", w: 90)
                    cellH("胜率", w: 70)
                    Spacer()
                }
                .background(Color.secondary.opacity(0.06))
                .frame(height: 28)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stats.indices, id: \.self) { i in
                            statsRow(stats[i])
                                .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.04))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 520, height: 560)
    }

    private func cellH(_ text: String, w: CGFloat, align: Alignment = .trailing) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .frame(width: w, alignment: align)
            .padding(.horizontal, 4)
    }

    private func statsRow(_ s: ResonanceSignalPerformanceStats) -> some View {
        let isBull = s.kind.direction > 0
        let kindColor = isBull
            ? chartTheme.candleUp(mode: candleColorMode)
            : chartTheme.candleDown(mode: candleColorMode)
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(s.kind.shortCode)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(kindColor)
                    .frame(width: 24, alignment: .center)
                Text(s.kind.displayName)
                    .font(.system(size: 11))
            }
            .frame(width: 110, alignment: .leading)
            .padding(.horizontal, 4)
            Text(s.sourcePeriod.displayName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60)
            Text("\(s.occurrenceCount)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
                .padding(.horizontal, 4)
            Text(String(format: "%+.2f%%", s.averagePriceChangePct))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 90, alignment: .trailing)
                .foregroundColor(s.averagePriceChangePct >= 0
                    ? chartTheme.candleUp(mode: candleColorMode)
                    : chartTheme.candleDown(mode: candleColorMode))
                .padding(.horizontal, 4)
            Text(String(format: "%.0f%%", s.winRatePct))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
                .foregroundColor(s.winRatePct >= 60 ? .green : (s.winRatePct >= 40 ? .orange : .red))
                .padding(.horizontal, 4)
            Spacer()
        }
        .frame(height: 24)
    }
}

#endif
