// v17.141 · 全工程快捷键速查 sheet
// 任何窗口按 ⌘⇧/ 通过 NotificationCenter 通知 ShellWindow 弹出本 sheet
// 顶部 Picker 切「全部 / 当前窗口」· 当前窗口由 menu 调用方传入（默认 .global = 全部）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

/// 触发本 sheet 的 NotificationCenter name · 全工程任何窗口可 post 触发
public extension Notification.Name {
    static let openGlobalShortcutsSheet = Notification.Name("v17141.openGlobalShortcutsSheet")
}

struct GlobalShortcutsHelpSheet: View {

    /// 起始作用域：全部 / 某具体窗口（默认全部）
    @State private var selectedScope: ScopeFilter
    @Environment(\.dismiss) private var dismiss

    init(initialScope: ShortcutWindowScope? = nil) {
        if let s = initialScope {
            _selectedScope = State(initialValue: .single(s))
        } else {
            _selectedScope = State(initialValue: .all)
        }
    }

    enum ScopeFilter: Hashable {
        case all
        case single(ShortcutWindowScope)

        var displayName: String {
            switch self {
            case .all: return "全部"
            case .single(let s): return s.displayName
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("⌨️ 全工程快捷键速查").font(.title3).bold()
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            // 作用域 Picker（"全部" + 每个 scope）
            Picker("范围", selection: $selectedScope) {
                Text("全部").tag(ScopeFilter.all)
                ForEach(ShortcutWindowScope.allCases) { s in
                    Text(s.displayName).tag(ScopeFilter.single(s))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredSections, id: \.scope) { section in
                        // 当不是单 scope 视图时显示 scope 大标题（区分不同窗口）
                        if case .all = selectedScope {
                            Text(section.scope.displayName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.top, 4)
                        }
                        ForEach(section.groups, id: \.title) { group in
                            Text(group.title)
                                .font(.headline)
                            ForEach(group.entries, id: \.key) { entry in
                                HStack(spacing: 16) {
                                    Text(entry.key)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 130, alignment: .leading)
                                    Text(entry.description)
                                        .font(.system(size: 12))
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
            }

            Divider()
            Text("⌘⇧/ 全局触发本浮窗 · Esc 关闭")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 580, height: 540)
    }

    private var filteredSections: [ShortcutSection] {
        switch selectedScope {
        case .all:
            return GlobalShortcutsCatalog.sections
        case .single(let s):
            return GlobalShortcutsCatalog.section(for: s).map { [$0] } ?? []
        }
    }
}

#endif
