// v17.165 · 形态识别清单 sheet（⌘⇧L · 列出当前 K 线全部检出形态 · trader 完整浏览 + 视觉跳转）
//
// 用途：v17.164 主图 overlay 只显示 visible 区间的形态 · 完整 K 历史的形态需要清单浏览
// 入口：⌘⇧L 触发 · 或主图 overlay menu 加按钮
// 行为：detect 一次（当前 bars 缓存）· List 显示 · 点行 → 跳转 viewport 到该形态 startIndex
//
// 设计：
// - 不持续监控（区分 v3 alert 实时触发）· 单次扫描即用即关
// - 按 confidence 降序 · trader 优先看最可靠的
// - 4 形态分色 icon · 复用 PatternKind.icon

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import IndicatorCore
import Shared

struct PatternsListSheet: View {

    let patterns: [DetectedPattern]
    /// v17.182 · 历史回测统计（caller 跑 PatternPerformanceAnalyzer.analyze 传入 · 不传 = 不显示）
    let stats: [PatternPerformanceStats]
    let chartTheme: ChartTheme
    let candleColorMode: CandleColorMode
    let onJumpTo: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    /// v17.182 兼容旧 caller（无 stats 参数）
    init(
        patterns: [DetectedPattern],
        stats: [PatternPerformanceStats] = [],
        chartTheme: ChartTheme,
        candleColorMode: CandleColorMode,
        onJumpTo: @escaping (Int) -> Void
    ) {
        self.patterns = patterns
        self.stats = stats
        self.chartTheme = chartTheme
        self.candleColorMode = candleColorMode
        self.onJumpTo = onJumpTo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("形态识别清单")
                    .font(.title2).bold()
                Spacer()
                Text("共 \(patterns.count) 个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            // v17.182 · 历史回测统计区（仅有命中的 kind 显示 · 占位 0 命中的 kind 不显示避免噪声）
            if !stats.isEmpty {
                statsSection
                Divider().padding(.bottom, 6)
            }

            if patterns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("当前 K 线序列未检出任何形态")
                        .foregroundColor(.secondary)
                    Text("尝试加载更长历史 / 调整 ZigZag 灵敏度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedPatterns, id: \.startIndex) { pattern in
                    Button {
                        onJumpTo(pattern.startIndex)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: pattern.kind.icon)
                                .foregroundColor(colorFor(pattern))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(pattern.kind.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(colorFor(pattern))
                                    Text(pattern.kind.direction > 0 ? "看多反转" : "看空反转")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Text("bars [\(pattern.startIndex) → \(pattern.endIndex)]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.0f%%", pattern.confidence * 100))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(confidenceColor(pattern.confidence))
                                Text("置信度")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 480, height: 540)
    }

    private var sortedPatterns: [DetectedPattern] {
        patterns.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - v17.182 · 历史回测统计区

    private var statsSection: some View {
        let nonZero = stats.filter { $0.occurrenceCount > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.caption)
                Text("历史回测（后 20 根 close 变化均值 + 与方向一致胜率）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            if nonZero.isEmpty {
                Text("当前 K 线无足够后续数据计算回测（≥ 20 根 lookForward）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(nonZero, id: \.kind) { s in
                    statsRow(s)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func statsRow(_ s: PatternPerformanceStats) -> some View {
        let kindColor: Color = {
            if s.kind.direction == 0 { return .gray }
            return s.kind.direction > 0
                ? chartTheme.candleUp(mode: candleColorMode)
                : chartTheme.candleDown(mode: candleColorMode)
        }()
        return HStack(spacing: 6) {
            Image(systemName: s.kind.icon)
                .foregroundColor(kindColor)
                .font(.system(size: 10))
                .frame(width: 14)
            Text(s.kind.displayName)
                .font(.system(size: 11))
                .frame(width: 70, alignment: .leading)
            Text("\(s.occurrenceCount)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 30, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(String(format: "%+.2f%%", s.averagePriceChangePct))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
                .foregroundColor(s.averagePriceChangePct >= 0
                    ? chartTheme.candleUp(mode: candleColorMode)
                    : chartTheme.candleDown(mode: candleColorMode))
            Text(String(format: "%.0f%%", s.winRatePct))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(s.winRatePct >= 60 ? .green : (s.winRatePct >= 40 ? .orange : .red))
        }
    }

    private func colorFor(_ p: DetectedPattern) -> Color {
        p.kind.direction > 0
            ? chartTheme.candleUp(mode: candleColorMode)
            : chartTheme.candleDown(mode: candleColorMode)
    }

    /// confidence 配色：>0.75 绿 · 0.5-0.75 橙 · <0.5 灰
    private func confidenceColor(_ c: Double) -> Color {
        switch c {
        case 0.75...: return .green
        case 0.5..<0.75: return .orange
        default: return .secondary
        }
    }
}

#endif
