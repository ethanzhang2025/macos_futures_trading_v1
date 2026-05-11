// MainApp · WP-54 模拟训练 · 规则 CRUD Panel（v15.23 batch9 · M5）
//
// 职责：
// - 显示当前 book.rules 列表（5 类 kind · threshold · enabled toggle · note）
// - 添加规则（kind picker + threshold 输入 + note）
// - 编辑规则（同 sheet · 复用）
// - 删除规则
// - 一键导入 5 条推荐配置 / 清空所有规则
//
// 设计要点：
// - 顶部工具栏 + 中部 List + 底部空态时引导导入推荐
// - sheet 编辑表单（无 .formStyle 依赖 · 自定义 VStack）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import TradingCore

struct TrainingRulesPanel: View {

    @ObservedObject var viewModel: TrainingViewModel
    @State private var editing: DisciplineRule? = nil
    @State private var showAdd: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.book.rules.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .sheet(isPresented: $showAdd) {
            RuleEditSheet(rule: nil) { newRule in
                viewModel.addRule(newRule)
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditSheet(rule: rule) { updated in
                viewModel.updateRule(updated)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("📋 纪律规则")
                .font(.headline)
            Text("\(viewModel.book.rules.count) 条 · 启用 \(viewModel.book.enabledRules.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            // v16.44 · 当前模板 chip（与 v16.43 模板对比 · 不匹配显示"自定义"）
            currentTemplateChip
            Spacer()
            Button {
                showAdd = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .tooltip("添加新规则")
            Menu {
                // v16.43 · trader 风格规则模板（4 套预设 · 与 9 形态训练场景互补）
                Section("📋 规则模板（覆盖当前规则集）") {
                    Button("🎯 保守短线（默认推荐 · 5 条）") {
                        viewModel.applyRuleTemplate(.defaultRecommended)
                    }
                    .tooltip("止损 2% / 日内 60 分钟 / 加仓≤3 / 单日亏损 5000 / 单日交易 20 笔")
                    Button("⚡ 激进日内（高频抢反弹 · 5 条）") {
                        viewModel.applyRuleTemplate(.aggressiveIntraday)
                    }
                    .tooltip("止损 3% / 持仓 30 分钟 / 加仓≤5 / 单日亏损 8000 / 单日交易 50 笔")
                    Button("📈 波段持仓（隔夜 OK · 5 条）") {
                        viewModel.applyRuleTemplate(.swingHolding)
                    }
                    .tooltip("止损 5% / 持仓 3 天 / 加仓≤2 / 单日亏损 10000 / 单日交易 5 笔")
                    Button("🌱 极简纪律（入门 · 仅 2 条核心）") {
                        viewModel.applyRuleTemplate(.minimal)
                    }
                    .tooltip("止损 2% + 单日亏损 5000 · 不被规则淹没")
                }
                Divider()
                // v16.99 · trader 分享规则集（导出 JSON · 与团队共享自定义纪律）
                Section("📤 导入/导出（v16.99/106/121 · JSON + markdown）") {
                    Button {
                        copyRulesJSONToPasteboard()
                    } label: {
                        Label("复制规则集 JSON 到剪贴板", systemImage: "doc.on.doc")
                    }
                    .tooltip("v16.106 · 直接发 IM/微信分享 · 不必存文件")
                    Button {
                        copyRulesMarkdownToPasteboard()
                    } label: {
                        Label("复制规则集 Markdown 表格", systemImage: "tablecells")
                    }
                    .tooltip("v16.121 · 可读性优先 · 适合粘到笔记 / wiki / 邮件")
                    Button {
                        exportRulesJSON()
                    } label: {
                        Label("导出 JSON 为文件…", systemImage: "square.and.arrow.up")
                    }
                    .tooltip("trader 分享自定义规则集给团队 / 备份")
                    Button {
                        importRulesJSON()
                    } label: {
                        Label("导入规则集 JSON", systemImage: "square.and.arrow.down")
                    }
                    .tooltip("从 JSON 文件加载规则集 · 覆盖当前")
                    Button {
                        importRulesJSONFromPasteboard()
                    } label: {
                        Label("从剪贴板粘贴导入", systemImage: "doc.on.clipboard")
                    }
                    .tooltip("v16.106 · IM 收到 JSON 文本直接粘贴 · 不必存文件")
                }
                Divider()
                Button("清空所有规则", role: .destructive) { viewModel.clearRules() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - v16.99 · 规则集 JSON 导入/导出

    private func exportRulesJSON() {
        let panel = NSSavePanel()
        panel.title = L("导出规则集 JSON")
        panel.allowedContentTypes = [.json]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "纪律规则_\(dateFmt.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(viewModel.book) else {
            Toast.errorBody("导出失败", "JSON 编码失败")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            Toast.info("导出成功", "\(viewModel.book.rules.count) 条规则 · \(data.count) 字节")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    private func importRulesJSON() {
        let panel = NSOpenPanel()
        panel.title = L("导入规则集 JSON")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            Toast.errorBody("导入失败", "读取文件失败")
            return
        }
        guard let book = try? JSONDecoder().decode(DisciplineBook.self, from: data) else {
            Toast.errorBody("导入失败", "JSON 格式无效（需含 DisciplineBook 结构）")
            return
        }
        // v16.117 · 覆盖确认（防误操作丢失现有规则）
        guard confirmOverwriteRules(newCount: book.rules.count) else { return }
        viewModel.applyRuleTemplate(book)
        Toast.info("导入成功", "\(book.rules.count) 条规则 · 启用 \(book.enabledRules.count)")
    }

    // MARK: - v16.121 · markdown 表格（可读性优先 · 适合笔记/wiki/邮件）

    private func copyRulesMarkdownToPasteboard() {
        let book = viewModel.book
        var md = "# 纪律规则集（\(book.rules.count) 条 · 启用 \(book.enabledRules.count)）\n\n"
        if book.rules.isEmpty {
            md += "_暂无规则_\n"
        } else {
            md += "| 启用 | 类型 | 阈值 | 备注 |\n"
            md += "|------|------|------|------|\n"
            for rule in book.rules {
                let enabled = rule.enabled ? "✓" : "—"
                let thresholdStr = "\(NSDecimalNumber(decimal: rule.threshold).stringValue) \(rule.kind.thresholdUnit)"
                let note = rule.note.isEmpty ? "—" : rule.note
                md += "| \(enabled) | \(rule.kind.displayName) | \(thresholdStr) | \(note) |\n"
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        Toast.info("复制成功", "\(book.rules.count) 条规则 · markdown 表格 · 已粘到剪贴板")
    }

    // MARK: - v16.106 · 剪贴板版（不存文件直接 IM 分享）

    private func copyRulesJSONToPasteboard() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(viewModel.book),
              let str = String(data: data, encoding: .utf8) else {
            Toast.errorBody("复制失败", "JSON 编码失败")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(str, forType: .string)
        Toast.info("复制成功", "\(viewModel.book.rules.count) 条规则 · \(str.count) 字符 · 已粘到剪贴板")
    }

    private func importRulesJSONFromPasteboard() {
        guard let str = NSPasteboard.general.string(forType: .string),
              let data = str.data(using: .utf8) else {
            Toast.errorBody("导入失败", "剪贴板无文本")
            return
        }
        guard let book = try? JSONDecoder().decode(DisciplineBook.self, from: data) else {
            Toast.errorBody("导入失败", "剪贴板内容非有效 DisciplineBook JSON")
            return
        }
        // v16.117 · 覆盖确认
        guard confirmOverwriteRules(newCount: book.rules.count) else { return }
        viewModel.applyRuleTemplate(book)
        Toast.info("导入成功", "\(book.rules.count) 条规则 · 启用 \(book.enabledRules.count)")
    }

    /// v16.117 · 覆盖现有规则集 confirm（防误操作丢失数据）· 当前为空时直接 true
    private func confirmOverwriteRules(newCount: Int) -> Bool {
        let curCount = viewModel.book.rules.count
        guard curCount > 0 else { return true }   // 当前为空 → 无 confirm 必要
        let alert = NSAlert()
        alert.messageText = L("确认覆盖当前规则集？")
        alert.informativeText = L("当前有 \(curCount) 条规则将被新的 \(newCount) 条覆盖 · 此操作不可撤销")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("覆盖"))
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// v16.44 · 当前规则集匹配的模板（与 v16.43 4 套对比 · 不匹配 → "自定义"）
    @ViewBuilder
    private var currentTemplateChip: some View {
        let label = currentTemplateName
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
            .tooltip("当前规则集对应的模板（v16.43 · 4 套预设 · 修改后变 \"自定义\"）")
    }

    private var currentTemplateName: String {
        let book = viewModel.book
        if book == .defaultRecommended      { return "🎯 保守短线" }
        if book == .aggressiveIntraday      { return "⚡ 激进日内" }
        if book == .swingHolding            { return "📈 波段持仓" }
        if book == .minimal                 { return "🌱 极简纪律" }
        if book.rules.isEmpty               { return "（空）" }
        return "✏️ 自定义"
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("尚未配置任何纪律规则")
                .font(.title3)
            Text("一键导入 5 条推荐覆盖期货短线常见纪律")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("📥 导入推荐配置") {
                viewModel.importRecommended()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 列表

    private var list: some View {
        List {
            ForEach(viewModel.book.rules) { rule in
                ruleRow(rule)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("编辑") { editing = rule }
                        Button(rule.enabled ? "停用" : "启用") {
                            viewModel.setEnabled(id: rule.id, enabled: !rule.enabled)
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.removeRule(id: rule.id)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func ruleRow(_ rule: DisciplineRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { viewModel.setEnabled(id: rule.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L(rule.kind.displayName))
                        .font(.system(size: 13, weight: .medium))
                    Text("\(formatThreshold(rule.threshold)) \(rule.kind.thresholdUnit)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                if !rule.note.isEmpty {
                    Text(rule.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // v16.130 · 历史违规次数 badge（trader 看哪条规则违反最多 · 优先调阈值）
            violationCountBadge(for: rule.kind)
            Button {
                editing = rule
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .tooltip("编辑")
        }
        .opacity(rule.enabled ? 1.0 : 0.5)
        .padding(.vertical, 4)
    }

    /// v16.130 · 该 rule kind 的历史违规次数 badge
    /// 0 不显示 · 1 灰 · 2-4 橙 · 5+ 红 · trader 一眼看痛点规则
    /// v16.136 · tooltip 加最近 5 次违规 session 名（与 v16.135 HistoryPanel chip 同模式）
    @ViewBuilder
    private func violationCountBadge(for kind: DisciplineRuleKind) -> some View {
        let count = viewModel.log.sessions
            .flatMap { $0.violations }
            .filter { $0.ruleKind == kind }
            .count
        if count > 0 {
            let color: Color = {
                switch count {
                case 5...:  return .red
                case 2...:  return .orange
                default:    return .secondary
                }
            }()
            let recentNames = viewModel.log.sessions
                .filter { $0.violations.contains { $0.ruleKind == kind } }
                .sorted { $0.endedAt > $1.endedAt }
                .prefix(5)
                .map { $0.scenarioName.isEmpty ? "(未命名)" : $0.scenarioName }
            let tip: String = recentNames.isEmpty
                ? "历史违反该规则 \(count) 次"
                : "历史违反该规则 \(count) 次\n最近 \(recentNames.count) 次：\n" + recentNames.map { "· \($0)" }.joined(separator: "\n")
            Text("⚠️ \(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .cornerRadius(3)
                .tooltip(tip)
        }
    }

    private func formatThreshold(_ value: Decimal) -> String {
        let n = value as NSDecimalNumber
        let d = n.doubleValue
        if d == floor(d) {
            return String(format: "%.0f", d)
        }
        return String(format: "%.2f", d)
    }
}

// MARK: - 编辑 Sheet

private struct RuleEditSheet: View {

    let rule: DisciplineRule?
    let onSave: (DisciplineRule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: DisciplineRuleKind
    @State private var thresholdText: String
    @State private var enabled: Bool
    @State private var note: String

    init(rule: DisciplineRule?, onSave: @escaping (DisciplineRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        let defaultKind: DisciplineRuleKind = rule?.kind ?? .stopLossPercent
        _kind = State(initialValue: defaultKind)
        let thresholdValue = rule?.threshold ?? Self.defaultThreshold(for: defaultKind)
        _thresholdText = State(initialValue: Self.formatDecimal(thresholdValue))
        _enabled = State(initialValue: rule?.enabled ?? true)
        _note = State(initialValue: rule?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(rule == nil ? "添加纪律规则" : "编辑纪律规则")
                .font(.title3)
                .fontWeight(.semibold)

            // kind picker
            HStack {
                Text("类型").frame(width: 70, alignment: .leading)
                Picker("", selection: $kind) {
                    ForEach(DisciplineRuleKind.allCases, id: \.self) { k in
                        Text(L(k.displayName)).tag(k)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: kind) { newKind in
                    if rule == nil || rule?.kind != newKind {
                        thresholdText = Self.formatDecimal(Self.defaultThreshold(for: newKind))
                    }
                }
            }

            HStack {
                Text("阈值").frame(width: 70, alignment: .leading)
                TextField("", text: $thresholdText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text(kind.thresholdUnit)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("备注").frame(width: 70, alignment: .leading)
                TextField("可选 · 用途说明", text: $note)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("状态").frame(width: 70, alignment: .leading)
                Toggle("启用", isOn: $enabled)
                    .toggleStyle(.switch)
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(rule == nil ? "添加" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parsedThreshold == nil)
            }
        }
        .padding(20)
        .frame(width: 380, height: 240)
    }

    private var parsedThreshold: Decimal? {
        guard let d = Double(thresholdText.trimmingCharacters(in: .whitespaces)) else { return nil }
        guard d.isFinite, d >= 0 else { return nil }
        return Decimal(d)
    }

    private func save() {
        guard let threshold = parsedThreshold else { return }
        let saved: DisciplineRule
        if let existing = rule {
            saved = DisciplineRule(
                id: existing.id,
                kind: kind,
                threshold: threshold,
                enabled: enabled,
                note: note,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            saved = DisciplineRule(
                kind: kind,
                threshold: threshold,
                enabled: enabled,
                note: note
            )
        }
        onSave(saved)
        dismiss()
    }

    private static func defaultThreshold(for kind: DisciplineRuleKind) -> Decimal {
        switch kind {
        case .stopLossPercent:    return 2.0
        case .maxHoldingMinutes:  return 60
        case .maxAddPositions:    return 3
        case .dailyMaxLoss:       return 5000
        case .maxDailyTrades:     return 20
        }
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        let n = value as NSDecimalNumber
        let d = n.doubleValue
        if d == floor(d) { return String(format: "%.0f", d) }
        return String(format: "%.2f", d)
    }
}

#endif
