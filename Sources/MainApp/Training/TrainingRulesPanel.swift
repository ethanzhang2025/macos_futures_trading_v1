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
            Spacer()
            Button {
                showAdd = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .help("添加新规则")
            Menu {
                Button("一键导入 5 条推荐") { viewModel.importRecommended() }
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
                    Text(rule.kind.displayName)
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
            Button {
                editing = rule
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")
        }
        .opacity(rule.enabled ? 1.0 : 0.5)
        .padding(.vertical, 4)
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
                        Text(k.displayName).tag(k)
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
