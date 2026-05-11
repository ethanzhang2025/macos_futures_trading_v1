// MainApp · Shell · v17.0 PoC Step 3
// Pane 切分容器 · 按 PaneLayout 渲染 1/2/4/6/9 切分
// Pane 内嵌入 28 view 的真实实例（首期 ChartScene · 其他 Step 5 适配）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct PaneContainer: View {
    let workspace: Workspace

    var body: some View {
        switch workspace.paneLayout {
        case .single:
            paneAt(0)
        case .twoVertical:
            VSplitView {
                paneAt(0)
                paneAt(1)
            }
        case .twoHorizontal:
            HSplitView {
                paneAt(0)
                paneAt(1)
            }
        case .four:
            VSplitView {
                HSplitView {
                    paneAt(0)
                    paneAt(1)
                }
                HSplitView {
                    paneAt(2)
                    paneAt(3)
                }
            }
        case .sixGrid:
            VSplitView {
                HSplitView { paneAt(0); paneAt(1); paneAt(2) }
                HSplitView { paneAt(3); paneAt(4); paneAt(5) }
            }
        case .nineGrid:
            VSplitView {
                HSplitView { paneAt(0); paneAt(1); paneAt(2) }
                HSplitView { paneAt(3); paneAt(4); paneAt(5) }
                HSplitView { paneAt(6); paneAt(7); paneAt(8) }
            }
        case .custom:
            Text("自定义布局（v17.2+ 实装）")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func paneAt(_ idx: Int) -> some View {
        if idx < workspace.panes.count {
            PaneHost(config: workspace.panes[idx])
        } else {
            // 配置中缺少该 Pane · 显示占位
            VStack {
                Text("空 Pane #\(idx + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.04))
        }
    }
}

// MARK: - PaneHost · 单 Pane 容器（header + body）

struct PaneHost: View {
    let config: PaneConfig

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(config: config)
            PaneBody(config: config)
                .environment(\.isHostedInShell, true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - PaneHeader · 顶部 24pt（kind emoji + symbol + group chip + actions）

struct PaneHeader: View {
    let config: PaneConfig

    var body: some View {
        HStack(spacing: 6) {
            Text(config.kind.emoji).font(.system(size: 12))
            Text(config.kind.displayName)
                .font(.system(size: 11, weight: .medium))
            if let sym = config.symbol {
                Text("·").foregroundColor(.secondary).font(.system(size: 11))
                Text(sym)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            if let period = config.periodRaw {
                Text("·").foregroundColor(.secondary).font(.system(size: 11))
                Text(period)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let color = config.groupColor {
                Circle()
                    .fill(color.color)
                    .frame(width: 10, height: 10)
                    .help("\(color.displayName) · 联动")
            } else {
                // group 设定 button（占位 · v17.1 实装 popover 6 色选择）
                Button {
                    // v17.1 实装
                } label: {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .help("设为彩色 group（v17.1 实装）")
            }
            Button {
                // 分离窗口（v17.1 实装 NSWindow 桥接）
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("分离独立窗口（v17.1 实装）")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(Color.secondary.opacity(0.08))
    }
}

// MARK: - PaneBody · 按 PaneKind 实例化 view（v17.0 Step 5 · 全 20 类接入）

struct PaneBody: View {
    let config: PaneConfig

    var body: some View {
        switch config.kind {
        // 看盘类
        case .chart:              ChartScene()
        case .watchlist:          WatchlistWindow()
        case .sectorHeatmap:      SectorWindow()
        case .anomalyMonitor:     AnomalyMonitorWindow()
        case .multiChart:         placeholderFor(config.kind)  // MultiChartHost 需 host 参数 · Step 5+ 适配
        // 套利类
        case .spread:             SpreadWindow()
        case .calendarSpread:     CalendarSpreadWindow()
        case .spreadAlert:        SpreadAlertWindow()
        // 期权类
        case .option:             OptionWindow()
        case .optionBacktest:     placeholderFor(config.kind)  // Sheet · Step 5+ 包成 Window
        // 复盘类
        case .review:             ReviewWindow()
        case .journal:            JournalWindow()
        // 训练类
        case .training:           TrainingWindow()
        case .formulaEditor:      FormulaEditorWindow()
        // 工具类
        case .position:           PositionWindow()
        case .correlation:        CorrelationWindow()
        case .moneyFlow:          MoneyFlowWindow()
        case .heatmap:            HeatmapWindow()
        case .instrumentDashboard: InstrumentDashboardWindow()
        case .sessionCompare:     SessionCompareWindow()
        }
    }

    @ViewBuilder
    private func placeholderFor(_ kind: PaneKind) -> some View {
        VStack(spacing: 8) {
            Text(kind.emoji).font(.system(size: 40))
            Text(kind.displayName)
                .font(.title3.bold())
            Text("Step 5+ 适配（需特殊 init / host 参数）")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.04))
    }
}

#endif
