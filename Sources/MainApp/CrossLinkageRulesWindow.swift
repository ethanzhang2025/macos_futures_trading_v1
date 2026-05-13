// v17.175 · 跨合约联动规则管理窗口（v17.172 闭环 UI）
//
// 布局：
//   顶部：规则列表（rules table · ruleID / trigger / kind / pct / watch / expectation / pct / enabled / delete）
//   中部：+ 新建规则 sheet（编辑器 · 8 字段表单）
//   底部：评估面板（trader 手填 instrument 快照 → 评估 → 显示 observation 列表）
//
// v1 评估输入手工录入（trader 看 watchlist 数字录进来）· v2 接 WatchlistWindow 自动喂 SinaQuote

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import DataCore

struct CrossLinkageRulesWindow: View {

    @State private var rules: CrossLinkageRules = .empty
    @State private var showEditor = false
    @State private var editingRule: CrossInstrumentLinkageRule?
    @State private var manualSnapshots: [String: ManualSnapshotEntry] = [:]
    @State private var observations: [CrossLinkageObservation] = []
    // v17.178 · Sina 实时 poll · 10s 定时自动拉取 + 评估
    @State private var autoPollEnabled: Bool = false
    @State private var pollTask: Task<Void, Never>?
    @State private var lastPollTime: Date?
    @State private var pollErrorMessage: String?

    private struct ManualSnapshotEntry: Equatable {
        var lastPrice: Double = 0
        var basePrice: Double = 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            rulesSection
                .frame(maxHeight: 240)
            Divider()
            snapshotSection
                .frame(maxHeight: 200)
            Divider()
            observationsSection
                .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 760)
        .onAppear { reload() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .sheet(isPresented: $showEditor) {
            CrossLinkageRuleEditorSheet(
                rule: editingRule ?? makeDefaultRule(),
                onSave: { newOrUpdated in
                    if editingRule != nil { rules.update(newOrUpdated) }
                    else { rules.add(newOrUpdated) }
                    CrossLinkageRulesStore.save(rules)
                    editingRule = nil
                }
            )
        }
    }

    // MARK: - sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("跨合约联动预警 · v17.172/175/178")
                    .font(.title2).bold()
                Spacer()
                Button {
                    editingRule = nil
                    showEditor = true
                } label: {
                    Label("新建规则", systemImage: "plus.circle.fill")
                }
                Button {
                    evaluate()
                } label: {
                    Label("评估当前快照", systemImage: "bolt.circle.fill")
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(rules.rules.isEmpty)
            }
            // v17.178 · Sina 实时 poll toggle + 状态显示
            HStack(spacing: 8) {
                Toggle(isOn: $autoPollEnabled) {
                    Label("Sina 实时（10s 自动评估）", systemImage: "antenna.radiowaves.left.and.right")
                }
                .toggleStyle(.switch)
                .disabled(rules.rules.isEmpty)
                .onChange(of: autoPollEnabled) { _, newVal in
                    if newVal { startPolling() } else { stopPolling() }
                }
                if let last = lastPollTime {
                    Text("上次：\(formatTime(last))")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                if let err = pollErrorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("规则列表（\(rules.rules.count)）").font(.headline)
            if rules.rules.isEmpty {
                Text("暂无规则 · 点击右上「新建规则」开始（如 RB 涨 3% 检查 HC 跟涨 1%）")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                Table(rules.rules) {
                    TableColumn("启用") { rule in
                        Toggle("", isOn: bindingForEnabled(rule))
                            .labelsHidden()
                    }
                    .width(50)
                    TableColumn("Trigger") { rule in Text(rule.triggerInstrument).font(.system(.body, design: .monospaced)) }
                    TableColumn("条件") { rule in
                        Text("\(rule.triggerKind.displayName) \(formatPct(rule.triggerThresholdPct))")
                    }
                    TableColumn("Watch") { rule in Text(rule.watchInstrument).font(.system(.body, design: .monospaced)) }
                    TableColumn("预期") { rule in
                        Text("\(rule.expectation.displayName) \(formatPct(rule.watchThresholdPct))")
                    }
                    TableColumn("操作") { rule in
                        HStack(spacing: 6) {
                            Button("编辑") {
                                editingRule = rule
                                showEditor = true
                            }
                            .buttonStyle(.borderless)
                            Button("删除", role: .destructive) {
                                rules.remove(ruleID: rule.ruleID)
                                CrossLinkageRulesStore.save(rules)
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }
                    .width(120)
                }
            }
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("快照输入（最新价 / 基准价 · 一般基准 = 昨结）").font(.headline)
                Spacer()
                Button("从规则自动填充") { autoFillSnapshots() }
                    .disabled(rules.rules.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(allInstruments(), id: \.self) { instr in
                        HStack(spacing: 8) {
                            Text(instr)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            TextField("最新价",
                                      value: bindingForSnapshot(instr).lastPrice,
                                      format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            TextField("基准价",
                                      value: bindingForSnapshot(instr).basePrice,
                                      format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("变动 \(formatChangePct(instr))")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var observationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("评估结果（\(observations.count)）").font(.headline)
                Spacer()
                Button("清除") { observations.removeAll() }
                    .disabled(observations.isEmpty)
            }
            if observations.isEmpty {
                Text("点击上方「评估当前快照」运行一次评估（⌘E）")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(observations.indices, id: \.self) { i in
                            observationRow(observations[i])
                        }
                    }
                }
            }
        }
    }

    private func observationRow(_ obs: CrossLinkageObservation) -> some View {
        let color: Color = {
            switch obs.verdict {
            case .matched:      return .green
            case .mismatched:   return .red
            case .notTriggered: return .secondary
            }
        }()
        let badge: String = {
            switch obs.verdict {
            case .matched:      return "✓ 符合"
            case .mismatched:   return "⚠ 套利机会"
            case .notTriggered: return "·  未触发"
            }
        }()
        return HStack(spacing: 8) {
            Text(badge)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color)
                .cornerRadius(3)
            Text(obs.ruleID).font(.caption.monospaced()).foregroundColor(.secondary)
            Text(obs.message).font(.caption)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - helpers

    private func reload() {
        rules = CrossLinkageRulesStore.load() ?? .empty
    }

    private func evaluate() {
        var snaps: [String: CrossLinkageSnapshot] = [:]
        for (instr, entry) in manualSnapshots {
            snaps[instr] = CrossLinkageSnapshot(
                instrument: instr, lastPrice: entry.lastPrice, basePrice: entry.basePrice
            )
        }
        observations = CrossInstrumentLinkage.evaluateAll(rules: rules.rules, snapshots: snaps)
    }

    private func autoFillSnapshots() {
        // 把规则里出现过的 instrument 都加入 manualSnapshots（已有的不覆盖）
        for instr in allInstruments() where manualSnapshots[instr] == nil {
            manualSnapshots[instr] = ManualSnapshotEntry(lastPrice: 0, basePrice: 0)
        }
    }

    private func allInstruments() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in rules.rules {
            for instr in [r.triggerInstrument, r.watchInstrument] {
                if seen.insert(instr).inserted { out.append(instr) }
            }
        }
        for instr in manualSnapshots.keys where seen.insert(instr).inserted { out.append(instr) }
        return out.sorted()
    }

    private func bindingForEnabled(_ rule: CrossInstrumentLinkageRule) -> Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { newVal in
                var copy = rule
                copy.enabled = newVal
                rules.update(copy)
                CrossLinkageRulesStore.save(rules)
            }
        )
    }

    private func bindingForSnapshot(_ instr: String) -> (lastPrice: Binding<Double>, basePrice: Binding<Double>) {
        let last = Binding<Double>(
            get: { manualSnapshots[instr]?.lastPrice ?? 0 },
            set: { newVal in
                var e = manualSnapshots[instr] ?? ManualSnapshotEntry()
                e.lastPrice = newVal
                manualSnapshots[instr] = e
            }
        )
        let base = Binding<Double>(
            get: { manualSnapshots[instr]?.basePrice ?? 0 },
            set: { newVal in
                var e = manualSnapshots[instr] ?? ManualSnapshotEntry()
                e.basePrice = newVal
                manualSnapshots[instr] = e
            }
        )
        return (last, base)
    }

    private func formatChangePct(_ instr: String) -> String {
        guard let e = manualSnapshots[instr], e.basePrice > 0 else { return "—" }
        let pct = (e.lastPrice - e.basePrice) / e.basePrice * 100
        return String(format: "%+.2f%%", pct)
    }

    private func formatPct(_ v: Double) -> String { String(format: "%.1f%%", v) }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - v17.178 · Sina 实时 poll

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            // 立即拉一次 · 不等 10s
            await pollSinaAndEvaluate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await pollSinaAndEvaluate()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @MainActor
    private func pollSinaAndEvaluate() async {
        let symbols = allInstruments()
        guard !symbols.isEmpty else {
            pollErrorMessage = "无规则 · 无合约可拉"
            return
        }
        let sina = SinaMarketData()
        do {
            let quotes = try await sina.fetchQuotes(symbols: symbols)
            var snaps: [String: CrossLinkageSnapshot] = [:]
            for q in quotes {
                // Sina API symbols 大写化 · 匹配回原 case
                let originalSym = symbols.first { $0.uppercased() == q.symbol.uppercased() } ?? q.symbol
                let last = NSDecimalNumber(decimal: q.lastPrice).doubleValue
                // base 优先 preSettlement · 缺失再回退 open · 都缺则跳过
                let baseDecimal = q.preSettlement != 0 ? q.preSettlement : q.open
                guard baseDecimal != 0 else { continue }
                let base = NSDecimalNumber(decimal: baseDecimal).doubleValue
                snaps[originalSym] = CrossLinkageSnapshot(
                    instrument: originalSym, lastPrice: last, basePrice: base
                )
                // 同步到 manualSnapshots · trader 在快照面板可见
                manualSnapshots[originalSym] = ManualSnapshotEntry(lastPrice: last, basePrice: base)
            }
            observations = CrossInstrumentLinkage.evaluateAll(rules: rules.rules, snapshots: snaps)
            lastPollTime = Date()
            pollErrorMessage = nil
        } catch {
            pollErrorMessage = "Sina 拉取失败：\(error)"
        }
    }

    private func makeDefaultRule() -> CrossInstrumentLinkageRule {
        CrossInstrumentLinkageRule(
            ruleID: rules.nextID(),
            triggerInstrument: "RB", triggerKind: .riseAtLeast, triggerThresholdPct: 3,
            watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1
        )
    }
}

// MARK: - 规则编辑器 sheet

struct CrossLinkageRuleEditorSheet: View {

    @State var rule: CrossInstrumentLinkageRule
    let onSave: (CrossInstrumentLinkageRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("联动规则编辑").font(.title2).bold()
            Form {
                Section("触发条件") {
                    TextField("触发合约", text: $rule.triggerInstrument)
                    Picker("条件类型", selection: $rule.triggerKind) {
                        ForEach(CrossLinkageTriggerKind.allCases, id: \.self) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    HStack {
                        Text("阈值百分比")
                        Spacer()
                        TextField("", value: $rule.triggerThresholdPct, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("%").foregroundColor(.secondary)
                    }
                }
                Section("Watch 合约 + 预期") {
                    TextField("Watch 合约", text: $rule.watchInstrument)
                    Picker("期望联动", selection: $rule.expectation) {
                        ForEach(CrossLinkageExpectation.allCases, id: \.self) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                    HStack {
                        Text("Watch 阈值")
                        Spacer()
                        TextField("", value: $rule.watchThresholdPct, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("%").foregroundColor(.secondary)
                    }
                }
                Section {
                    Toggle("启用规则", isOn: $rule.enabled)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { onSave(rule); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule.triggerInstrument.isEmpty || rule.watchInstrument.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}

#endif
