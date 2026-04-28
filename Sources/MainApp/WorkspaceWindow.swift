// MainApp · 工作区模板面板（WP-55 UI · commit 2/4 · CRUD + 切换激活）
//
// commit 1 已交付：NavigationSplitView 双栏 · WorkspaceBook 真模型 · Mock 4 模板（每 Kind 各 1）
// commit 2 本次新增：
// - 顶部 "+" 按钮（⌘⇧K · 添加模板 sheet）
// - 行 contextMenu：重命名 / 复制（duplicateTemplate）/ 删除（destructive）
// - 删除前 confirmationDialog（含级联清空 N 窗口警示）
// - TemplateEditorSheet（add/edit 共用 · 字段 name + Kind picker · 4 类预设）
// - detail header "设为当前激活"按钮（非激活时显示 · 双击 sidebar 行同效）
// - 操作 helper：addTemplate / renameAndRekind / duplicateTemplate / deleteTemplate / activate
//
// 留待 commit 3/4：网格预设 6 卡片 + windows 列表编辑（合约/周期/指标 picker）
// 留待 commit 4/4：快捷键编辑器（CommandRecorder）+ 全局唯一性 + 主图联动 stub
//
// 留待 M5：StoreManager 注入 SQLiteWorkspaceBookStore · 替换 Mock 真持久化数据

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared

// MARK: - Sheet 状态

private enum WorkspaceSheetState: Identifiable {
    case addTemplate
    case editTemplate(WorkspaceTemplate)

    var id: String {
        switch self {
        case .addTemplate:        return "add-template"
        case .editTemplate(let t): return "edit-template-\(t.id)"
        }
    }
}

// MARK: - 主窗口

struct WorkspaceWindow: View {

    @State private var book: WorkspaceBook = MockWorkspaceBook.generate()
    @State private var selectedTemplateID: UUID?
    @State private var sheetState: WorkspaceSheetState?
    @State private var pendingDeleteTemplate: WorkspaceTemplate?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 520, idealHeight: 640)
        .animation(.easeInOut(duration: 0.22), value: book)
        .onAppear {
            if selectedTemplateID == nil {
                selectedTemplateID = book.activeTemplateID ?? book.templates.first?.id
            }
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .addTemplate:
                TemplateEditorSheet(mode: .add) { name, kind in
                    addTemplate(name: name, kind: kind)
                }
            case .editTemplate(let template):
                TemplateEditorSheet(mode: .edit(template: template)) { name, kind in
                    renameAndRekind(template, name: name, kind: kind)
                }
            }
        }
        .confirmationDialog(
            "删除模板？",
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible,
            presenting: pendingDeleteTemplate
        ) { template in
            Button("删除「\(template.name)」", role: .destructive) {
                deleteTemplate(template)
            }
            Button("取消", role: .cancel) {
                pendingDeleteTemplate = nil
            }
        } message: { template in
            Text("模板「\(template.name)」内的 \(template.windows.count) 个窗口布局将一并清空。该操作无法撤销。")
        }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTemplate != nil },
            set: { if !$0 { pendingDeleteTemplate = nil } }
        )
    }

    // MARK: - 左栏 · 按 Kind 分组的模板列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作区模板").font(.headline)
                Spacer()
                Text("\(book.templates.count) 个")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    sheetState = .addTemplate
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加模板（⌘⇧K）")
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $selectedTemplateID) {
                ForEach(WorkspaceTemplate.Kind.allCases, id: \.self) { kind in
                    let templates = book.templates(of: kind)
                    if !templates.isEmpty {
                        Section(kind.displayName) {
                            ForEach(templates) { template in
                                templateRow(template)
                                    .tag(template.id as UUID?)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func templateRow(_ template: WorkspaceTemplate) -> some View {
        let isActive = book.activeTemplateID == template.id
        return HStack(spacing: 8) {
            Image(systemName: isActive ? "star.fill" : "rectangle.stack")
                .foregroundColor(isActive ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .fontWeight(isActive ? .semibold : .regular)
                HStack(spacing: 4) {
                    Text("\(template.windows.count) 窗口")
                    if template.shortcut != nil {
                        Text("·")
                        Image(systemName: "command.circle")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            activate(template)
        }
        .contextMenu {
            Button("重命名 / 修改类型") {
                sheetState = .editTemplate(template)
            }
            Button("复制为副本") {
                duplicateTemplate(template)
            }
            if !isActive {
                Divider()
                Button("设为当前激活") {
                    activate(template)
                }
            }
            Divider()
            Button("删除模板", role: .destructive) {
                pendingDeleteTemplate = template
            }
        }
    }

    // MARK: - 右栏 · 模板详情

    @ViewBuilder
    private var detail: some View {
        if let id = selectedTemplateID, let template = book.template(id: id) {
            templateDetail(template)
        } else {
            emptyState(
                icon: "rectangle.stack",
                title: "未选择模板",
                hint: "在左侧选择一个工作区模板查看详情"
            )
        }
    }

    private func templateDetail(_ template: WorkspaceTemplate) -> some View {
        let isActive = book.activeTemplateID == template.id
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(template.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(template.kind.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(template.kind.color.opacity(0.18))
                    .foregroundColor(template.kind.color)
                    .clipShape(Capsule())
                Spacer()
                if isActive {
                    Label("当前激活", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Button {
                        activate(template)
                    } label: {
                        Label("设为当前激活", systemImage: "star")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("把此模板标为当前激活（双击 sidebar 行同效）")
                }
            }
            .padding(20)

            Divider()

            // Body · 信息卡片
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    windowsCard(template)
                    shortcutCard(template)
                }
                .padding(20)
            }

            Divider()
            footerHint
        }
    }

    private func windowsCard(_ template: WorkspaceTemplate) -> some View {
        infoCard("窗口布局（\(template.windows.count) 个）") {
            if template.windows.isEmpty {
                Text("空模板 · 暂无窗口（commit 3 加网格预设可一键生成）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(template.windows.enumerated()), id: \.element.id) { index, window in
                    windowRow(index: index, window: window)
                }
            }
        }
    }

    private func windowRow(index: Int, window: WindowLayout) -> some View {
        HStack(spacing: 0) {
            Text("窗口 \(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(window.instrumentID)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            Text(window.period.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            if window.indicatorIDs.isEmpty {
                Text("无指标")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                Text(window.indicatorIDs.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func shortcutCard(_ template: WorkspaceTemplate) -> some View {
        infoCard("一键切换快捷键") {
            if let shortcut = template.shortcut {
                Text(formatShortcut(shortcut))
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("未绑定 · commit 4 加快捷键编辑器（CommandRecorder）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
    }

    private var footerHint: some View {
        HStack(spacing: 8) {
            if let active = book.activeTemplate {
                Image(systemName: "star.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("当前激活：\(active.name)")
                    .font(.caption2)
            } else {
                Text("未设置激活模板")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("commit 2/4 · CRUD + 切换激活 · 网格 + 编辑 待 commit 3")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title).font(.title3).foregroundColor(.secondary)
            Text(hint).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 显示辅助

    /// 快捷键展示（commit 1 仅显示 keyCode/modifiers · commit 4 完整 Carbon → 字符映射）
    private func formatShortcut(_ shortcut: WorkspaceShortcut) -> String {
        "keyCode \(shortcut.keyCode) · modifiers 0x\(String(shortcut.modifierFlags, radix: 16))"
    }

    // MARK: - Mutations · CRUD + 激活切换

    private func addTemplate(name: String, kind: WorkspaceTemplate.Kind) {
        guard let trimmed = name.trimmedOrNil else { return }
        let template = book.addTemplate(name: trimmed, kind: kind)
        selectedTemplateID = template.id
    }

    /// 数据层 renameTemplate 只改 name；要改 kind 必须走 updateTemplate（保留 id/sortIndex/createdAt）
    /// 无变更短路由 sheet 的 canSubmit 拦截（edit 模式 disabled 按钮）
    private func renameAndRekind(_ template: WorkspaceTemplate, name: String, kind: WorkspaceTemplate.Kind) {
        guard let trimmed = name.trimmedOrNil else { return }
        var updated = template
        updated.name = trimmed
        updated.kind = kind
        book.updateTemplate(updated)
    }

    private func duplicateTemplate(_ template: WorkspaceTemplate) {
        guard let copy = book.duplicateTemplate(id: template.id) else { return }
        selectedTemplateID = copy.id
    }

    private func deleteTemplate(_ template: WorkspaceTemplate) {
        let wasSelected = selectedTemplateID == template.id
        book.removeTemplate(id: template.id)
        if wasSelected {
            selectedTemplateID = book.activeTemplateID ?? book.templates.first?.id
        }
        pendingDeleteTemplate = nil
    }

    private func activate(_ template: WorkspaceTemplate) {
        book.setActive(id: template.id)
    }
}

// MARK: - 显示辅助 extension（与 JournalEmotion / JournalDeviation 同模式）

fileprivate extension WorkspaceTemplate.Kind {
    var displayName: String {
        switch self {
        case .preMarket:  return "盘前"
        case .inMarket:   return "盘中"
        case .postMarket: return "盘后"
        case .custom:     return "自定义"
        }
    }

    var color: Color {
        switch self {
        case .preMarket:  return .orange
        case .inMarket:   return .red
        case .postMarket: return .blue
        case .custom:     return .gray
        }
    }
}

// MARK: - String 私有扩展

private extension String {
    /// 去前后空白后返回；若为空返回 nil
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Sheet · 模板编辑（add / edit 共用）

private struct TemplateEditorSheet: View {

    enum Mode {
        case add
        case edit(template: WorkspaceTemplate)
    }

    let mode: Mode
    let onSubmit: (String, WorkspaceTemplate.Kind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: WorkspaceTemplate.Kind

    init(mode: Mode, onSubmit: @escaping (String, WorkspaceTemplate.Kind) -> Void) {
        self.mode = mode
        self.onSubmit = onSubmit
        switch mode {
        case .add:
            self._name = State(initialValue: "")
            self._kind = State(initialValue: .custom)
        case .edit(let template):
            self._name = State(initialValue: template.name)
            self._kind = State(initialValue: template.kind)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()

            Form {
                TextField("模板名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)

                Picker("类型", selection: $kind) {
                    ForEach(WorkspaceTemplate.Kind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                Text("4 类预设：盘前刷新自选 / 盘中主交易 / 盘后复盘 / 自定义临时模板")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) {
                    onSubmit(name, kind)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
    }

    private var title: String {
        switch mode {
        case .add:  return "添加工作区模板"
        case .edit: return "编辑模板"
        }
    }

    private var actionLabel: String {
        switch mode {
        case .add:  return "保存"
        case .edit: return "更新"
        }
    }

    /// add 模式必须有名字；edit 模式必须有名字且与原值不同（任一字段变更）
    private var canSubmit: Bool {
        guard let trimmed = name.trimmedOrNil else { return false }
        switch mode {
        case .add:
            return true
        case .edit(let template):
            return trimmed != template.name || kind != template.kind
        }
    }
}

// MARK: - Mock 数据（commit 1 静态 · M5 替换 SQLiteWorkspaceBookStore）

private enum MockWorkspaceBook {
    /// 4 模板 · 每 Kind 各 1 · 含示例 windows
    /// 主力 RB0/IF0/AU0 ∈ MarketDataPipeline.supportedContracts · 后续主图联动可生效
    static func generate() -> WorkspaceBook {
        var book = WorkspaceBook()
        let now = Date()

        // 盘前看大盘（1 全屏窗口 · IF0 60min · 隔夜分析）
        book.addTemplate(
            name: "盘前看大盘",
            kind: .preMarket,
            windows: [
                WindowLayout(
                    instrumentID: "IF0",
                    period: .hour1,
                    indicatorIDs: ["MA20", "MA60"],
                    frame: LayoutFrame(x: 0, y: 0, width: 1, height: 1)
                )
            ],
            now: now
        )

        // 盘中主交易（4 windows · 2x2 grid · RB0 主战场）
        book.addTemplate(
            name: "盘中主交易",
            kind: .inMarket,
            windows: WindowGridPreset.grid2x2.applyTo([
                WindowLayout(instrumentID: "RB0", period: .minute5, indicatorIDs: ["MA5", "MA20", "BOLL"]),
                WindowLayout(instrumentID: "RB0", period: .hour1,   indicatorIDs: ["MA20", "MA60"]),
                WindowLayout(instrumentID: "IF0", period: .minute5, indicatorIDs: ["MA20"]),
                WindowLayout(instrumentID: "AU0", period: .minute5, indicatorIDs: ["MA20"]),
            ]),
            now: now
        )

        // 盘后复盘（2 windows · vertical · 日线）
        book.addTemplate(
            name: "盘后复盘",
            kind: .postMarket,
            windows: WindowGridPreset.vertical2.applyTo([
                WindowLayout(instrumentID: "RB0", period: .daily, indicatorIDs: ["MA20", "MA60", "BOLL", "MACD"]),
                WindowLayout(instrumentID: "AU0", period: .daily, indicatorIDs: ["MA20", "MA60"]),
            ]),
            now: now
        )

        // 自定义（空模板 · 演示空 state · commit 3 用网格预设填充）
        book.addTemplate(
            name: "自定义模板 1",
            kind: .custom,
            now: now
        )

        // 默认激活"盘中主交易"（最常用 · 不依赖 init 时 first auto-active 的副作用）
        if book.templates.count >= 2 {
            book.setActive(id: book.templates[1].id)
        }

        return book
    }
}

#endif
