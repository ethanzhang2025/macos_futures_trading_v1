// MainApp · Shell · v17.0 PoC Step 7
// 底部交易区（期货软件核心特征 · 5 tab 常驻）
// Stage A 不接 CTP · v17.24 接 SimulatedTradingStore 真实数据（position/order/trade/account）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import Shared
import TradingCore

struct BottomTradingBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @State private var activeTab: BottomTab = .position
    /// v17.24 · 模拟交易 snapshot · 与 Sidebar 同步（UserDefaults didChange）
    @State private var tradingSnapshot: SimulatedTradingSnapshot? = SimulatedTradingStore.load()

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

    }

    private func badge(_ tab: BottomTab) -> String {
        guard let snap = tradingSnapshot else {
            switch tab {
            case .account: return "¥100,000"
            case .rules:   return "6/6"
            default:       return "0"
            }
        }
        switch tab {
        case .position: return "\(snap.positions.count)"
        case .order:    return "\(snap.orders.count)"
        case .trade:    return "\(snap.trades.count)"
        case .account:
            let bal = NSDecimalNumber(decimal: snap.account.balance).doubleValue
            return String(format: "¥%.0f", bal)
        case .rules:    return "6/6"
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
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if let snap = SimulatedTradingStore.load() { tradingSnapshot = snap }
        }
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
                Text(badge(tab))
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
        Group {
            if let snap = tradingSnapshot, !snap.positions.isEmpty {
                positionList(snap)
            } else {
                emptyState("无持仓 · TradingWindow ⌘T 模拟开仓")
            }
        }
    }

    @ViewBuilder
    private func positionList(_ snap: SimulatedTradingSnapshot) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(snap.positions, id: \.instrumentID) { pos in
                    let last = snap.instrumentLastPrice[pos.instrumentID] ?? pos.avgPrice
                    let pnl = NSDecimalNumber(decimal: pos.floatingPnL(currentPrice: last)).doubleValue
                    HStack(spacing: 12) {
                        Text(pos.instrumentID).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .leading)
                        Text(pos.direction.displayName)
                            .font(.system(size: 10))
                            .padding(.horizontal, 4)
                            .background((pos.direction == .long ? Color.red : Color.green).opacity(0.2))
                            .cornerRadius(2)
                        Text("\(pos.volume)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
                        let avg = NSDecimalNumber(decimal: pos.avgPrice).doubleValue
                        let lastVal = NSDecimalNumber(decimal: last).doubleValue
                        Text(String(format: "%.2f", avg)).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).frame(width: 64, alignment: .trailing)
                        Text(String(format: "%.2f", lastVal)).font(.system(size: 11, design: .monospaced)).frame(width: 64, alignment: .trailing)
                        Text(String(format: "%@¥%.0f", pnl >= 0 ? "+" : "", pnl))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(pnl >= 0 ? .red : .green)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
        }
    }

    private var orderPlaceholder: some View {
        if let count = tradingSnapshot?.orders.count, count > 0 {
            return AnyView(emptyState("\(count) 笔委托（详情见 TradingWindow ⌘T）"))
        }
        return AnyView(emptyState("无委托"))
    }

    private var tradePlaceholder: some View {
        if let count = tradingSnapshot?.trades.count, count > 0 {
            return AnyView(emptyState("\(count) 笔成交（详情见 TradingWindow ⌘T）"))
        }
        return AnyView(emptyState("无成交"))
    }

    private var accountPlaceholder: some View {
        let snap = tradingSnapshot
        let balance = snap.map { NSDecimalNumber(decimal: $0.account.balance).doubleValue } ?? 100_000
        let available = snap.map { NSDecimalNumber(decimal: $0.account.available).doubleValue } ?? 100_000
        let margin = snap.map { NSDecimalNumber(decimal: $0.account.margin).doubleValue } ?? 0
        let riskPct = snap.map { NSDecimalNumber(decimal: $0.account.riskRatio).doubleValue } ?? 0
        return HStack(spacing: 24) {
            statCell(label: "总权益", value: String(format: "¥%.0f", balance))
            statCell(label: "可用",   value: String(format: "¥%.0f", available))
            statCell(label: "占用",   value: String(format: "¥%.0f", margin))
            statCell(label: "风险度", value: String(format: "%.1f%%", riskPct), valueColor: riskPct > 50 ? .red : (riskPct > 20 ? .orange : .primary))
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

    private func statCell(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundColor(valueColor)
        }
    }
}

#endif
