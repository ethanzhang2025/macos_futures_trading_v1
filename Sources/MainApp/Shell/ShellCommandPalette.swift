// MainApp · Shell · v17.2 · 全局命令面板（⌘+K · Bloomberg "GO" 现代化版）
// 国内国外首家 · TradingView 仅 symbol 搜索 · 我们是全局 command palette
//
// 候选源：合约 mock list / PrimaryTab 切换 / Workspace 切换 / 新建 Pane

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellCommandPalette: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    filteredCommands.isEmpty
                        ? AnyView(emptyState)
                        : AnyView(commandList)
                }
            }
        }
        .frame(width: 640, height: 480)
        .background(.regularMaterial)
        .onAppear { queryFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索合约 / 功能 / Workspace…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($queryFocused)
                .onSubmit { executeFirst() }
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var commandList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { _, cmd in
                commandRow(cmd)
            }
        }
        .padding(.vertical, 4)
    }

    private func commandRow(_ cmd: PaletteCommand) -> some View {
        Button {
            cmd.action()
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Text(cmd.emoji).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cmd.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    if let subtitle = cmd.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(cmd.category.label)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cmd.category.color.opacity(0.18))
                    .foregroundColor(cmd.category.color)
                    .cornerRadius(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { _ in }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🔍").font(.system(size: 32))
            Text("无匹配结果")
                .font(.callout).foregroundColor(.secondary)
            Text("试试：合约代码 / 模块名 / Workspace 名")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private func executeFirst() {
        if let first = filteredCommands.first {
            first.action()
            isPresented = false
        }
    }

    // MARK: - 候选汇集

    private var allCommands: [PaletteCommand] {
        var list: [PaletteCommand] = []

        // 一级模块切换
        for tab in PrimaryTab.allCases {
            list.append(PaletteCommand(
                title: "切到 \(tab.displayName)",
                subtitle: "⌘\(tab.shortcutNumber)",
                emoji: tab.emoji,
                category: .module,
                action: {
                    if shellVM.primaryTab != tab {
                        shellVM.primaryTab = tab
                        shellVM.activateFirstWorkspaceOfPrimaryTab()
                    }
                }
            ))
        }

        // Workspace 切换
        for ws in shellVM.workspaces {
            list.append(PaletteCommand(
                title: ws.name,
                subtitle: "\(ws.primaryTab.displayName) · \(ws.paneLayout.displayName) · \(ws.panes.count) Pane",
                emoji: ws.primaryTab.emoji,
                category: .workspace,
                action: { shellVM.activate(ws.id) }
            ))
        }

        // 合约 mock list（v17.x 接 WatchlistStore）
        for sym in mockSymbols {
            list.append(PaletteCommand(
                title: sym.symbol,
                subtitle: sym.name,
                emoji: "📊",
                category: .symbol,
                action: {
                    // 把 symbol 设到当前 active Pane（首个 chart Pane）
                    if let ws = shellVM.activeWorkspace,
                       let chartPane = ws.panes.first(where: { $0.kind == .chart }) {
                        shellVM.setPaneSymbol(paneID: chartPane.id, symbol: sym.symbol)
                    }
                }
            ))
        }

        // 新建 Pane（按 kind）
        let popularKinds: [PaneKind] = [.chart, .spread, .option, .review, .training, .formulaEditor]
        for kind in popularKinds {
            list.append(PaletteCommand(
                title: "新建 \(kind.displayName)",
                subtitle: "添加为当前 Workspace 的新 Pane",
                emoji: kind.emoji,
                category: .action,
                action: {
                    // v17.x · 加 ShellViewModel.addPaneToActiveWorkspace 实现
                }
            ))
        }

        return list
    }

    private var filteredCommands: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(allCommands.prefix(20)) }
        return allCommands.filter {
            $0.title.lowercased().contains(q)
                || ($0.subtitle?.lowercased().contains(q) ?? false)
        }
    }
}

// MARK: - Palette command model

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let emoji: String
    let category: Category
    let action: () -> Void

    enum Category {
        case module, workspace, symbol, action

        var label: String {
            switch self {
            case .module:    return "模块"
            case .workspace: return "Workspace"
            case .symbol:    return "合约"
            case .action:    return "操作"
            }
        }

        var color: Color {
            switch self {
            case .module:    return .accentColor
            case .workspace: return .purple
            case .symbol:    return .orange
            case .action:    return .green
            }
        }
    }
}

// MARK: - Mock 合约（v17.x 接 WatchlistStore）

private struct SymbolItem { let symbol: String; let name: String }
private let mockSymbols: [SymbolItem] = [
    SymbolItem(symbol: "rb2510", name: "螺纹钢 主力"),
    SymbolItem(symbol: "i2510",  name: "铁矿石 主力"),
    SymbolItem(symbol: "IF2509", name: "沪深300 主力"),
    SymbolItem(symbol: "IC2509", name: "中证500 主力"),
    SymbolItem(symbol: "IH2509", name: "上证50 主力"),
    SymbolItem(symbol: "ag2510", name: "白银 主力"),
    SymbolItem(symbol: "au2510", name: "黄金 主力"),
    SymbolItem(symbol: "MA2510", name: "甲醇 主力"),
    SymbolItem(symbol: "TA2510", name: "PTA 主力"),
    SymbolItem(symbol: "p2509",  name: "棕榈油 主力"),
    SymbolItem(symbol: "y2509",  name: "豆油 主力"),
    SymbolItem(symbol: "m2509",  name: "豆粕 主力"),
    SymbolItem(symbol: "c2509",  name: "玉米 主力"),
    SymbolItem(symbol: "cu2510", name: "沪铜 主力"),
    SymbolItem(symbol: "al2510", name: "沪铝 主力"),
]

#endif
