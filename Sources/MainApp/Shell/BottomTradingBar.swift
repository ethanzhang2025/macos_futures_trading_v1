// MainApp · Shell · v17.0 PoC Step 7
// 底部交易区（期货软件核心特征 · 5 tab 常驻）
// Stage A 不接 CTP · v17.0 占位 · v17.1 接 SimulatedTradingEngine + TrainingViewModel

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct BottomTradingBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @State private var activeTab: BottomTab = .position

    enum BottomTab: String, CaseIterable, Identifiable {
        case position = "持仓"
        case order = "委托"
        case trade = "成交"
        case account = "资金"
        case rules = "训练规则"

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .position: return "💼"
            case .order:    return "📋"
            case .trade:    return "✓"
            case .account:  return "💰"
            case .rules:    return "🎯"
            }
        }

        var badge: String {
            switch self {
            case .position: return "0"
            case .order:    return "0"
            case .trade:    return "0"
            case .account:  return "¥100,000"
            case .rules:    return "6/6"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .frame(height: shellVM.layout.bottomBarCollapsed
               ? ShellMetrics.bottomBarCollapsedHeight
               : ShellMetrics.bottomBarHeight)
        .background(Color.secondary.opacity(0.04))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(BottomTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
            // 折叠 button
            Button {
                shellVM.layout.bottomBarCollapsed.toggle()
            } label: {
                Image(systemName: shellVM.layout.bottomBarCollapsed
                      ? "chevron.up"
                      : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help(shellVM.layout.bottomBarCollapsed ? "展开交易区" : "折叠交易区")
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
    }

    @ViewBuilder
    private func tabButton(_ tab: BottomTab) -> some View {
        let isActive = (activeTab == tab && !shellVM.layout.bottomBarCollapsed)
        Button {
            if shellVM.layout.bottomBarCollapsed {
                shellVM.layout.bottomBarCollapsed = false
            }
            activeTab = tab
        } label: {
            HStack(spacing: 3) {
                Text(tab.emoji).font(.system(size: 11))
                Text(tab.rawValue).font(.system(size: 11, weight: isActive ? .semibold : .regular))
                Text(tab.badge)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        if shellVM.layout.bottomBarCollapsed {
            EmptyView()
        } else {
            switch activeTab {
            case .position: positionPlaceholder
            case .order:    orderPlaceholder
            case .trade:    tradePlaceholder
            case .account:  accountPlaceholder
            case .rules:    rulesPlaceholder
            }
        }
    }

    private var positionPlaceholder: some View {
        emptyState("无持仓 · Stage A 不接 CTP · 后续接 SimulatedTradingEngine")
    }

    private var orderPlaceholder: some View {
        emptyState("无委托")
    }

    private var tradePlaceholder: some View {
        emptyState("无成交")
    }

    private var accountPlaceholder: some View {
        HStack(spacing: 24) {
            statCell(label: "总权益", value: "¥100,000")
            statCell(label: "可用",   value: "¥100,000")
            statCell(label: "占用",   value: "¥0")
            statCell(label: "风险度", value: "0.0%")
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var rulesPlaceholder: some View {
        HStack(spacing: 16) {
            Text("✓ 已启用 6 / 共 6 条规则 · 准备就绪")
                .font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text("打开 RulesPanel ⌘⇧T")
                .font(.caption2).foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func emptyState(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, design: .monospaced))
        }
    }
}

#endif
