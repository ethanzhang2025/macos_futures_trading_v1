// MainApp · 工作区模板面板（WP-55 收官 + v1.5 拖拽 + v1.7 JSON 导入导出）
//
// 能力：NavigationSplitView 双栏 · 模板 CRUD + setActive · windows 增删改 + 6 网格预设
//      · 快捷键设置/修改/清除（A-Z + 0-9 字符 × ⌘⇧⌥⌃ modifier · 全局唯一 · 抢占提示）
//      · activate 时 NotificationCenter post .workspaceTemplateActivated（跨窗口联动）
//      · 同 Kind 内拖拽排序（跨 Kind 拒绝 · 通过 contextMenu「修改类型」改 kind · 同 WP-43 模式）
//      · JSON 导入/导出（NSSavePanel + NSOpenPanel · 整本 WorkspaceBook Codable · sortedKeys 稳定）
//
// 留待 M5：StoreManager 注入 SQLiteWorkspaceBookStore · 替换 Mock 真持久化
// 留待 M5：多窗口同时渲染（WP-44 + WP-40）+ CGRect 桥接 + 接收 .workspaceTemplateActivated
// 留待 A12 (M7-M9)：CloudKit 同步（CKContainer/CKSubscription/冲突合并）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Shared

// MARK: - Sheet 状态

private enum WorkspaceSheetState: Identifiable {
    case addTemplate
    case editTemplate(WorkspaceTemplate)
    case addWindow(template: WorkspaceTemplate)
    case editWindow(template: WorkspaceTemplate, index: Int)
    case applyGrid(template: WorkspaceTemplate)
    case editShortcut(template: WorkspaceTemplate)

    var id: String {
        switch self {
        case .addTemplate:                      return "add-template"
        case .editTemplate(let t):              return "edit-template-\(t.id)"
        case .addWindow(let t):                 return "add-window-\(t.id)"
        case .editWindow(let t, let i):         return "edit-window-\(t.id)-\(i)"
        case .applyGrid(let t):                 return "apply-grid-\(t.id)"
        case .editShortcut(let t):              return "edit-shortcut-\(t.id)"
        }
    }
}

// MARK: - 主窗口

struct WorkspaceWindow: View {

    @State private var book: WorkspaceBook = MockWorkspaceBook.generate()
    @State private var selectedTemplateID: UUID?
    @State private var sheetState: WorkspaceSheetState?
    @State private var pendingDeleteTemplate: WorkspaceTemplate?
    @State private var hoverTemplateID: UUID?
    @State private var pendingImportedBook: WorkspaceBook?
    @State private var importErrorMessage: String?

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
            case .addWindow(let template):
                WindowEditorSheet(mode: .add) { layout in
                    addWindow(layout, to: template)
                }
            case .editWindow(let template, let index):
                if template.windows.indices.contains(index) {
                    WindowEditorSheet(mode: .edit(layout: template.windows[index])) { layout in
                        updateWindow(at: index, to: layout, in: template)
                    }
                }
            case .applyGrid(let template):
                ApplyGridSheet(template: template) { preset in
                    applyGrid(preset, to: template)
                }
            case .editShortcut(let template):
                ShortcutEditorSheet(
                    template: template,
                    occupiedBy: { shortcut in book.template(forShortcut: shortcut) }
                ) { shortcut in
                    setShortcut(shortcut, for: template)
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
        .confirmationDialog(
            "导入工作区模板？",
            isPresented: importConfirmBinding,
            titleVisibility: .visible,
            presenting: pendingImportedBook
        ) { imported in
            Button("替换当前 \(book.templates.count) 个模板", role: .destructive) {
                applyImport(imported)
            }
            Button("取消", role: .cancel) {
                pendingImportedBook = nil
            }
        } message: { imported in
            Text("将用导入的 \(imported.templates.count) 个模板替换当前 \(book.templates.count) 个模板。该操作无法撤销。")
        }
        .alert(
            "操作失败",
            isPresented: importErrorBinding,
            presenting: importErrorMessage
        ) { _ in
            Button("好") { importErrorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTemplate != nil },
            set: { if !$0 { pendingDeleteTemplate = nil } }
        )
    }

    private var importConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingImportedBook != nil },
            set: { if !$0 { pendingImportedBook = nil } }
        )
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
    }

    // MARK: - 左栏 · 按 Kind 分组的模板列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("工作区模板").font(.headline)
                Spacer()
                Text("\(book.templates.count) 个")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    presentImportPanel()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("导入 JSON · 整本替换当前模板")
                Button {
                    presentExportPanel()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("导出 JSON · 当前 \(book.templates.count) 个模板")
                .disabled(book.templates.isEmpty)
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
        .overlay(alignment: .top) { insertionIndicator(for: template.id) }
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
        .draggable(WorkspaceTemplateRef(id: template.id, kind: template.kind)) {
            templateDragPreview(template)
        }
        .dropDestination(for: WorkspaceTemplateRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            return moveTemplate(ref, before: template)
        } isTargeted: { isOver in
            updateHover(template.id, active: isOver)
        }
    }

    /// 拖拽 hover 到行顶部时显示 2px 蓝色横线（同 WP-43 insertionIndicator 模式）
    private func insertionIndicator(for templateID: UUID) -> some View {
        let isActive = hoverTemplateID == templateID
        return Rectangle()
            .fill(Color.accentColor)
            .frame(height: isActive ? 2 : 0)
    }

    private func templateDragPreview(_ template: WorkspaceTemplate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .foregroundColor(.accentColor)
            Text(template.name)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            HStack {
                Button {
                    sheetState = .addWindow(template: template)
                } label: {
                    Label("添加窗口", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    sheetState = .applyGrid(template: template)
                } label: {
                    Label("应用网格预设", systemImage: "rectangle.split.2x2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(template.windows.isEmpty)
                .help("把当前 N 个窗口的 frame 替换为预设网格（不变合约/周期/指标）")
                Spacer()
            }
            .padding(.bottom, 4)

            if template.windows.isEmpty {
                Text("空模板 · 点击「添加窗口」开始 · 或先添加再应用网格预设")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(template.windows.enumerated()), id: \.element.id) { index, window in
                    windowRow(index: index, window: window, template: template)
                }
            }
        }
    }

    private func windowRow(index: Int, window: WindowLayout, template: WorkspaceTemplate) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            sheetState = .editWindow(template: template, index: index)
        }
        .contextMenu {
            Button("编辑窗口") {
                sheetState = .editWindow(template: template, index: index)
            }
            Divider()
            Button("删除窗口", role: .destructive) {
                removeWindow(at: index, from: template)
            }
        }
    }

    private func shortcutCard(_ template: WorkspaceTemplate) -> some View {
        infoCard("一键切换快捷键") {
            HStack {
                if let shortcut = template.shortcut {
                    Text(formatShortcut(shortcut))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer()
                    Button("修改") { sheetState = .editShortcut(template: template) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("清除", role: .destructive) { setShortcut(nil, for: template) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text("未绑定")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("设置快捷键") { sheetState = .editShortcut(template: template) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text("强制全局唯一 · 抢占其他模板的相同快捷键时会自动清空对方绑定")
                .font(.caption2)
                .foregroundColor(.secondary)
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
            Text("WP-55 收官 🎉")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.18))
                .foregroundColor(.green)
                .clipShape(Capsule())
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

    /// 快捷键展示：⌃⌥⇧⌘ + 单字符（如 ⌘K / ⌘⇧K）· keyCode 不在表中时回落到 hex
    private func formatShortcut(_ shortcut: WorkspaceShortcut) -> String {
        let prefix = ShortcutKey.symbolPrefix(for: shortcut.modifierFlags)
        let suffix = ShortcutKey.char(for: shortcut.keyCode)
            ?? "0x\(String(shortcut.keyCode, radix: 16))"
        return prefix + suffix
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

    /// 切换激活模板 · 同时通知主图（M5 多窗口实际渲染时接收 · v1 仅 stub）
    private func activate(_ template: WorkspaceTemplate) {
        book.setActive(id: template.id)
        NotificationCenter.default.post(
            name: .workspaceTemplateActivated,
            object: template.id.uuidString
        )
    }

    // MARK: - Mutations · 拖拽排序（v1.5 · 同 WP-43 模式）

    /// 拖拽模板到目标行前（同 Kind 内）· 跨 Kind 拒绝（用 contextMenu「修改类型」改 kind）
    /// 数据层 moveTemplate 是全局 templates 数组的 indices · normalizeSortIndices 保持连续
    @discardableResult
    private func moveTemplate(_ ref: WorkspaceTemplateRef, before target: WorkspaceTemplate) -> Bool {
        defer { hoverTemplateID = nil }
        guard ref.kind == target.kind else { return false }
        guard let from = book.templates.firstIndex(where: { $0.id == ref.id }),
              let targetIdx = book.templates.firstIndex(where: { $0.id == target.id }),
              let to = Self.resolveDropIndex(from: from, target: targetIdx)
        else { return false }
        return book.moveTemplate(from: from, to: to)
    }

    /// "落在 targetIndex 前"语义 → Array.move 风格的 (from, to) 转换（同 WP-43 resolveDropIndex）
    private static func resolveDropIndex(from: Int, target: Int) -> Int? {
        if target == from || target == from + 1 { return nil }
        return target > from ? target - 1 : target
    }

    private func updateHover(_ id: UUID, active: Bool) {
        if active {
            hoverTemplateID = id
        } else if hoverTemplateID == id {
            hoverTemplateID = nil
        }
    }

    // MARK: - JSON 导入 / 导出（v1.7 · NSSavePanel + NSOpenPanel · 与 WP-53 CSV 风格对称）

    /// 自定义 encoder：iso8601 日期 + sortedKeys（diff 友好）+ prettyPrinted（人读）
    /// 之所以不用 Workspaces module 内 JSONEncoder.cloudKit：那是 internal 不跨模块 · 这里独立配置
    private static let exportEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    private static let importDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "工作区模板-\(Self.filenameDate(Date())).json"
        panel.title = "导出工作区模板"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Self.exportEncoder.encode(book)
            try data.write(to: url)
        } catch {
            importErrorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择工作区模板 JSON 文件"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try Self.importDecoder.decode(WorkspaceBook.self, from: data)
            pendingImportedBook = imported
        } catch {
            importErrorMessage = "导入失败：JSON 格式不识别 · \(error.localizedDescription)"
        }
    }

    /// 用户在 confirmationDialog 确认后整本替换 · 选中切到导入的激活模板（或第一个）
    private func applyImport(_ imported: WorkspaceBook) {
        book = imported
        selectedTemplateID = imported.activeTemplateID ?? imported.templates.first?.id
        pendingImportedBook = nil
    }

    private static func filenameDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 设置/清除快捷键（数据层 setShortcut 强制全局唯一 · 抢占自动清空旧绑定）
    private func setShortcut(_ shortcut: WorkspaceShortcut?, for template: WorkspaceTemplate) {
        book.setShortcut(shortcut, for: template.id)
    }

    // MARK: - Mutations · windows 编辑

    /// windows 改动统一入口：取最新 template（避免 stale 引用）→ 跑 transform → updateTemplate 整体覆盖
    /// 之所以重新查 book.template(id:) 而不直接用入参 template：sheet 关闭时 book 可能已被其他操作改动
    private func updateWindows(of template: WorkspaceTemplate, transform: (inout [WindowLayout]) -> Void) {
        guard var fresh = book.template(id: template.id) else { return }
        transform(&fresh.windows)
        book.updateTemplate(fresh)
    }

    private func addWindow(_ layout: WindowLayout, to template: WorkspaceTemplate) {
        updateWindows(of: template) { $0.append(layout) }
    }

    private func updateWindow(at index: Int, to layout: WindowLayout, in template: WorkspaceTemplate) {
        updateWindows(of: template) { windows in
            guard windows.indices.contains(index) else { return }
            // 保留原 id（避免 ForEach diff 全量重渲染 + frame/zIndex 由网格预设决定，编辑时不动几何）
            var updated = layout
            updated.id = windows[index].id
            updated.frame = windows[index].frame
            updated.zIndex = windows[index].zIndex
            windows[index] = updated
        }
    }

    private func removeWindow(at index: Int, from template: WorkspaceTemplate) {
        updateWindows(of: template) { windows in
            guard windows.indices.contains(index) else { return }
            windows.remove(at: index)
        }
    }

    /// 网格预设应用：保留 instrumentID/period/indicatorIDs，仅替换 frame
    /// 多余的 windows 会被 WindowGridPreset.applyTo 截断（数据层语义）
    private func applyGrid(_ preset: WindowGridPreset, to template: WorkspaceTemplate) {
        updateWindows(of: template) { $0 = preset.applyTo($0) }
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

// MARK: - Sheet · 单窗口编辑（add / edit 共用）

private struct WindowEditorSheet: View {

    enum Mode {
        case add
        case edit(layout: WindowLayout)
    }

    let mode: Mode
    let onSubmit: (WindowLayout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instrumentID: String
    @State private var period: KLinePeriod
    @State private var indicatorIDsRaw: String

    init(mode: Mode, onSubmit: @escaping (WindowLayout) -> Void) {
        self.mode = mode
        self.onSubmit = onSubmit
        switch mode {
        case .add:
            self._instrumentID = State(initialValue: "")
            self._period = State(initialValue: .minute5)
            self._indicatorIDsRaw = State(initialValue: "")
        case .edit(let layout):
            self._instrumentID = State(initialValue: layout.instrumentID)
            self._period = State(initialValue: layout.period)
            self._indicatorIDsRaw = State(initialValue: layout.indicatorIDs.joined(separator: ", "))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()

            Form {
                TextField("合约代码（如 RB0 / IF0）", text: $instrumentID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)

                // PeriodSwitcher.default9Periods 与默认 ⌘1~9 快捷键映射对齐
                Picker("周期", selection: $period) {
                    ForEach(PeriodSwitcher.default9Periods, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)

                TextField("指标 IDs（逗号分隔 · 如 MA5, MA20, BOLL）", text: $indicatorIDsRaw)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)

                Text("commit 4 / M5 可加指标多选 UI · v1 用逗号分隔字符串简化")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) {
                    onSubmit(buildLayout())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    private var title: String {
        switch mode {
        case .add:  return "添加窗口"
        case .edit: return "编辑窗口"
        }
    }

    private var actionLabel: String {
        switch mode {
        case .add:  return "添加"
        case .edit: return "更新"
        }
    }

    private var canSubmit: Bool {
        instrumentID.trimmedOrNil != nil
    }

    /// 把 raw 字符串拆成 indicatorIDs 数组（trim · 大写 · 去空 · 去重保留顺序）
    private func buildLayout() -> WindowLayout {
        let id = instrumentID.trimmedOrNil?.uppercased() ?? ""
        let indicators = indicatorIDsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let dedup = indicators.filter { seen.insert($0).inserted }
        return WindowLayout(
            instrumentID: id,
            period: period,
            indicatorIDs: dedup
        )
    }
}

// MARK: - Sheet · 应用网格预设（6 张卡片）

private struct ApplyGridSheet: View {

    let template: WorkspaceTemplate
    let onApply: (WindowGridPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: WindowGridPreset?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用网格预设").font(.title2).bold()
            Text("当前 \(template.windows.count) 个窗口 · 选择网格后会按「先列后行」顺序填入 · 多余的窗口会被截断")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(WindowGridPreset.allCases, id: \.self) { preset in
                    gridCard(preset)
                }
            }

            HStack {
                if let sel = selected, sel.maxWindows < template.windows.count {
                    Label(
                        "应用后将截断 \(template.windows.count - sel.maxWindows) 个窗口",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("应用") {
                    if let sel = selected { onApply(sel) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }

    private func gridCard(_ preset: WindowGridPreset) -> some View {
        let isSelected = selected == preset
        return Button {
            selected = preset
        } label: {
            VStack(spacing: 8) {
                gridPreview(preset)
                    .frame(height: 64)
                Text(preset.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("最多 \(preset.maxWindows) 窗口")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    /// 网格 mini preview · 用 dimensions 直出格子 · 保持 4:3 视觉比例
    private func gridPreview(_ preset: WindowGridPreset) -> some View {
        let (rows, cols) = preset.dimensions
        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<cols, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .overlay(
                                Rectangle().stroke(Color.accentColor, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(4)
    }
}

fileprivate extension WindowGridPreset {
    var displayName: String {
        switch self {
        case .single:      return "单窗口"
        case .horizontal2: return "1×2 横排"
        case .vertical2:   return "2×1 竖排"
        case .grid2x2:     return "2×2 四宫"
        case .grid2x3:     return "2×3 六宫"
        case .grid3x2:     return "3×2 六宫"
        }
    }
}

// MARK: - 快捷键编码 · macOS Carbon keyCode 双向表

/// 字符 ↔ Carbon kVK_ANSI_X keyCode 双向映射（仅 A-Z + 0-9 · 已覆盖工作区切换典型场景）
/// keyCode 数值非连续（HID Usage 顺序）· 所以表格写死 · 不算"魔法数字"
fileprivate enum ShortcutKey {

    /// NSEvent.ModifierFlags rawValue 位掩码（与 PeriodSwitcher.commandModifier 同口径）
    static let commandMask: UInt32 = 0x100000   // .command  (1 << 20)
    static let shiftMask:   UInt32 = 0x020000   // .shift    (1 << 17)
    static let optionMask:  UInt32 = 0x080000   // .option   (1 << 19)
    static let controlMask: UInt32 = 0x040000   // .control  (1 << 18)

    static let charToKeyCode: [(char: String, keyCode: UInt16)] = [
        ("A", 0x00), ("B", 0x0B), ("C", 0x08), ("D", 0x02), ("E", 0x0E),
        ("F", 0x03), ("G", 0x05), ("H", 0x04), ("I", 0x22), ("J", 0x26),
        ("K", 0x28), ("L", 0x25), ("M", 0x2E), ("N", 0x2D), ("O", 0x1F),
        ("P", 0x23), ("Q", 0x0C), ("R", 0x0F), ("S", 0x01), ("T", 0x11),
        ("U", 0x20), ("V", 0x09), ("W", 0x0D), ("X", 0x07), ("Y", 0x10),
        ("Z", 0x06),
        ("0", 0x1D), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15),
        ("5", 0x17), ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19),
    ]

    private static let keyCodeToCharMap: [UInt16: String] = Dictionary(
        uniqueKeysWithValues: charToKeyCode.map { ($0.keyCode, $0.char) }
    )

    static func char(for keyCode: UInt16) -> String? {
        keyCodeToCharMap[keyCode]
    }

    static func keyCode(for char: String) -> UInt16? {
        charToKeyCode.first(where: { $0.char == char })?.keyCode
    }

    static var allChars: [String] {
        charToKeyCode.map { $0.char }
    }

    /// modifierFlags 位掩码 → ⌃⌥⇧⌘ 符号串（顺序与 Apple HIG 一致 · formatShortcut 与 previewString 共用）
    static func symbolPrefix(for modifierFlags: UInt32) -> String {
        var s = ""
        if modifierFlags & controlMask != 0 { s += "⌃" }
        if modifierFlags & optionMask  != 0 { s += "⌥" }
        if modifierFlags & shiftMask   != 0 { s += "⇧" }
        if modifierFlags & commandMask != 0 { s += "⌘" }
        return s
    }
}

// MARK: - Sheet · 快捷键编辑（设置 / 修改 · 字符 + 4 modifier）

private struct ShortcutEditorSheet: View {

    let template: WorkspaceTemplate
    /// 检查给定 shortcut 是否被其他模板占用（命中则提示"会抢占"）
    let occupiedBy: (WorkspaceShortcut) -> WorkspaceTemplate?
    let onApply: (WorkspaceShortcut) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedChar: String
    @State private var commandOn: Bool
    @State private var shiftOn:   Bool
    @State private var optionOn:  Bool
    @State private var controlOn: Bool

    init(
        template: WorkspaceTemplate,
        occupiedBy: @escaping (WorkspaceShortcut) -> WorkspaceTemplate?,
        onApply: @escaping (WorkspaceShortcut) -> Void
    ) {
        self.template = template
        self.occupiedBy = occupiedBy
        self.onApply = onApply

        let initial = template.shortcut
        let initialChar = initial.flatMap { ShortcutKey.char(for: $0.keyCode) } ?? "K"
        let initialMods = initial?.modifierFlags ?? ShortcutKey.commandMask

        self._selectedChar = State(initialValue: initialChar)
        self._commandOn = State(initialValue: initialMods & ShortcutKey.commandMask != 0)
        self._shiftOn   = State(initialValue: initialMods & ShortcutKey.shiftMask   != 0)
        self._optionOn  = State(initialValue: initialMods & ShortcutKey.optionMask  != 0)
        self._controlOn = State(initialValue: initialMods & ShortcutKey.controlMask != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置快捷键 · 「\(template.name)」").font(.title2).bold()

            Form {
                LabeledContent("修饰键") {
                    HStack(spacing: 8) {
                        Toggle("⌘", isOn: $commandOn)
                        Toggle("⇧", isOn: $shiftOn)
                        Toggle("⌥", isOn: $optionOn)
                        Toggle("⌃", isOn: $controlOn)
                    }
                    .toggleStyle(.button)
                }

                Picker("按键", selection: $selectedChar) {
                    ForEach(ShortcutKey.allChars, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("预览") {
                    Text(previewString)
                        .font(.system(.title3, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                if let occupant = occupiedTemplate {
                    Label(
                        "该快捷键当前由「\(occupant.name)」占用 · 应用后将自动从对方清除（数据层强制全局唯一）",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("应用") {
                    if let s = buildShortcut() {
                        onApply(s)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }

    /// 至少需要一个修饰键（避免裸字符快捷键劫持普通输入）
    private var canSubmit: Bool {
        commandOn || shiftOn || optionOn || controlOn
    }

    private var modifierFlags: UInt32 {
        var flags: UInt32 = 0
        if commandOn { flags |= ShortcutKey.commandMask }
        if shiftOn   { flags |= ShortcutKey.shiftMask }
        if optionOn  { flags |= ShortcutKey.optionMask }
        if controlOn { flags |= ShortcutKey.controlMask }
        return flags
    }

    private func buildShortcut() -> WorkspaceShortcut? {
        guard let keyCode = ShortcutKey.keyCode(for: selectedChar) else { return nil }
        return WorkspaceShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    private var previewString: String {
        ShortcutKey.symbolPrefix(for: modifierFlags) + selectedChar
    }

    /// 抢占检查：拿到当前预览中的 shortcut 是否被另一模板占用（不是当前 template 自己）
    private var occupiedTemplate: WorkspaceTemplate? {
        guard canSubmit, let s = buildShortcut() else { return nil }
        guard let occupant = occupiedBy(s) else { return nil }
        return occupant.id == template.id ? nil : occupant
    }
}

// MARK: - Notification.Name · 跨窗口联动

extension Notification.Name {
    /// WP-55 commit 4 · WorkspaceWindow 切换激活 → 主图/多窗口接收切换布局（object: templateID String）
    /// M5 多窗口实际渲染时接收 + frame 桥接 CGRect · v1 仅 stub
    static let workspaceTemplateActivated = Notification.Name("workspaceTemplateActivated")
}

// MARK: - Transferable 拖拽载荷（WP-55 v1.5）

private struct WorkspaceTemplateRef: Codable, Hashable, Transferable {
    let id: UUID
    let kind: WorkspaceTemplate.Kind   // 跨 Kind 拒绝判定用
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
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

        // commit 4 · 演示快捷键效果：盘中主交易 ⌘⇧1 · 盘后复盘 ⌘⇧2 · 让 sidebar 行 ⌘ icon 立即可见
        if book.templates.count >= 3,
           let key1 = ShortcutKey.keyCode(for: "1"),
           let key2 = ShortcutKey.keyCode(for: "2") {
            let cmdShift = ShortcutKey.commandMask | ShortcutKey.shiftMask
            book.setShortcut(WorkspaceShortcut(keyCode: key1, modifierFlags: cmdShift), for: book.templates[1].id)
            book.setShortcut(WorkspaceShortcut(keyCode: key2, modifierFlags: cmdShift), for: book.templates[2].id)
        }

        return book
    }
}

#endif
