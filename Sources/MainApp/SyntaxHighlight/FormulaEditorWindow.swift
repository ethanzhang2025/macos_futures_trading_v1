// WP-65 v15.22 batch4 · 麦语言公式编辑器窗口
// toolbar（打开 / 保存 / 主题）+ MaiLangCodeView 主编辑区 + status bar

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import Shared
import IndicatorCore

public struct FormulaEditorWindow: View {

    /// v15.22 batch4 · @AppStorage 持久化最近编辑文本（窗口关闭重开保留 · trader 多次迭代不丢）
    @AppStorage("viewState.v1.formulaEditor.text") private var sourceText: String =
        """
        { 在此输入麦语言公式 · 例如：}

        MA5:=MA(CLOSE,5);
        MA20:=MA(CLOSE,20);

        {绘图属性示例：}
        VOL:VOLUME,COLORRED,LINETHICK2;
        """

    @AppStorage("viewState.v1.formulaEditor.schemeRaw") private var schemeRaw: String = "dark"
    /// v15.22 batch36 · 字体大小（持久化 · 默认 13 · 范围 [10, 28]）
    @AppStorage("viewState.v1.formulaEditor.fontSize") private var fontSizeStored: Double = 13
    /// v15.22 batch7 · 片段库 · 用户自定义公式模板（JSON 持久化 · 跨会话保留）
    @AppStorage("viewState.v1.formulaEditor.snippets") private var snippetsJSON: String = ""
    @State private var statusMessage: String = L("未保存修改")
    @State private var showSnippetSaveSheet: Bool = false
    @State private var newSnippetName: String = ""
    /// v15.22 batch5 · 编译验证结果（nil = 未验证 / "" = 通过 / 否则错误信息）
    @State private var compileResult: String? = nil
    @State private var compileSucceeded: Bool = false
    /// v15.22 batch6 · 错误位置 marker · 编辑器内红色背景标注 · 用户改动后清空
    @State private var errorMarker: CodeErrorMarker? = nil
    /// v15.22 batch11 · 当前光标位置（1-based · 显示在 status bar）
    @State private var cursorLine: Int = 1
    @State private var cursorCol: Int = 1
    /// v15.22 batch23 · 当前选区范围（用于多行 ⌘/ 批量注释）
    @State private var selectionRange: NSRange = NSRange(location: 0, length: 0)
    /// v15.22 batch27 · 当前光标 token 的函数签名（nil = 当前位置不是已知函数）
    @State private var currentTokenSig: String? = nil
    /// v15.23 batch110 · 当前光标 token 原文（不限于已知函数 · 含变量名 · minimap 同名引用高亮用）
    @State private var currentTokenText: String? = nil
    /// v15.22 batch28 · 函数列表面板（⌘⇧L 切换 · 73 函数 9 分类）
    @State private var showFunctionsPanel: Bool = false
    /// v15.22 batch35 · 函数库搜索过滤
    @State private var funcSearchQuery: String = ""
    /// v15.22 batch29 · 跳转到行 sheet + 待跳转行号
    @State private var showGotoLineSheet: Bool = false
    @State private var gotoLineInput: String = ""
    @State private var pendingGotoLine: Int? = nil
    /// v15.23 batch107 · minimap 拖动专用 scroll-only 跳转（不动光标 · 与 pendingGotoLine 区分）
    @State private var pendingScrollToLine: Int? = nil
    /// v15.22 batch39 · 待插入到光标位置的文本
    @State private var pendingInsertText: String? = nil
    /// v15.22 batch34 · 快捷键帮助面板
    @State private var showHelpSheet: Bool = false
    /// v15.22 batch37 · 公式大纲面板（变量定义 + 行号 · 点击跳转）
    @State private var showOutlineSheet: Bool = false
    /// v15.23 batch139 · outline sheet 搜索框 · filter 变量名（大小写不敏感）
    @State private var outlineSearchQuery: String = ""
    /// v15.23 batch140 · outline sheet 仅显示输出变量 toggle
    @State private var outlineShowOutputsOnly: Bool = false
    /// v15.23 batch140 · outline sheet 排序键
    @State private var outlineSortKey: OutlineSortKey = .lineAsc

    enum OutlineSortKey: String, CaseIterable {
        case lineAsc = "行号 ↑"
        case nameAsc = "变量名 A→Z"
        case typeFirst = "输出在前"
    }

    // v15.23 batch43-44 · 多 tab 支持（多公式同窗口编辑 · 切换不丢内容）
    /// 持久化：tabs 数组 JSON（除 active tab 内容由 sourceText 镜像）
    @AppStorage("viewState.v1.formulaEditor.tabsJSON") private var tabsJSON: String = ""
    @AppStorage("viewState.v1.formulaEditor.activeTabIdx") private var activeTabIdxStored: Int = 0
    /// v15.23 batch45 · 保存时自动格式化（trader 习惯 · 关闭则按原样写盘）
    @AppStorage("viewState.v1.formulaEditor.formatOnSave") private var formatOnSave: Bool = true
    /// v15.23 batch123 · 保存时清行末空格（IDE 经典 · 默认开 · 配合 git 减少无意义 diff）
    @AppStorage("viewState.v1.formulaEditor.trimTrailingWhitespace") private var trimTrailingWhitespaceOnSave: Bool = true
    /// v15.23 batch47 · 最近文件历史（最新在前 · cap 5 · JSON 持久化）
    @AppStorage("viewState.v1.formulaEditor.recentFiles") private var recentFilesJSON: String = ""
    /// v15.23 batch105 · minimap 缩略图开关（IDE 级长公式快速导航 · 默认开 · ⌘⇧M 切换）
    @AppStorage("viewState.v1.formulaEditor.showMinimap") private var showMinimap: Bool = true
    /// v16.107 · lint 行内波浪线开关（默认开 · trader 视觉太重时可关）
    @AppStorage("viewState.v1.formulaEditor.showLintUnderline") private var showLintUnderline: Bool = true
    /// v16.152 · lint outline section 按 severity 过滤（默认全开 · trader noise 控制）
    @AppStorage("viewState.v1.formulaEditor.showLintErrors") private var showLintErrors: Bool = true
    @AppStorage("viewState.v1.formulaEditor.showLintWarnings") private var showLintWarnings: Bool = true
    /// v16.158 · 本会话隐藏指定 kind 的 lint（不持久化 · trader 临时关掉某类噪音）
    @State private var sessionHiddenLintKinds: Set<MaiLangLintWarning.Kind> = []
    /// v15.23 batch109 · minimap 宽度 4 档（80 窄 / 100 中 / 120 宽 / 160 超宽 · 默认 100 · 持久化）
    @AppStorage("viewState.v1.formulaEditor.minimapWidth") private var minimapWidth: Double = 100
    /// v15.23 batch106 · 主编辑器当前可视行（1-based · minimap viewport 高亮 + 滚动同步）
    @State private var visibleStartLine: Int = 1
    @State private var visibleEndLine: Int = 1
    /// v15.23 batch129 · split 视图右 pane 显示的 tab 索引（nil = 关闭 split · 默认关）
    @State private var splitTabIdx: Int? = nil
    /// 多 tab 状态（持久化 · 初始化在 .onAppear）
    @State private var tabs: [FormulaTab] = []
    @State private var activeIdx: Int = 0
    /// 关闭脏 tab 确认 sheet
    @State private var pendingCloseIdx: Int? = nil

    private var scheme: SyntaxColorScheme {
        schemeRaw == "light" ? .light : .dark
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // v15.23 batch43 · 多 tab bar（在 toolbar 下、编辑器上）
            FormulaTabBar(
                tabs: $tabs,
                activeIdx: $activeIdx,
                onSwitch: { idx in switchToTab(idx) },
                onNew: { newTab() },
                onClose: { idx in closeTab(idx) },
                onRename: { idx, newName in renameTab(idx, to: newName) },
                onReorder: { persistTabs() }
            )
            Divider()
            // v15.23 batch105 · 编辑器 + 右侧 minimap 缩略图（HStack 横排 · ⌘⇧M 切换）
            HStack(spacing: 0) {
                MaiLangCodeView(text: $sourceText, scheme: scheme,
                                fontSize: CGFloat(fontSizeStored),
                                errorMarker: errorMarker,
                                onCursorChange: { line, col in
                                    cursorLine = line
                                    cursorCol = col
                                },
                                onSelectionChange: { range in selectionRange = range },
                                onTokenAtCursor: { name in
                                    currentTokenText = name
                                    if let n = name?.uppercased(),
                                       let s = MaiLangFunctionSignatures.all[n] {
                                        currentTokenSig = s.formatted
                                    } else {
                                        currentTokenSig = nil
                                    }
                                },
                                pendingGotoLine: $pendingGotoLine,
                                pendingInsertText: $pendingInsertText,
                                pendingScrollToLine: $pendingScrollToLine,
                                onVisibleLinesChange: { s, e in
                                    visibleStartLine = s
                                    visibleEndLine = e
                                },
                                // v16.92 · lint 行内波浪线（按 severity 颜色）· v16.107 可关闭
                                lintWarnings: showLintUnderline ? MaiLangLint.analyze(sourceText) : [])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // v15.23 batch129 · split 视图右 pane（只读 · 同屏对比另一 tab · ⌘\\ 切换）
                if let splitIdx = splitTabIdx, splitIdx < tabs.count, splitIdx != activeIdx {
                    Divider()
                    let splitTab = tabs[splitIdx]
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.split.2x1")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(splitTab.name)
                                .font(.system(size: 11, weight: .semibold))
                            Text("(只读对比)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button { splitTabIdx = nil } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                            .tooltip("关闭 split 对比")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.06))
                        Divider()
                        MaiLangCodeView(text: .constant(splitTab.content),
                                        scheme: scheme,
                                        fontSize: CGFloat(fontSizeStored),
                                        isEditable: false,
                                        // v16.96 · split view 右 pane 也显示 lint 行内波浪线（与左 pane 一致）· v16.107 可关闭
                                        lintWarnings: showLintUnderline ? MaiLangLint.analyze(splitTab.content) : [])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                if showMinimap {
                    let selRange = minimapSelectionLineRange()
                    let warns = MaiLangLint.analyze(sourceText)
                    MinimapView(text: sourceText, scheme: scheme,
                                visibleStartLine: visibleStartLine,
                                visibleEndLine: visibleEndLine,
                                cursorLine: cursorLine,
                                selectionStartLine: selRange?.0,
                                selectionEndLine: selRange?.1,
                                errorLine: errorMarker?.line,
                                highlightedToken: currentTokenText,
                                warningLines: warns.filter { $0.severity == .warning }.map { $0.line },
                                lintErrorLines: warns.filter { $0.severity == .error }.map { $0.line },
                                onClickLine: { line in pendingScrollToLine = line },
                                onDoubleClickLine: { line in pendingGotoLine = line })
                        .frame(width: CGFloat(minimapWidth))
                }
            }
            .onChange(of: sourceText) { _ in
                // v15.22 batch6 · 用户改动后清错误标注（防陈旧 marker 误导）
                if errorMarker != nil { errorMarker = nil }
                if compileResult != nil { compileResult = nil }
                // v15.23 batch43-44 · 同步 active tab 内容 + 持久化
                syncActiveTab()
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 720, idealWidth: 920, minHeight: 480, idealHeight: 640)
        .onAppear {
            loadTabsIfNeeded()
        }
        // v15.23 batch44 · 关闭脏 tab 确认（pendingCloseIdx 非 nil 弹）
        .alert("关闭未保存的 tab？", isPresented: Binding(
            get: { pendingCloseIdx != nil },
            set: { if !$0 { pendingCloseIdx = nil } }
        )) {
            Button("取消", role: .cancel) { pendingCloseIdx = nil }
            Button("丢弃修改并关闭", role: .destructive) {
                if let idx = pendingCloseIdx { confirmCloseTab(idx) }
                pendingCloseIdx = nil
            }
        } message: {
            if let idx = pendingCloseIdx, idx < tabs.count {
                Text("「\(tabs[idx].name)」有未保存修改 · 关闭后将丢失")
            } else {
                Text("有未保存修改 · 关闭后将丢失")
            }
        }
        // v15.23 batch44 · 多 tab 快捷键（隐藏 button 触发 · SwiftUI 通用做法）
        .background(
            Group {
                Button("") { newTab() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .opacity(0)
                Button("") { closeTab(activeIdx) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .opacity(0)
                Button("") { switchPrev() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .opacity(0)
                Button("") { switchNext() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .opacity(0)
            }
        )
        // v15.22 batch37 · 公式大纲面板（变量定义 + 行号 · 点击跳转）
        // v15.23 batch120 · 加 lint warnings Section · 一站式结构 + 健康度
        .sheet(isPresented: $showOutlineSheet) {
            let allOutline = MaiLangOutline.parse(sourceText)
            let allLintWarns = MaiLangLint.analyze(sourceText)
            let q = outlineSearchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            let outline: [MaiLangOutlineEntry] = {
                let searchFiltered = q.isEmpty ? allOutline
                    : allOutline.filter { $0.name.lowercased().contains(q) }
                let outputFiltered = outlineShowOutputsOnly
                    ? searchFiltered.filter { $0.isOutput }
                    : searchFiltered
                switch outlineSortKey {
                case .lineAsc: return outputFiltered
                case .nameAsc: return outputFiltered.sorted { $0.name.lowercased() < $1.name.lowercased() }
                case .typeFirst:
                    return outputFiltered.sorted { a, b in
                        if a.isOutput != b.isOutput { return a.isOutput && !b.isOutput }
                        return a.line < b.line
                    }
                }
            }()
            let searchFilteredLints = q.isEmpty ? allLintWarns
                          : allLintWarns.filter { $0.message.lowercased().contains(q) }
            // v16.152 · severity 过滤（齿轮 Menu toggle 控制 · 默认全开 · trader noise 控制）
            // v16.158 · kind 过滤（每条 contextMenu 隐藏 · 本会话有效 · 不持久化）
            let lintWarns = searchFilteredLints.filter {
                ($0.severity == .error && showLintErrors)
                || ($0.severity == .warning && showLintWarnings)
            }.filter { !sessionHiddenLintKinds.contains($0.kind) }
            let deps = MaiLangDependencies.analyze(sourceText)
            let depByName: [String: MaiLangVarDependency] = Dictionary(
                uniqueKeysWithValues: deps.map { ($0.name.uppercased(), $0) })
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("📋 公式大纲").font(.title2).bold()
                    Text("(\(outline.count) 变量")
                        .font(.caption).foregroundColor(.secondary)
                    if !lintWarns.isEmpty {
                        Text("· \(lintWarns.count) 警告")
                            .font(.caption).foregroundColor(.orange)
                    }
                    Text(")").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    // v15.23 batch153 · 复制大纲到剪贴板（markdown bullet 格式）
                    Button {
                        copyOutlineMarkdown(outline: outline,
                                            warns: lintWarns,
                                            deps: depByName)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .tooltip("复制大纲为 markdown · 粘贴到笔记/分享公式结构")
                    // v15.23 batch140 · 排序 + 仅输出 toggle
                    Menu {
                        Section("排序") {
                            ForEach(OutlineSortKey.allCases, id: \.self) { k in
                                let isOn = outlineSortKey == k
                                Button("\(isOn ? "✓ " : "")\(k.rawValue)") { outlineSortKey = k }
                            }
                        }
                        Divider()
                        Toggle("仅显示输出变量", isOn: $outlineShowOutputsOnly)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .tooltip("排序选项 + 仅显示输出变量过滤")
                    Button("关闭") { showOutlineSheet = false }.keyboardShortcut(.cancelAction)
                    // v16.171 · ⌘W 关闭 sheet（macOS 标准 · 与 ESC 互补）
                    Button("") { showOutlineSheet = false }
                        .keyboardShortcut("w", modifiers: [.command])
                        .opacity(0)
                        .frame(width: 0, height: 0)
                }
                .padding(12)
                // batch139 · 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("过滤变量名 / 警告（如 \"DIF\" / \"未使用\"）", text: $outlineSearchQuery)
                        .textFieldStyle(.plain)
                    if !outlineSearchQuery.isEmpty {
                        Button { outlineSearchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                if outline.isEmpty && lintWarns.isEmpty {
                    Spacer()
                    HStack { Spacer(); Text("公式中暂无变量定义\n（NAME:=expr 或 NAME:expr,attr;）")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.callout); Spacer() }
                    Spacer()
                } else {
                    List {
                        if !outline.isEmpty {
                            Section(header: Text("变量定义").font(.headline)) {
                                ForEach(outline, id: \.line) { entry in
                                    let dep = depByName[entry.name.uppercased()]
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("\(entry.line)").font(.caption.monospacedDigit())
                                                .foregroundColor(.secondary)
                                                .frame(width: 32, alignment: .trailing)
                                            Text(entry.name)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                            Text(entry.isOutput ? "(输出)" : "(中间)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Button("跳转") {
                                                pendingGotoLine = entry.line
                                                showOutlineSheet = false
                                                statusMessage = "跳转到 \(entry.name) · 第 \(entry.line) 行"
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        // batch163 · 双击行任何位置直接跳转
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            pendingGotoLine = entry.line
                                            showOutlineSheet = false
                                            statusMessage = "跳转到 \(entry.name) · 第 \(entry.line) 行"
                                        }
                                        // batch134 · 依赖关系（紧凑显示在变量行下方）
                                        if let d = dep, !d.uses.isEmpty || !d.usedBy.isEmpty {
                                            HStack(spacing: 8) {
                                                Color.clear.frame(width: 32)
                                                if !d.uses.isEmpty {
                                                    Text("→ \(d.uses.joined(separator: ", "))")
                                                        .font(.caption2)
                                                        .foregroundColor(.cyan)
                                                        .tooltip("依赖：\(d.uses.joined(separator: ", "))")
                                                }
                                                if !d.usedBy.isEmpty {
                                                    Text("← \(d.usedBy.joined(separator: ", "))")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                        .tooltip("被引用：\(d.usedBy.joined(separator: ", "))")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !lintWarns.isEmpty || !allLintWarns.isEmpty {
                            // v16.75 · 按 severity 排序：error 在前 · warning 在后 · 同级保持原行号顺序
                            let sortedLints = lintWarns.sorted {
                                if $0.severity != $1.severity { return $0.severity > $1.severity }
                                return $0.line < $1.line
                            }
                            let errorCount = sortedLints.filter { $0.severity == .error }.count
                            let unusedLines = sortedLints.filter { $0.kind == .unusedVariable }.map { $0.line }
                            // v16.154 · 总数（不受 severity filter 影响 · chip 展示完整 warn count）
                            let totalErrorCount = allLintWarns.filter { $0.severity == .error }.count
                            let totalWarningCount = allLintWarns.filter { $0.severity == .warning }.count
                            Section(header: HStack {
                                Text("⚠ Lint 警告").font(.headline).foregroundColor(.orange)
                                if errorCount > 0 {
                                    Text("(\(errorCount) 紧急 + \(sortedLints.count - errorCount) 提醒)")
                                        .font(.caption).foregroundColor(.secondary)
                                } else {
                                    Text("(\(sortedLints.count))").font(.caption).foregroundColor(.secondary)
                                }
                                // v16.154 · severity 过滤 chip（直接点击切换 · 比齿轮 Menu 直觉）
                                if totalErrorCount > 0 {
                                    severityFilterChip(
                                        label: "🔴 \(totalErrorCount)",
                                        isOn: showLintErrors,
                                        tip: "\(showLintErrors ? "隐藏" : "显示") error 紧急 (\(totalErrorCount) 条)"
                                    ) { showLintErrors.toggle() }
                                }
                                if totalWarningCount > 0 {
                                    severityFilterChip(
                                        label: "🟡 \(totalWarningCount)",
                                        isOn: showLintWarnings,
                                        tip: "\(showLintWarnings ? "隐藏" : "显示") warning 提醒 (\(totalWarningCount) 条)"
                                    ) { showLintWarnings.toggle() }
                                }
                                Spacer()
                                // v16.113 · 批量删除全部 unused（≥ 2 才显示 · 单条用单 Menu）
                                if unusedLines.count >= 2 {
                                    Button {
                                        quickFixDeleteLinesBatch(unusedLines)
                                        statusMessage = "已删除 \(unusedLines.count) 条未用变量定义"
                                    } label: {
                                        Label("一键删除 \(unusedLines.count) 条未用", systemImage: "trash.fill")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.borderless)
                                    .tooltip("批量删除所有 unusedVariable 警告对应的行")
                                }
                                // v16.173 · 一键隐藏全部 warning kinds（保留 error · trader 聚焦紧急）
                                let warningKinds: Set<MaiLangLintWarning.Kind> = Set(
                                    allLintWarns.filter { $0.severity == .warning }.map(\.kind))
                                let warningKindsNotYetHidden = warningKinds.subtracting(sessionHiddenLintKinds)
                                if warningKindsNotYetHidden.count >= 2 {
                                    Button {
                                        sessionHiddenLintKinds.formUnion(warningKinds)
                                        statusMessage = "已隐藏全部 warning 类 lint · 仅显示 error"
                                    } label: {
                                        Label("仅看 error", systemImage: "eye.slash.fill")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.borderless)
                                    .tooltip("一键隐藏全部 warning 类（\(warningKinds.count) 类）· 仅保留 error · 与 v16.158 单类 hide 共享 sessionHiddenLintKinds")
                                }
                            }) {
                                // v16.154 · 全 filter 隐藏后 · 提示用户点 chip 重开
                                if sortedLints.isEmpty {
                                    HStack {
                                        Text("⚙️ 已通过 chip 隐藏全部 \(allLintWarns.count) 条 lint · 点击 chip 重新显示")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                }
                                // v16.158 · 已隐藏 kinds 恢复 chip 行（trader 一键恢复某类）
                                // v16.160 · ≥ 2 时加 "全部恢复" button（一键清空隐藏集）
                                if !sessionHiddenLintKinds.isEmpty {
                                    HStack(spacing: 4) {
                                        Text("已隐藏：").font(.system(size: 10)).foregroundColor(.secondary)
                                        ForEach(Array(sessionHiddenLintKinds), id: \.self) { kind in
                                            Button {
                                                sessionHiddenLintKinds.remove(kind)
                                            } label: {
                                                HStack(spacing: 2) {
                                                    Text(lintKindLabel(kind))
                                                        .font(.system(size: 10))
                                                    Image(systemName: "arrow.uturn.backward.circle")
                                                        .font(.system(size: 9))
                                                }
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.secondary.opacity(0.15)))
                                            }
                                            .buttonStyle(.plain)
                                            .tooltip("恢复显示 \(lintKindLabel(kind)) 类")
                                        }
                                        if sessionHiddenLintKinds.count >= 2 {
                                            Button {
                                                let n = sessionHiddenLintKinds.count
                                                sessionHiddenLintKinds.removeAll()
                                                statusMessage = "已恢复 \(n) 类隐藏 lint"
                                            } label: {
                                                Text("全部恢复")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(RoundedRectangle(cornerRadius: 4)
                                                        .strokeBorder(Color.accentColor.opacity(0.6),
                                                                       lineWidth: 1))
                                                    .foregroundColor(.accentColor)
                                            }
                                            .buttonStyle(.plain)
                                            .tooltip("一键恢复全部 \(sessionHiddenLintKinds.count) 类隐藏的 lint")
                                        }
                                    }
                                }
                                ForEach(Array(sortedLints.enumerated()), id: \.offset) { _, warn in
                                    HStack {
                                        Text("\(warn.line)").font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                            .frame(width: 32, alignment: .trailing)
                                        // v16.75 · severity 颜色 + icon 区分（error 红 / warning 橙）
                                        Image(systemName: warn.severity == .error
                                              ? "exclamationmark.octagon.fill"
                                              : "exclamationmark.triangle.fill")
                                            .foregroundColor(warn.severity == .error ? .red : .orange)
                                            .font(.system(size: 11))
                                        Text(warn.message)
                                            .font(.system(size: 12))
                                        Spacer()
                                        // v16.60 · quick fix Menu（按 kind 提供针对性修复）
                                        quickFixMenu(for: warn)
                                        Button("跳转") {
                                            pendingGotoLine = warn.line
                                            showOutlineSheet = false
                                            statusMessage = "跳转到第 \(warn.line) 行 · \(warn.message)"
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    // v16.158 · 右键隐藏此 kind 类（本会话 · 不持久化）
                                    .contextMenu {
                                        Button {
                                            sessionHiddenLintKinds.insert(warn.kind)
                                            statusMessage = "已隐藏 \(lintKindLabel(warn.kind)) 类 lint（本会话）"
                                        } label: {
                                            Label("本会话隐藏「\(lintKindLabel(warn.kind))」类",
                                                   systemImage: "eye.slash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 460, idealWidth: 540, minHeight: 460, idealHeight: 600)
        }
        // v15.22 batch34 · 快捷键帮助面板（22+ 快捷键 · 按主题分组）
        .sheet(isPresented: $showHelpSheet) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("⌨️ 编辑器快捷键").font(.title2).bold()
                    Spacer()
                    Button("关闭") { showHelpSheet = false }.keyboardShortcut(.cancelAction)
                }
                .padding(12)
                Divider()
                List {
                    ForEach(Self.helpGroups, id: \.0) { (group, items) in
                        Section(header: Text(group).font(.headline)) {
                            ForEach(items, id: \.0) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.0)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 130, alignment: .leading)
                                        .foregroundColor(.accentColor)
                                    Text(item.1)
                                        .font(.callout)
                                    Spacer()
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 520, idealWidth: 600, minHeight: 540, idealHeight: 680)
        }
        // v15.22 batch29 · 跳转到行 sheet
        .sheet(isPresented: $showGotoLineSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("跳转到行").font(.title2).bold()
                let total = textStats(sourceText).lines
                Text("总 \(total) 行 · 当前光标第 \(cursorLine) 行")
                    .font(.caption).foregroundColor(.secondary)
                TextField("行号（1-\(total)）", text: $gotoLineInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitGotoLine() }
                Spacer()
                HStack {
                    Spacer()
                    Button("取消") { showGotoLineSheet = false }.keyboardShortcut(.cancelAction)
                    Button("跳转") { commitGotoLine() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(Int(gotoLineInput) == nil)
                }
            }
            .padding(20)
            .frame(width: 320, height: 180)
        }
        // v15.22 batch28+35 · 函数库 sheet（73 函数 · 9 分类 · 搜索过滤）
        .sheet(isPresented: $showFunctionsPanel) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("📚 麦语言函数库").font(.title2).bold()
                    Text("(\(MaiLangFunctionSignatures.entries.count) 个 · 9 大类)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("关闭") { showFunctionsPanel = false }.keyboardShortcut(.cancelAction)
                }
                .padding(12)
                // batch35 · 搜索框（按 name / summary 过滤）
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索函数名 / 摘要（如 \"ma\"、\"均线\"、\"穿\"）", text: $funcSearchQuery)
                        .textFieldStyle(.plain)
                    if !funcSearchQuery.isEmpty {
                        Button { funcSearchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
                Divider()
                List {
                    if funcSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(MaiLangFunctionSignatures.byCategory, id: \.0) { (cat, sigs) in
                            Section(header: Text(cat.rawValue).font(.headline)) {
                                ForEach(sigs, id: \.name) { sig in functionRow(sig) }
                            }
                        }
                    } else {
                        let results = MaiLangFunctionSignatures.search(funcSearchQuery)
                        if results.isEmpty {
                            Text("未匹配到函数").font(.callout).foregroundColor(.secondary).padding()
                        } else {
                            Section(header: Text("搜索结果（\(results.count) 个）").font(.headline)) {
                                ForEach(results, id: \.name) { sig in functionRow(sig) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 460, idealWidth: 540, minHeight: 520, idealHeight: 640)
        }
        // v15.22 batch7 · 保存片段 sheet · 输入名后追加到 @AppStorage 列表
        .sheet(isPresented: $showSnippetSaveSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("保存为片段").font(.title2).bold()
                Text("输入片段名（已存在同名将覆盖）").font(.caption).foregroundColor(.secondary)
                TextField("例如：MACD 标准 / 我的均线突破", text: $newSnippetName)
                    .textFieldStyle(.roundedBorder)
                Text("片段长度：\(sourceText.count) 字符 · \(textStats(sourceText).lines) 行")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Button("取消") { showSnippetSaveSheet = false }.keyboardShortcut(.cancelAction)
                    Button("保存") {
                        let trimmed = newSnippetName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        saveSnippet(name: trimmed, text: sourceText)
                        showSnippetSaveSheet = false
                        statusMessage = "已保存片段：\(trimmed)"
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newSnippetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 380, height: 200)
        }
    }

    // MARK: - 内置示例（v15.22 batch8 · trader 学习参考 · 标准指标实现）

    private struct BuiltinExample {
        let name: String
        let description: String
        let text: String
    }

    // v16.37 · 代码片段（trader 写公式常用 1-2 行表达式 · 插入光标位置不覆盖）
    private struct CodeSnippet {
        let name: String
        let category: String
        let text: String
        let description: String
    }

    private static let codeSnippets: [CodeSnippet] = [
        // 信号 4
        CodeSnippet(name: "金叉", category: "信号",
            text: "CROSS(MA(CLOSE,5),MA(CLOSE,20))",
            description: "5 日均线上穿 20 日均线（经典金叉）"),
        CodeSnippet(name: "死叉", category: "信号",
            text: "CROSSDOWN(MA(CLOSE,5),MA(CLOSE,20))",
            description: "5 日均线下穿 20 日均线"),
        CodeSnippet(name: "KDJ 金叉超卖", category: "信号",
            text: "CROSS(K,D) AND K<20",
            description: "K 上穿 D · 且 K 在超卖区（< 20）· 高质信号"),
        CodeSnippet(name: "MACD 顶背离", category: "信号",
            text: "HIGH>=HHV(HIGH,20) AND DIF<HHV(DIF,20)",
            description: "价创新高 · 但 MACD DIF 未创新高（动能减弱）"),
        // 形态 3
        CodeSnippet(name: "突破新高", category: "形态",
            text: "CROSS(CLOSE,REF(HHV(HIGH,20),1))",
            description: "收盘价突破前 20 日最高（突破信号）"),
        CodeSnippet(name: "假突破回踩", category: "形态",
            text: "CLOSE<REF(HHV(HIGH,20),1) AND HIGH>REF(HHV(HIGH,20),1)",
            description: "盘中破前高 · 收盘回落（假突破 · 反手做空候选）"),
        CodeSnippet(name: "布林挤压", category: "形态",
            text: "(BOLL_UP-BOLL_LOW)/MA(CLOSE,20)<0.05",
            description: "布林带宽收窄 < 5%（蓄势 · 即将变盘）"),
        // 风险 3
        CodeSnippet(name: "止损 2%", category: "风险",
            text: "CLOSE<ENTRYPRICE*0.98",
            description: "持仓后浮亏达 2% 平仓（固定百分比止损）"),
        CodeSnippet(name: "止盈 5%", category: "风险",
            text: "CLOSE>=ENTRYPRICE*1.05",
            description: "持仓后浮盈达 5% 平仓（固定百分比止盈）"),
        CodeSnippet(name: "移动止损", category: "风险",
            text: "CLOSE<HHV(CLOSE,5)*0.97",
            description: "回撤超 5 日最高 3% 平仓（trailing stop · 锁利）"),
        // 量价 2
        CodeSnippet(name: "量能放大", category: "量价",
            text: "VOLUME>REF(VOLUME,1)*1.5",
            description: "当前量能比上期放大 1.5 倍（有效突破前置条件）"),
        CodeSnippet(name: "缩量回调", category: "量价",
            text: "VOLUME<MA(VOLUME,5)*0.7 AND CLOSE<REF(CLOSE,1)",
            description: "量能 < 5 日均量 70% 且收阴（健康回调 · 不破位则可加仓）"),
    ]

    private static let builtinExamples: [BuiltinExample] = [
        BuiltinExample(name: "MACD（标准）", description: "经典 MACD · DIF/DEA/MACD 三线 · 红柱涨绿柱跌", text: """
        {MACD · 移动平均收敛发散指标}
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2,COLORRED,LINETHICK2;
        """),
        BuiltinExample(name: "KDJ（标准）", description: "随机指标 K/D/J 三线 · 9 周期", text: """
        {KDJ · 随机指标}
        RSV:=(CLOSE-LLV(LOW,9))/(HHV(HIGH,9)-LLV(LOW,9))*100;
        K:SMA(RSV,3,1);
        D:SMA(K,3,1);
        J:3*K-2*D;
        """),
        BuiltinExample(name: "RSI（6/12/24）", description: "相对强弱指标三周期 · 50 中轴", text: """
        {RSI · 相对强弱指标}
        LC:=REF(CLOSE,1);
        RSI6:SMA(MAX(CLOSE-LC,0),6,1)/SMA(ABS(CLOSE-LC),6,1)*100;
        RSI12:SMA(MAX(CLOSE-LC,0),12,1)/SMA(ABS(CLOSE-LC),12,1)*100;
        RSI24:SMA(MAX(CLOSE-LC,0),24,1)/SMA(ABS(CLOSE-LC),24,1)*100;
        """),
        BuiltinExample(name: "BOLL（布林带）", description: "布林带 20 周期 ±2 倍标准差", text: """
        {BOLL · 布林带}
        MID:MA(CLOSE,20);
        UPPER:MID+2*STD(CLOSE,20);
        LOWER:MID-2*STD(CLOSE,20);
        """),
        BuiltinExample(name: "MA 多周期", description: "5/10/20/60 多均线", text: """
        {MA · 多周期均线}
        MA5:MA(CLOSE,5),COLORYELLOW;
        MA10:MA(CLOSE,10),COLORMAGENTA;
        MA20:MA(CLOSE,20),COLORWHITE;
        MA60:MA(CLOSE,60),COLORGREEN;
        """),
        BuiltinExample(name: "突破信号", description: "20 日新高 + 量能放大 1.5 倍", text: """
        {突破信号 · 价新高 + 量能放大}
        BREAK:=CROSS(CLOSE,REF(HHV(HIGH,20),1));
        VOLUP:=VOLUME>REF(VOLUME,1)*1.5;
        SIGNAL:BREAK AND VOLUP,COLORRED,LINETHICK2;
        """),
    ]

    // MARK: - 片段库（@AppStorage JSON 持久化）

    private struct Snippet: Codable, Equatable, Sendable {
        let name: String
        let text: String
    }

    private func loadSnippets() -> [Snippet] {
        guard !snippetsJSON.isEmpty,
              let data = snippetsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Snippet].self, from: data) else {
            return []
        }
        return arr
    }

    private func saveSnippet(name: String, text: String) {
        var snippets = loadSnippets()
        snippets.removeAll { $0.name == name }   // 同名覆盖
        snippets.append(Snippet(name: name, text: text))
        if let data = try? JSONEncoder().encode(snippets),
           let str = String(data: data, encoding: .utf8) {
            snippetsJSON = str
        }
    }

    private func deleteSnippet(_ name: String) {
        var snippets = loadSnippets()
        snippets.removeAll { $0.name == name }
        if let data = try? JSONEncoder().encode(snippets),
           let str = String(data: data, encoding: .utf8) {
            snippetsJSON = str
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("📝 麦语言公式编辑器").font(.headline)
            Divider().frame(height: 18)
            Button {
                openFile()
            } label: {
                Label("打开 .wh", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .tooltip("从 .wh / .txt 文件加载（⌘O）")
            // v15.23 batch47 · 最近文件 Menu（cap 5 · 最新在前）
            Menu {
                let recents = recentFiles
                if recents.isEmpty {
                    Button("（暂无最近文件）") { }.disabled(true)
                } else {
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            loadRecentFile(url)
                        }
                        .tooltip(url.path)
                    }
                    Divider()
                    Button("清空最近") { clearRecentFiles() }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .tooltip("最近文件（最多 5 · 点击直接加载到当前 tab）")
            Button {
                saveFile()
            } label: {
                Label("保存为 .wh", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(sourceText.isEmpty)
            .tooltip("保存到 .wh / .txt 文件（⌘S）")
            Menu {
                Button("复制全文（纯文本）") { copyAllToPasteboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                // v15.22 batch22 · 导出 Markdown 代码块（trader 分享聊天/笔记常用）
                Button("复制为 Markdown 代码块") { copyAsMarkdown() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .tooltip("复制公式（⌘⇧C 纯文本 / ⌘⌥C Markdown 代码块）")
            // v15.22 batch5 · 编译验证（⌘B · 走 IndicatorCore Lexer + Parser · 第一个错误精确定位）
            Button {
                compileNow()
            } label: {
                Label("编译验证", systemImage: "checkmark.shield")
            }
            .keyboardShortcut("b", modifiers: [.command])
            .tooltip("用 IndicatorCore Lexer + Parser 验证公式 · 错误显示行列（⌘B）")
            // v15.23 batch41 · 格式化公式（⌘⇧F · MaiLangFormatter 一键归一）
            Button {
                formatNow()
            } label: {
                Label("格式化", systemImage: "wand.and.stars")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .tooltip("一键格式化公式 · 大写关键字 + 空白归一 + 逗号空格（⌘⇧F）")
            // v15.22 batch15 · 注释切换（⌘/ · 麦语言行注释 // · 当前行 toggle）
            Button {
                toggleLineComment()
            } label: {
                Label("注释切换", systemImage: "text.append")
            }
            .keyboardShortcut("/", modifiers: [.command])
            .tooltip("注释 / 取消注释当前行（⌘/）")
            // v15.22 batch17 · 删除当前行（⌘⇧K · VSCode 经典）
            Button {
                deleteCurrentLine()
            } label: {
                Label("删除行", systemImage: "minus.rectangle")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .tooltip("删除当前光标所在行（⌘⇧K）")
            // v15.22 batch18 · 复制当前行到下一行（⌘D · VSCode/Sublime 经典）
            Button {
                duplicateCurrentLine()
            } label: {
                Label("复制行", systemImage: "plus.rectangle.on.rectangle")
            }
            .keyboardShortcut("d", modifiers: [.command])
            .tooltip("复制当前光标所在行到下一行（⌘D）")
            // v15.22 batch19 · 上下移动当前行（⌥↑/⌥↓ · VSCode/Sublime 经典）
            Button { moveCurrentLine(up: true) } label: { Image(systemName: "arrow.up.square") }
                .keyboardShortcut(.upArrow, modifiers: [.option])
                .tooltip("当前行上移（⌥↑）")
            Button { moveCurrentLine(up: false) } label: { Image(systemName: "arrow.down.square") }
                .keyboardShortcut(.downArrow, modifiers: [.option])
                .tooltip("当前行下移（⌥↓）")
            // v15.22 batch25 · 缩进/反缩进选中行（⌘]/⌘[ · VSCode 经典）
            Button { indentLines(by: 1) } label: { Image(systemName: "increase.indent") }
                .keyboardShortcut("]", modifiers: [.command])
                .tooltip("缩进选中行（⌘]）")
            Button { indentLines(by: -1) } label: { Image(systemName: "decrease.indent") }
                .keyboardShortcut("[", modifiers: [.command])
                .tooltip("反缩进选中行（⌘[）")
            // v15.22 batch28 · 函数库面板（73 函数 9 分类 · 浏览 + 复制函数签名）
            Button {
                showFunctionsPanel = true
            } label: {
                Label("函数库", systemImage: "function")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .tooltip("浏览 73 个内置函数（⌘⇧L · 按分类 · 复制签名）")
            // v15.22 batch29 · 跳转到行（⌘L · 与 batch20 行号/batch24 点击行号联动）
            Button {
                gotoLineInput = "\(cursorLine)"
                showGotoLineSheet = true
            } label: {
                Label("跳转到行", systemImage: "arrow.right.to.line")
            }
            .keyboardShortcut("l", modifiers: [.command])
            .tooltip("跳转到指定行（⌘L · 输入行号）")
            // v15.22 batch34 · 快捷键帮助面板（⌘⇧? · trader 学习编辑器 22+ 快捷键）
            Button {
                showHelpSheet = true
            } label: {
                Label("帮助", systemImage: "questionmark.circle")
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
            .tooltip("查看所有编辑器快捷键（⌘⇧?）")
            // v15.22 batch37 · 公式大纲（⌘⇧O · 解析变量定义 · 点击跳转）
            Button {
                showOutlineSheet = true
            } label: {
                Label("大纲", systemImage: "list.bullet.indent")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .tooltip("公式大纲（⌘⇧O · 变量定义列表 · 点击跳转）")
            // v15.23 batch129 · split 视图（⌘\ 切换 · 选 tab 同屏只读对比）
            Menu {
                if splitTabIdx != nil {
                    Button("✕ 关闭 split") { splitTabIdx = nil }
                        .keyboardShortcut("\\", modifiers: [.command])
                    Divider()
                }
                ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                    if idx != activeIdx {
                        let isOn = (splitTabIdx == idx)
                        Button("\(isOn ? "✓ " : "")\(tab.name)") {
                            splitTabIdx = isOn ? nil : idx
                        }
                    }
                }
                if tabs.count <= 1 {
                    Text("（仅 1 个 tab · 新建第二个再 split）")
                }
            } label: {
                Label("分屏",
                      systemImage: splitTabIdx != nil ? "square.split.2x1.fill" : "square.split.2x1")
            }
            .tooltip("split 视图（⌘\\ 切换 · 选另一 tab 同屏只读对比 · trader 比对 MACD vs KDJ 实现）")
            // v15.23 batch105/109 · minimap 缩略图（⌘⇧M 切换 + Menu 选宽度 4 档）
            Menu {
                Button(showMinimap ? "▣ 隐藏 minimap" : "▢ 显示 minimap") {
                    showMinimap.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                if showMinimap {
                    Divider()
                    Picker("宽度", selection: $minimapWidth) {
                        Text("窄（80pt）").tag(80.0)
                        Text("中（100pt · 默认）").tag(100.0)
                        Text("宽（120pt）").tag(120.0)
                        Text("超宽（160pt）").tag(160.0)
                    }
                }
            } label: {
                Label("缩略图",
                      systemImage: showMinimap ? "rectangle.righthalf.inset.filled" : "rectangle.righthalf.inset")
            }
            .tooltip("minimap 缩略图（⌘⇧M 切换 · 宽度 4 档 · 拖动跳转 · 持久化）")
            // v15.22 batch36 · 字体大小调节（⌘=放大 / ⌘-缩小 / ⌘0 重置 · 持久化）
            Menu {
                Button("放大字体（⌘=）") {
                    fontSizeStored = min(28, fontSizeStored + 1)
                }
                .keyboardShortcut("=", modifiers: [.command])
                Button("缩小字体（⌘-）") {
                    fontSizeStored = max(10, fontSizeStored - 1)
                }
                .keyboardShortcut("-", modifiers: [.command])
                Button("重置（⌘0 · 默认 13pt）") {
                    fontSizeStored = 13
                }
                .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Text("当前 \(Int(fontSizeStored))pt")
            } label: {
                Label("字体", systemImage: "textformat.size")
            }
            .tooltip("字体大小（⌘= 放大 / ⌘- 缩小 / ⌘0 重置 · 持久化）")
            // v15.22 batch8 · 内置示例公式 Menu（trader 学习 · 一键加载标准实现）
            Menu {
                ForEach(Self.builtinExamples, id: \.name) { ex in
                    Button(ex.name) {
                        sourceText = ex.text
                        statusMessage = "已加载示例：\(ex.name)"
                    }
                    .tooltip(ex.description)
                }
            } label: {
                Label("示例", systemImage: "books.vertical.fill")
            }
            .tooltip("加载内置标准公式示例（MACD / KDJ / RSI / BOLL 等）")
            // v16.37 · 内置代码片段 Menu（trader 高频 1-2 行表达式 · 插入光标位置不覆盖 · 4 类 12 个）
            Menu {
                let grouped = Dictionary(grouping: Self.codeSnippets, by: { $0.category })
                let order = ["信号", "形态", "风险", "量价"]
                ForEach(order, id: \.self) { cat in
                    if let items = grouped[cat], !items.isEmpty {
                        Section(cat) {
                            ForEach(items, id: \.name) { snip in
                                Button(snip.name) {
                                    pendingInsertText = snip.text
                                    statusMessage = "已插入片段：\(snip.name)"
                                }
                                .tooltip("\(snip.description)\n→ \(snip.text)")
                            }
                        }
                    }
                }
            } label: {
                Label("插入片段", systemImage: "wrench.adjustable")
            }
            .tooltip("插入 trader 高频 1-2 行表达式到光标位置（金叉 / 突破新高 / 止损止盈 / 量能放大 等 12 个）")
            // v15.22 batch7 · 片段库 Menu（保存当前 / 加载已存 · trader 自定义模板）
            Menu {
                Button("💾 保存当前为片段…") {
                    newSnippetName = ""
                    showSnippetSaveSheet = true
                }
                .disabled(sourceText.isEmpty)
                Divider()
                let snippets = loadSnippets()
                if snippets.isEmpty {
                    Text("（暂无片段）")
                } else {
                    ForEach(snippets, id: \.name) { snip in
                        Button(snip.name) { sourceText = snip.text; statusMessage = "已加载片段：\(snip.name)" }
                    }
                    Divider()
                    Menu("🗑️ 删除片段") {
                        ForEach(snippets, id: \.name) { snip in
                            Button(snip.name, role: .destructive) {
                                deleteSnippet(snip.name)
                                statusMessage = "已删除片段：\(snip.name)"
                            }
                        }
                    }
                }
            } label: {
                Label("片段库", systemImage: "books.vertical")
            }
            .tooltip("保存当前公式为命名片段 / 加载已存片段（@AppStorage 持久化）")
            Spacer()
            // v15.23 batch45/123 · 编辑器选项（保存自动格式化 + 清行末空格）
            Menu {
                Toggle("保存时自动格式化", isOn: $formatOnSave)
                Toggle("保存时清行末空格", isOn: $trimTrailingWhitespaceOnSave)
                // v16.107 · lint 行内波浪线开关
                Toggle("显示 lint 行内波浪线", isOn: $showLintUnderline)
                // v16.152 · lint outline section 按 severity 过滤（noise 控制）
                Divider()
                Toggle("显示 lint 紧急（error）", isOn: $showLintErrors)
                Toggle("显示 lint 提醒（warning）", isOn: $showLintWarnings)
                Divider()
                Button(formatOnSave ? "✓ 自动格式化已启用" : "▢ 自动格式化已关闭") { }
                    .disabled(true)
                Button(trimTrailingWhitespaceOnSave ? "✓ 清行末空格已启用" : "▢ 清行末空格已关闭") { }
                    .disabled(true)
                Button(showLintUnderline ? "✓ lint 波浪线已启用" : "▢ lint 波浪线已关闭") { }
                    .disabled(true)
                Button("\(showLintErrors ? "✓" : "▢") error · \(showLintWarnings ? "✓" : "▢") warning") { }
                    .disabled(true)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .tooltip("编辑器选项 · 保存自动格式化 / lint 显示等")
            // 主题切换
            Picker("主题", selection: $schemeRaw) {
                Text("🌙 暗色").tag("dark")
                Text("☀️ 浅色").tag("light")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 12) {
            // v15.23 batch61 · active tab 文件路径 + dirty marker（trader 知道当前是哪个文件）
            if !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count {
                let active = tabs[activeIdx]
                HStack(spacing: 4) {
                    // v15.23 batch66 · tab N/M 计数（与 multichart status bar 风格一致）
                    Text("Tab \(activeIdx + 1)/\(tabs.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .tooltip("当前 tab \(activeIdx + 1) · 共 \(tabs.count) 个 · ⌘⌥← / → 切换")
                    Image(systemName: active.fileURL == nil ? "doc" : "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let url = active.fileURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .tooltip(url.path)
                    } else {
                        Text("未保存")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if active.isDirty {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                            .tooltip("有未保存修改")
                    }
                }
                Divider().frame(height: 12)
            }
            // 字符数 / 行数
            let stats = textStats(sourceText)
            Text("行数 \(stats.lines)").font(.caption).foregroundColor(.secondary)
            Text("字符 \(stats.chars)").font(.caption).foregroundColor(.secondary)
            // v15.23 batch111/145/148 · lint 警告 chip · 按类型细分（未使用/重复/无颜色）
            let lintWarnings = MaiLangLint.analyze(sourceText)
            if !lintWarnings.isEmpty {
                let unusedCount = lintWarnings.filter { $0.kind == .unusedVariable }.count
                let dupCount = lintWarnings.filter { $0.kind == .duplicateDefinition }.count
                let colorCount = lintWarnings.filter { $0.kind == .missingColorAttribute }.count
                let undefinedCount = lintWarnings.filter { $0.kind == .undefinedVariable }.count
                let argCount = lintWarnings.filter { $0.kind == .argCountMismatch }.count
                let suspiciousCount = lintWarnings.filter { $0.kind == .suspiciousVariableName }.count
                let chipText = [
                    undefinedCount > 0 ? "\(undefinedCount) 未定义" : nil,
                    dupCount > 0 ? "\(dupCount) 重复" : nil,
                    argCount > 0 ? "\(argCount) 参数" : nil,
                    unusedCount > 0 ? "\(unusedCount) 未用" : nil,
                    colorCount > 0 ? "\(colorCount) 无色" : nil,
                    suspiciousCount > 0 ? "\(suspiciousCount) 疑似" : nil,
                ].compactMap { $0 }.joined(separator: " · ")
                // v16.78 · 有 error 严重度 → chip 用红色（紧急）· 仅 warning → 橙
                let hasError = lintWarnings.contains { $0.severity == .error }
                let chipColor: Color = hasError ? .red : .orange
                Button {
                    // 跳到首个 error · 无 error 则首个 warning（v16.78 按 severity 优先）
                    let target = lintWarnings.first { $0.severity == .error } ?? lintWarnings.first
                    pendingGotoLine = target?.line
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: hasError ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(chipColor)
                        Text(chipText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(chipColor)
                    }
                }
                .buttonStyle(.borderless)
                .tooltip(lintWarnings.prefix(5).map { "第 \($0.line) 行 · \($0.message)" }
                      .joined(separator: "\n") +
                      (lintWarnings.count > 5 ? "\n... 还有 \(lintWarnings.count - 5) 个" : ""))
            }
            // v15.22 batch11 · 当前光标位置（行:列 · 与编译错误的"第 N 行第 M 列"对齐 trader 直接定位）
            Text("光标 \(cursorLine):\(cursorCol)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .tooltip("当前光标位置（行:列 · 与编译错误定位对齐）")
            // v15.22 batch27 · 当前光标 token 函数签名（与 batch26 静态表联动 · IDE 教学体验）
            if let sig = currentTokenSig {
                Text("📖 \(sig)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .tooltip("当前光标处函数签名（参考 batch26 内置签名表 · 73 个函数）")
            }
            // token 数（与 highlighter 同源）
            let tokenCount = MaiLangSyntaxHighlighter.tokenize(sourceText).count
            Text("token \(tokenCount)").font(.caption).foregroundColor(.secondary)
            // v15.22 batch5 · 编译状态 chip
            // v15.23 batch124 · 编译失败时加「复制错误」按钮（trader 直接粘贴求助 ChatGPT）
            if let result = compileResult {
                Image(systemName: compileSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundColor(compileSucceeded ? .green : .red)
                Text(result)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(compileSucceeded ? .green : .red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !compileSucceeded {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(result, forType: .string)
                        statusMessage = "已复制错误信息（\(result.count) 字符）"
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .tooltip("复制错误信息（粘贴到搜索/AI 求助）")
                }
            }
            Spacer()
            Text(statusMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
    }

    // MARK: - 操作

    private func openFile() {
        let panel = NSOpenPanel()
        panel.title = L("打开 .wh / 文本公式")
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            sourceText = text
            // v15.23 batch44 · 打开文件后更新 active tab 名 + URL + 清 dirty
            if !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count {
                tabs[activeIdx].name = url.deletingPathExtension().lastPathComponent
                tabs[activeIdx].fileURL = url
                tabs[activeIdx].isDirty = false
                persistTabs()
            }
            // v15.23 batch47 · 加最近文件
            pushRecentFile(url)
            statusMessage = "已加载 \(url.lastPathComponent) · \(text.count) 字符"
        } catch {
            statusMessage = "打开失败：\(error.localizedDescription)"
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.title = L("保存麦语言公式")
        panel.allowedContentTypes = [.plainText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        // v15.23 batch44 · 已绑文件的 tab 默认用原文件名（trader 重复保存常用）
        if !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count,
           let url = tabs[activeIdx].fileURL {
            panel.nameFieldStringValue = url.lastPathComponent
            panel.directoryURL = url.deletingLastPathComponent()
        } else {
            panel.nameFieldStringValue = "formula_\(dateFmt.string(from: Date())).wh"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // v15.23 batch45/123 · 保存前格式化 + 清行末空格（顺序：先 format · 后 trim）
            var textToSave: String = formatOnSave ? MaiLangFormatter.format(sourceText) : sourceText
            if trimTrailingWhitespaceOnSave {
                textToSave = textToSave
                    .components(separatedBy: "\n")
                    .map { line in
                        var s = Substring(line)
                        while let last = s.last, last == " " || last == "\t" { s = s.dropLast() }
                        return String(s)
                    }
                    .joined(separator: "\n")
            }
            if textToSave != sourceText {
                sourceText = textToSave
            }
            try textToSave.write(to: url, atomically: true, encoding: .utf8)
            // v15.23 batch44 · 保存后更新 tab 名/URL + 清 dirty
            if !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count {
                tabs[activeIdx].name = url.deletingPathExtension().lastPathComponent
                tabs[activeIdx].fileURL = url
                tabs[activeIdx].isDirty = false
                persistTabs()
            }
            // v15.23 batch47 · 加最近文件
            pushRecentFile(url)
            let formatHint = formatOnSave ? " · 已格式化" : ""
            statusMessage = "已保存到 \(url.lastPathComponent)\(formatHint)"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func copyAllToPasteboard() {
        Pasteboard.copy(sourceText)
        statusMessage = "已复制 \(sourceText.count) 字符到剪贴板"
    }

    /// v15.22 batch22 · 复制为 Markdown 代码块（fenced ```mailang）
    /// trader 分享公式到聊天/笔记 · 自带语言 hint 渲染高亮
    private func copyAsMarkdown() {
        let md = "```mailang\n" + sourceText + "\n```"
        Pasteboard.copy(md)
        statusMessage = "已复制为 Markdown · \(md.count) 字符"
    }

    /// v15.22 batch5 · 编译验证 · 走 IndicatorCore Lexer + Parser · 第一个错误精确定位
    private func compileNow() {
        guard !sourceText.isEmpty else {
            compileResult = "公式为空"
            compileSucceeded = false
            return
        }
        do {
            var lexer = Lexer(source: sourceText)
            let tokens = try lexer.tokenize()
            var parser = Parser(tokens: tokens)
            _ = try parser.parse()
            compileSucceeded = true
            compileResult = "✓ 编译通过 · \(tokens.count - 1) tokens"   // -1 排除 .eof
            errorMarker = nil
            statusMessage = "编译验证通过"
        } catch let err as LexerError {
            compileSucceeded = false
            compileResult = "Lexer 错误：第 \(err.line) 行第 \(err.column) 列 · \(err.message)"
            errorMarker = CodeErrorMarker(line: err.line, column: err.column, length: 1)
            statusMessage = compileResult ?? ""
        } catch let err as ParserError {
            compileSucceeded = false
            compileResult = "Parser 错误：第 \(err.line) 行第 \(err.column) 列 · \(err.message)"
            errorMarker = CodeErrorMarker(line: err.line, column: err.column, length: 1)
            statusMessage = compileResult ?? ""
        } catch {
            compileSucceeded = false
            compileResult = "未知错误：\(error.localizedDescription)"
            errorMarker = nil
            statusMessage = compileResult ?? ""
        }
    }

    /// v15.23 batch41 · 一键格式化公式（⌘⇧F · MaiLangFormatter 纯函数）
    /// 已 idempotent · 二次调用结果不变 · 安全
    private func formatNow() {
        let formatted = MaiLangFormatter.format(sourceText)
        if formatted == sourceText {
            statusMessage = "已格式化 · 无变化"
            return
        }
        sourceText = formatted
        statusMessage = "已格式化"
        // 编译结果可能仍有效 · 但内容变了 · 清掉避免误导
        compileResult = nil
        errorMarker = nil
    }

    /// v15.22 batch15+23 · 注释切换 · 单行（无选区）/ 多行（选区跨行）批量 toggle
    /// - 多行：任一行未注释 → 全部加注释 · 否则全部去注释（VSCode 行为）
    /// - 单行：cursorLine 所在行 toggle
    private func toggleLineComment() {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }

        // 计算行范围 [firstLine, lastLine]（0-based · inclusive）
        let firstLine: Int
        let lastLine: Int
        if selectionRange.length > 0 {
            let nsStr = sourceText as NSString
            firstLine = lineForUtf16(selectionRange.location, in: nsStr)
            // 选区终点 -1 字符避免末尾恰为 \n 时多算下一行
            let endIdx = max(selectionRange.location, NSMaxRange(selectionRange) - 1)
            lastLine = lineForUtf16(endIdx, in: nsStr)
        } else {
            let idx = max(0, min(cursorLine - 1, lines.count - 1))
            firstLine = idx
            lastLine = idx
        }
        let lineRange = max(0, firstLine)...min(lastLine, lines.count - 1)

        // 决定 add/remove · 任一行未注释 → 全加（VSCode 行为）
        let isAdding = lineRange.contains { i in
            let line = lines[i]
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
            return !line.dropFirst(leading.count).hasPrefix("//")
        }

        var newLines = lines
        for i in lineRange {
            let line = lines[i]
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
            let trimmed = line.dropFirst(leading.count)
            if isAdding {
                if !trimmed.hasPrefix("//") {
                    newLines[i] = String(leading) + "// " + String(trimmed)
                }
            } else {
                if trimmed.hasPrefix("// ") {
                    newLines[i] = String(leading) + String(trimmed.dropFirst(3))
                } else if trimmed.hasPrefix("//") {
                    newLines[i] = String(leading) + String(trimmed.dropFirst(2))
                }
            }
        }
        sourceText = newLines.joined(separator: "\n")
        let count = lineRange.count
        statusMessage = isAdding ? "已注释 \(count) 行" : "已取消注释 \(count) 行"
    }

    /// v15.22 batch25 · 缩进 / 反缩进（⌘]/⌘[ · 选区 = 多行批量 · 无选区 = 当前行）
    /// - delta > 0 → 每行前加 4 空格
    /// - delta < 0 → 每行去前 4 空格（或 1 tab · 兼容旧文件）
    private func indentLines(by delta: Int) {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        let nsStr = sourceText as NSString
        let firstLine: Int
        let lastLine: Int
        if selectionRange.length > 0 {
            firstLine = lineForUtf16(selectionRange.location, in: nsStr)
            let endIdx = max(selectionRange.location, NSMaxRange(selectionRange) - 1)
            lastLine = lineForUtf16(endIdx, in: nsStr)
        } else {
            let idx = max(0, min(cursorLine - 1, lines.count - 1))
            firstLine = idx
            lastLine = idx
        }
        let lineRange = max(0, firstLine)...min(lastLine, lines.count - 1)
        var newLines = lines
        for i in lineRange {
            let line = lines[i]
            if delta > 0 {
                newLines[i] = "    " + line
            } else {
                if line.hasPrefix("    ") { newLines[i] = String(line.dropFirst(4)) }
                else if line.hasPrefix("\t") { newLines[i] = String(line.dropFirst(1)) }
            }
        }
        sourceText = newLines.joined(separator: "\n")
        let count = lineRange.count
        statusMessage = delta > 0 ? "缩进 \(count) 行" : "反缩进 \(count) 行"
    }

    /// v15.22 batch29 · 跳转到输入行号（clamp 到 [1, total]）· 触发 MaiLangCodeView updateNSView 跳转
    private func commitGotoLine() {
        guard let raw = Int(gotoLineInput.trimmingCharacters(in: .whitespaces)) else { return }
        let total = textStats(sourceText).lines
        let target = max(1, min(raw, max(1, total)))
        pendingGotoLine = target
        statusMessage = "已跳转到第 \(target) 行"
        showGotoLineSheet = false
    }

    /// utf16 location → 0-based 行号
    private func lineForUtf16(_ loc: Int, in s: NSString) -> Int {
        var line = 0
        let length = min(max(0, loc), s.length)
        for i in 0..<length {
            if s.character(at: i) == 0x0A { line += 1 }
        }
        return line
    }

    /// v15.22 batch17+32 · 删除当前行（⌘⇧K · 选区跨行 = 批量删 · 无选区 = 单行）
    private func deleteCurrentLine() {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        let (firstLine, lastLine) = selectedLineRange(in: lines)
        var newLines = lines
        newLines.removeSubrange(firstLine...lastLine)
        if newLines.isEmpty { newLines = [""] }
        sourceText = newLines.joined(separator: "\n")
        statusMessage = "已删除 \(lastLine - firstLine + 1) 行"
    }

    /// v15.22 batch18+32 · 复制行（⌘D · 选区跨行 = 整段复制粘贴到下方 · 无选区 = 单行）
    private func duplicateCurrentLine() {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        let (firstLine, lastLine) = selectedLineRange(in: lines)
        let block = Array(lines[firstLine...lastLine])
        var newLines = lines
        newLines.insert(contentsOf: block, at: lastLine + 1)
        sourceText = newLines.joined(separator: "\n")
        statusMessage = "已复制 \(block.count) 行"
    }

    /// v15.22 batch32 · 解析选区跨行的 [firstLine, lastLine]（0-based · 复用于多行操作）
    private func selectedLineRange(in lines: [String]) -> (Int, Int) {
        let nsStr = sourceText as NSString
        let first: Int
        let last: Int
        if selectionRange.length > 0 {
            first = lineForUtf16(selectionRange.location, in: nsStr)
            let endIdx = max(selectionRange.location, NSMaxRange(selectionRange) - 1)
            last = lineForUtf16(endIdx, in: nsStr)
        } else {
            let idx = max(0, min(cursorLine - 1, lines.count - 1))
            first = idx
            last = idx
        }
        return (max(0, first), min(last, lines.count - 1))
    }

    /// v15.22 batch19+32 · 上下移动行（⌥↑/⌥↓ · 选区 = 整段批量移 · 无选区 = 单行）
    private func moveCurrentLine(up: Bool) {
        let lines = sourceText.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        let (first, last) = selectedLineRange(in: lines)
        if up {
            guard first > 0 else { return }
            let block = Array(lines[first...last])
            var newLines = lines
            newLines.removeSubrange(first...last)
            newLines.insert(contentsOf: block, at: first - 1)
            sourceText = newLines.joined(separator: "\n")
            cursorLine = first   // 1-based · 上移后块起始 first → first-1 · 光标 first-1+1=first
        } else {
            guard last < lines.count - 1 else { return }
            let block = Array(lines[first...last])
            var newLines = lines
            newLines.removeSubrange(first...last)
            newLines.insert(contentsOf: block, at: first + 1)
            sourceText = newLines.joined(separator: "\n")
            cursorLine = last + 2   // 1-based · 下移后块末尾 last → last+1 · 光标 last+1+1=last+2
        }
        let count = last - first + 1
        statusMessage = up ? "上移 \(count) 行" : "下移 \(count) 行"
    }

    /// v15.22 batch28+35+39 · 函数库单行 row 渲染（搜索/分组共用）· 复制 + 插入到光标
    @ViewBuilder
    private func functionRow(_ sig: MaiLangFunctionSignature) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sig.formatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.accentColor)
                Text(sig.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("插入") {
                // batch39 · 插入到当前光标位置（用 name + 空括号 + 光标暂时停在末尾）
                let snippet = sig.parameters.isEmpty ? sig.name : "\(sig.name)()"
                pendingInsertText = snippet
                showFunctionsPanel = false
                statusMessage = "已插入：\(snippet)"
            }
            .buttonStyle(.borderless)
            .tooltip("插入 \(sig.formatted) 到当前光标位置（关闭面板）")
            Button("复制") {
                Pasteboard.copy(sig.formatted)
                statusMessage = "已复制：\(sig.formatted)"
            }
            .buttonStyle(.borderless)
            .tooltip("复制 \(sig.formatted) 到剪贴板（保持面板打开）")
        }
        .padding(.vertical, 2)
    }

    /// v15.22 batch34 · 编辑器快捷键全集 · 按主题分组（trader 学习参考）
    private static let helpGroups: [(String, [(String, String)])] = [
        ("📁 文件 / 复制", [
            ("⌘O", "打开 .wh / .txt 文件"),
            ("⌘S", "保存为 .wh / .txt（默认自动格式化 · 可在齿轮菜单关闭）"),
            ("⌘⇧C", "复制全文（纯文本）"),
            ("⌘⌥C", "复制为 Markdown 代码块（含 ```mailang fenced）"),
            ("最近文件", "toolbar 时钟图标 · 最近 5 个 · 一键加载到当前 tab"),
        ]),
        ("📑 多 tab（v15.23）", [
            ("⌘⇧N", "新建 tab"),
            ("⌘⇧W", "关闭当前 tab（脏 tab 弹确认）"),
            ("⌘⌥←", "上一个 tab（循环）"),
            ("⌘⌥→", "下一个 tab（循环）"),
            ("点击 tab", "切换 · 内容自动保存"),
            ("双击 tab", "重命名（Enter 保存 · Esc 取消）"),
            ("长按拖动", "重排序 tabs（v15.23 · 拖到目标位置释放）"),
            ("⌘\\", "split 视图开关（v15.23 · 选另一 tab 同屏只读对比）"),
        ]),
        ("🔧 编译 / 格式化 / 学习", [
            ("⌘B", "编译验证（IndicatorCore Lexer + Parser · 错误显示行列）"),
            ("⌘⇧F", "一键格式化（关键字大写 + 空白归一 + 逗号空格 · v15.23）"),
            ("⌘⇧L", "函数库面板（73 函数 9 分类 · 复制签名）"),
            ("⌘⇧?", "本帮助面板"),
        ]),
        ("✏️ 行级编辑（多行选区批量）", [
            ("⌘/", "注释 / 取消注释"),
            ("⌘⇧K", "删除整行"),
            ("⌘D", "复制整行到下方"),
            ("⌥↑ / ⌥↓", "上下移动"),
            ("⌘] / ⌘[", "缩进 / 反缩进 4 空格"),
        ]),
        ("🎯 行级定位", [
            ("⌘L", "跳转到指定行（输入行号）"),
            ("点击行号", "选中整行（左侧 gutter）"),
            ("⌘⇧M", "切换 minimap 缩略图（v15.23 · 拖动 scroll-only · 双击 goto + 移光标 · 4 档宽度）"),
            ("minimap 标记", "🟧未用变量/缺颜色 · 🟥编译错误 · 🟥紧急 lint (undefined/重复定义 · v16.77) · 🟨当前 token 引用"),
            ("lint 行内波浪线 (v16.92)", "整行 dot 波浪线：error 红色（undefined/重复）/ warning 橙色（unused/缺色）"),
            ("status bar", "实时显示光标位置 行:列 · ⚠ 警告数（点击跳第一个）"),
        ]),
        ("🔍 查找", [
            ("⌘F", "查找（NSTextView 内置 find bar · 增量）"),
            ("⌘⌥F", "查找替换"),
            ("⌘G / ⌘⇧G", "下一个 / 上一个匹配"),
        ]),
        ("⌨️ 输入辅助", [
            ("Tab", "插入 4 空格（与 Swift 习惯一致）"),
            ("Enter", "保持上一行缩进"),
            ("Esc / F5 / ⌃Space", "弹出自动补全候选（IDE 标准 ⌃Space · 空 prefix 时弹全部 362 · v16.59）"),
            ("输入 ( [ { ' \"", "自动补对应闭合（光标停中间）"),
            ("⌫", "在配对中按删除 → 同时删两侧（如 (|) → 删空）"),
            ("智能大写", "完整保留字 + 空格/逗号/括号 → 自动转大写"),
        ]),
        ("⚠ Lint 警告 + Quick Fix（v16.60 / v16.66 / v16.98 / v16.109）", [
            ("未使用变量", "🔧 修复 → 删除该行"),
            ("重复定义", "🔧 修复 → 跳到首次定义 / 删除该重复行"),
            ("输出未指定颜色", "🔧 修复 → 插入颜色属性（COLORRED/GREEN/BLUE 等 6 选）"),
            ("未定义标识符 (v16.66)", "🔧 修复 → 跳转 · v16.93 typo 建议 · v16.97 复制 · v16.105 自动替换"),
            ("函数参数数量不符 (v16.98)", "🔧 修复 → 跳转 + 复制正确签名模板"),
            ("变量名疑似 typo (v16.109)", "🔧 修复 → 跳转 + 复制 builtin 名 · ≥ 5 字符 + 距离 1"),
            ("行内波浪线 (v16.92)", "整行 dot · error 红 / warning 橙 · trader 写时即看 · v16.107 可关闭"),
        ]),
        ("🔇 Lint 噪音控制（v16.152 / v16.154 / v16.158 / v16.160 / v16.171 / v16.173）", [
            ("齿轮 Menu severity (v16.152)", "Toggle error / warning 全局开关 · 持久化 @AppStorage"),
            ("chip 切 severity (v16.154)", "outline section 🔴 / 🟡 chip 直接点击 toggle · 与 Menu 共享 state"),
            ("右键 hide kind (v16.158)", "lint 行右键 → 本会话隐藏「未使用变量」类 · 不持久化"),
            ("已隐藏 chip 行 (v16.158)", "顶部「已隐藏：[kind ⤺]」· 点击 chip 单独恢复"),
            ("全部恢复 (v16.160)", "≥ 2 已隐藏时显示「全部恢复」button · 一键清空"),
            ("仅看 error (v16.173)", "一键隐藏全部 warning 类 · 聚焦紧急"),
            ("⌘W 关闭 sheet (v16.171)", "outline sheet macOS 标准 ⌘W · 与 ESC 互补"),
        ]),
    ]

    // MARK: - v16.158 · kind 中文标签（context menu / 已隐藏 chip 共用）

    private func lintKindLabel(_ kind: MaiLangLintWarning.Kind) -> String {
        switch kind {
        case .unusedVariable:        return "未使用变量"
        case .duplicateDefinition:   return "重复定义"
        case .missingColorAttribute: return "缺 COLOR 属性"
        case .undefinedVariable:     return "未定义引用"
        case .argCountMismatch:      return "参数数量不符"
        case .suspiciousVariableName: return "疑似 typo 变量"
        }
    }

    // MARK: - v16.154 · severity 过滤 chip（outline section · 直接点击 toggle）

    /// chip 视觉态：isOn 时实色 · isOff 时灰色描边 · 点击切 toggle
    private func severityFilterChip(label: String, isOn: Bool, tip: String,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.orange.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isOn ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.3),
                                       lineWidth: 1)
                )
                .foregroundColor(isOn ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .tooltip(tip)
    }

    // MARK: - v16.60 · Lint quick fix Menu（按 warning kind 提供针对性修复）

    @ViewBuilder
    private func quickFixMenu(for warn: MaiLangLintWarning) -> some View {
        Menu {
            switch warn.kind {
            case .unusedVariable:
                Button {
                    quickFixDeleteLine(warn.line)
                    statusMessage = "已删除第 \(warn.line) 行"
                } label: {
                    Label("删除该行", systemImage: "trash")
                }
            case .duplicateDefinition:
                if let firstLine = parseFirstDefinedLine(from: warn.message) {
                    Button {
                        pendingGotoLine = firstLine
                        showOutlineSheet = false
                        statusMessage = "跳到首次定义（第 \(firstLine) 行）"
                    } label: {
                        Label("跳到首次定义（第 \(firstLine) 行）", systemImage: "arrow.up.right.circle")
                    }
                }
                Button(role: .destructive) {
                    quickFixDeleteLine(warn.line)
                    statusMessage = "已删除重复定义（第 \(warn.line) 行）"
                } label: {
                    Label("删除该重复定义行", systemImage: "trash")
                }
            case .missingColorAttribute:
                Menu {
                    ForEach(["COLORRED", "COLORGREEN", "COLORBLUE",
                             "COLORYELLOW", "COLORMAGENTA", "COLORWHITE"], id: \.self) { color in
                        Button(color) {
                            quickFixInsertColor(warn.line, color: color)
                            statusMessage = "已插入 \(color)"
                        }
                    }
                } label: {
                    Label("插入颜色属性", systemImage: "paintpalette")
                }
            case .undefinedVariable:
                // 仅跳转 · trader 自己决定是定义还是改名（无机械修复方案）
                Button {
                    pendingGotoLine = warn.line
                    showOutlineSheet = false
                    statusMessage = "跳到第 \(warn.line) 行 · 检查标识符拼写或补定义"
                } label: {
                    Label("跳转检查拼写", systemImage: "magnifyingglass")
                }
                // v16.97 · 若 message 含 typo 建议 · 加复制按钮（trader 手动替换免输错）
                if let suggestion = parseTypoSuggestion(from: warn.message) {
                    // v16.105 · 真正的 quick fix：直接替换该行第一处 undefined identifier
                    if let undefName = parseUndefinedName(from: warn.message) {
                        Button {
                            quickFixReplaceInLine(warn.line, oldName: undefName, newName: suggestion)
                            statusMessage = "已替换 \(undefName) → \(suggestion)（第 \(warn.line) 行）"
                        } label: {
                            Label("替换为 \(suggestion)", systemImage: "wand.and.stars")
                        }
                    }
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(suggestion, forType: .string)
                        statusMessage = "已复制建议 \(suggestion) 到剪贴板"
                    } label: {
                        Label("复制建议 \(suggestion)", systemImage: "doc.on.doc")
                    }
                }
            case .argCountMismatch:
                // v16.98 · 参数数量不符 · 跳转 + 复制正确签名模板
                Button {
                    pendingGotoLine = warn.line
                    showOutlineSheet = false
                    statusMessage = "跳到第 \(warn.line) 行 · \(warn.message)"
                } label: {
                    Label("跳转检查参数", systemImage: "magnifyingglass")
                }
                if let template = parseArgSignatureTemplate(from: warn.message) {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(template, forType: .string)
                        statusMessage = "已复制签名模板：\(template)"
                    } label: {
                        Label("复制签名模板", systemImage: "doc.on.doc")
                    }
                }
            case .suspiciousVariableName:
                // v16.109 · 变量定义名 typo 嫌疑 · 跳转 + 提示建议名（无机械修复 · trader 自决）
                Button {
                    pendingGotoLine = warn.line
                    showOutlineSheet = false
                    statusMessage = "跳到第 \(warn.line) 行 · 检查变量名是否 typo"
                } label: {
                    Label("跳转检查变量名", systemImage: "magnifyingglass")
                }
                if let close = parseSuspiciousCloseName(from: warn.message) {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(close, forType: .string)
                        statusMessage = "已复制 builtin 名 \(close)"
                    } label: {
                        Label("复制 builtin 名 \(close)", systemImage: "doc.on.doc")
                    }
                }
            }
        } label: {
            Label("修复", systemImage: "wand.and.stars")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 60)
        .tooltip("快速修复该 lint 警告")
    }

    /// 从 "重复定义：X（首次定义在第 N 行）" 提取 N
    private func parseFirstDefinedLine(from message: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"第\s*(\d+)\s*行"#) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    /// v16.97 · 从 v16.93 typo 建议 message "可能是 `X`?" 提取 X
    private func parseTypoSuggestion(from message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"可能是 `([A-Z_][A-Z0-9_]*)`"#) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// v16.98 · 从 argCountMismatch message 提取签名模板（"签名：MA(序列, 周期 N)" → "MA(序列, 周期 N)"）
    private func parseArgSignatureTemplate(from message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"签名：([^）]+\))"#) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// v16.105 · 从 undefinedVariable message 提取标识符名（"未定义的标识符 FOOBAR(...)" → "FOOBAR"）
    private func parseUndefinedName(from message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"未定义的标识符 ([A-Za-z_][A-Za-z0-9_]*)"#) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// v16.109 · 从 suspiciousVariableName message 提取 close builtin 名（"与 builtin/keyword `X` 仅差..." → X）
    private func parseSuspiciousCloseName(from message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"`([A-Z_][A-Z0-9_]*)`"#) else { return nil }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// v16.105 · 替换指定行内首次出现的 oldName → newName（word boundary 保护 · 防误替换子串）
    private func quickFixReplaceInLine(_ lineNumber: Int, oldName: String, newName: String) {
        var lines = sourceText.components(separatedBy: "\n")
        guard lineNumber >= 1, lineNumber <= lines.count else { return }
        let lineContent = lines[lineNumber - 1]
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: oldName))\\b") else { return }
        let ns = lineContent as NSString
        guard let m = regex.firstMatch(in: lineContent, range: NSRange(location: 0, length: ns.length)) else { return }
        lines[lineNumber - 1] = ns.replacingCharacters(in: m.range, with: newName)
        sourceText = lines.joined(separator: "\n")
    }

    /// 删除 sourceText 第 N 行（1-based · 越界保护）
    private func quickFixDeleteLine(_ lineNumber: Int) {
        var lines = sourceText.components(separatedBy: "\n")
        guard lineNumber >= 1, lineNumber <= lines.count else { return }
        lines.remove(at: lineNumber - 1)
        sourceText = lines.joined(separator: "\n")
    }

    /// v16.113 · 批量删除多行（从后往前避免行号偏移）
    private func quickFixDeleteLinesBatch(_ lineNumbers: [Int]) {
        var lines = sourceText.components(separatedBy: "\n")
        // 倒序删除（从大到小）避免索引偏移
        for ln in lineNumbers.sorted(by: >) {
            guard ln >= 1, ln <= lines.count else { continue }
            lines.remove(at: ln - 1)
        }
        sourceText = lines.joined(separator: "\n")
    }

    /// 在 sourceText 第 N 行末追加 ,COLORxxx · 自动判断 ; 前还是行末
    private func quickFixInsertColor(_ lineNumber: Int, color: String) {
        var lines = sourceText.components(separatedBy: "\n")
        guard lineNumber >= 1, lineNumber <= lines.count else { return }
        var content = lines[lineNumber - 1]
        if let semiRange = content.range(of: ";", options: .backwards) {
            content.insert(contentsOf: ",\(color)", at: semiRange.lowerBound)
        } else {
            // 无分号 · 行末追加
            content += ",\(color)"
        }
        lines[lineNumber - 1] = content
        sourceText = lines.joined(separator: "\n")
    }

    /// v15.23 batch153 · 复制大纲为 markdown（变量列表 + 警告 + 依赖）
    private func copyOutlineMarkdown(outline: [MaiLangOutlineEntry],
                                     warns: [MaiLangLintWarning],
                                     deps: [String: MaiLangVarDependency]) {
        var md = "# 公式大纲\n\n"
        if outline.isEmpty && warns.isEmpty {
            md += "_暂无变量定义_\n"
        } else {
            if !outline.isEmpty {
                md += "## 变量（\(outline.count)）\n\n"
                for entry in outline {
                    let typeLabel = entry.isOutput ? "输出" : "中间"
                    md += "- L\(entry.line) · `\(entry.name)` (\(typeLabel))"
                    if let d = deps[entry.name.uppercased()] {
                        if !d.uses.isEmpty {
                            md += " → uses: \(d.uses.joined(separator: ", "))"
                        }
                        if !d.usedBy.isEmpty {
                            md += " ← usedBy: \(d.usedBy.joined(separator: ", "))"
                        }
                    }
                    md += "\n"
                }
                md += "\n"
            }
            if !warns.isEmpty {
                md += "## ⚠ Lint 警告（\(warns.count)）\n\n"
                for w in warns {
                    md += "- L\(w.line) · \(w.message)\n"
                }
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        statusMessage = "已复制大纲（\(md.count) 字符 markdown）"
    }

    /// v15.23 batch108 · 当前选区起止行号（1-based · selection.length == 0 返回 nil）· minimap 选区高亮用
    private func minimapSelectionLineRange() -> (Int, Int)? {
        guard selectionRange.length > 0 else { return nil }
        let ns = sourceText as NSString
        let startLine = MaiLangCodeView.lineNumber(forUTF16Loc: selectionRange.location, in: ns)
        let endLoc = max(selectionRange.location, NSMaxRange(selectionRange) - 1)
        let endLine = MaiLangCodeView.lineNumber(forUTF16Loc: endLoc, in: ns)
        return (startLine, endLine)
    }

    private func textStats(_ s: String) -> (chars: Int, lines: Int) {
        let chars = s.count
        let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
        return (chars, lines)
    }

    // MARK: - v15.23 batch43-44 · 多 tab 操作

    /// 初始化 tabs（从 @AppStorage 反序列化 · 空则用当前 sourceText 包装一个 tab）
    func loadTabsIfNeeded() {
        guard tabs.isEmpty else { return }
        if !tabsJSON.isEmpty,
           let data = tabsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([FormulaTab].self, from: data),
           !decoded.isEmpty {
            tabs = decoded
            activeIdx = max(0, min(activeTabIdxStored, decoded.count - 1))
            // 同步 active tab 内容到 sourceText（持久化的 sourceText 可能落后）
            sourceText = tabs[activeIdx].content
        } else {
            tabs = [FormulaTab(name: "公式 1", content: sourceText, isDirty: false)]
            activeIdx = 0
        }
    }

    /// 当前 sourceText 镜像写回 active tab · 持久化
    func syncActiveTab() {
        guard !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count else { return }
        if tabs[activeIdx].content != sourceText {
            tabs[activeIdx].content = sourceText
            tabs[activeIdx].isDirty = true
        }
        persistTabs()
    }

    func persistTabs() {
        if let data = try? JSONEncoder().encode(tabs),
           let s = String(data: data, encoding: .utf8) {
            tabsJSON = s
        }
        activeTabIdxStored = activeIdx
    }

    /// 切到指定 tab（保存当前 sourceText 到旧 tab · 加载新 tab 内容）
    func switchToTab(_ idx: Int) {
        guard idx >= 0, idx < tabs.count, idx != activeIdx else { return }
        // 保存当前
        tabs[activeIdx].content = sourceText
        // 切换
        activeIdx = idx
        sourceText = tabs[idx].content
        // 清编辑器状态
        compileResult = nil
        errorMarker = nil
        statusMessage = "切到 · \(tabs[idx].name)"
        persistTabs()
    }

    /// 新建 tab（追加 · 自动切到新 tab）
    func newTab() {
        // 保存当前
        tabs[activeIdx].content = sourceText
        let nextNumber = (tabs.compactMap { Int($0.name.replacingOccurrences(of: "公式 ", with: "")) }.max() ?? 0) + 1
        let fresh = FormulaTab(name: "公式 \(nextNumber)", content: "", isDirty: false)
        tabs.append(fresh)
        activeIdx = tabs.count - 1
        sourceText = ""
        compileResult = nil
        errorMarker = nil
        statusMessage = "新建 · \(fresh.name)"
        persistTabs()
    }

    /// 关闭指定 tab（脏 tab 弹确认）· 关闭后自动切到相邻 tab · 唯一 tab 不允许关闭
    func closeTab(_ idx: Int) {
        guard idx >= 0, idx < tabs.count, tabs.count > 1 else {
            statusMessage = tabs.count <= 1 ? "至少保留 1 个 tab" : ""
            return
        }
        if tabs[idx].isDirty && idx == activeIdx {
            pendingCloseIdx = idx
            return
        }
        confirmCloseTab(idx)
    }

    /// 实际关闭 tab（已确认）
    func confirmCloseTab(_ idx: Int) {
        guard idx >= 0, idx < tabs.count, tabs.count > 1 else { return }
        let wasActive = idx == activeIdx
        tabs.remove(at: idx)
        if wasActive {
            activeIdx = max(0, min(idx, tabs.count - 1))
            sourceText = tabs[activeIdx].content
            compileResult = nil
            errorMarker = nil
        } else if idx < activeIdx {
            activeIdx -= 1
        }
        statusMessage = "已关闭 tab"
        persistTabs()
    }

    /// 切换到上一个 / 下一个 tab（循环）
    func switchPrev() {
        guard tabs.count > 1 else { return }
        let next = (activeIdx - 1 + tabs.count) % tabs.count
        switchToTab(next)
    }

    func switchNext() {
        guard tabs.count > 1 else { return }
        let next = (activeIdx + 1) % tabs.count
        switchToTab(next)
    }

    /// v15.23 batch46 · 重命名 tab（双击触发 · 不影响 fileURL）
    func renameTab(_ idx: Int, to newName: String) {
        guard idx >= 0, idx < tabs.count else { return }
        tabs[idx].name = newName
        persistTabs()
        statusMessage = "已重命名为 \(newName)"
    }

    // MARK: - v15.23 batch47 · 最近文件历史

    /// 当前最近文件列表（JSON 反序列化）· 最新在前 · cap 5
    var recentFiles: [URL] {
        guard !recentFilesJSON.isEmpty,
              let data = recentFilesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([URL].self, from: data) else {
            return []
        }
        return arr
    }

    /// 把 url push 到最近文件（已存在则提到首位 · cap 5）
    func pushRecentFile(_ url: URL) {
        var list = recentFiles
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        if let data = try? JSONEncoder().encode(list),
           let s = String(data: data, encoding: .utf8) {
            recentFilesJSON = s
        }
    }

    /// 加载指定路径到当前 tab（不影响其他 tab）· 文件不存在 → 状态栏提示
    func loadRecentFile(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            sourceText = text
            if !tabs.isEmpty, activeIdx >= 0, activeIdx < tabs.count {
                tabs[activeIdx].name = url.deletingPathExtension().lastPathComponent
                tabs[activeIdx].fileURL = url
                tabs[activeIdx].isDirty = false
                persistTabs()
            }
            pushRecentFile(url)
            statusMessage = "已加载最近 · \(url.lastPathComponent)"
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription) · 已从最近列表移除"
            // 清掉无效条目
            var list = recentFiles
            list.removeAll { $0 == url }
            if let data = try? JSONEncoder().encode(list),
               let s = String(data: data, encoding: .utf8) {
                recentFilesJSON = s
            }
        }
    }

    /// 清空最近文件列表
    func clearRecentFiles() {
        recentFilesJSON = ""
        statusMessage = "已清空最近文件"
    }
}

// MARK: - v15.23 batch43 · FormulaTab 数据模型（Codable 持久化 · @AppStorage JSON）

struct FormulaTab: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var content: String
    var fileURL: URL?
    var isDirty: Bool

    init(id: UUID = UUID(), name: String, content: String,
         fileURL: URL? = nil, isDirty: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.fileURL = fileURL
        self.isDirty = isDirty
    }
}

// MARK: - v15.23 batch43 · Tab Bar 子视图

struct FormulaTabBar: View {
    @Binding var tabs: [FormulaTab]
    @Binding var activeIdx: Int
    let onSwitch: (Int) -> Void
    let onNew: () -> Void
    let onClose: (Int) -> Void
    let onRename: (Int, String) -> Void
    /// v15.23 batch117 · 重排序后回调（持久化 tabsJSON · 父视图实现）
    var onReorder: (() -> Void)? = nil

    /// v15.23 batch46 · 当前重命名中的 tab 索引（nil = 无）
    @State private var renamingIdx: Int? = nil
    @State private var renameDraft: String = ""
    /// v15.23 batch117 · 拖动中的 tab（nil = 无 · 用于 DropDelegate 识别 source）
    @State private var draggedTab: FormulaTab? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                    tabPill(idx: idx, tab: tab)
                }
                Button {
                    onNew()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .tooltip("新建 tab（⌘⇧N）")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func tabPill(idx: Int, tab: FormulaTab) -> some View {
        let isActive = idx == activeIdx
        let isRenaming = renamingIdx == idx
        HStack(spacing: 4) {
            if isRenaming {
                TextField("名称", text: $renameDraft, onCommit: {
                    commitRename(idx)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 100)
                .onExitCommand { cancelRename() }
            } else {
                Text(tab.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
            }
            if tab.isDirty {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            if tabs.count > 1 && !isRenaming {
                Button {
                    onClose(idx)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .tooltip("关闭（⌘⇧W）")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive
                    ? Color.accentColor.opacity(0.18)
                    : Color.secondary.opacity(0.06))
        .cornerRadius(5)
        .opacity(draggedTab?.id == tab.id ? 0.4 : 1)
        .onTapGesture(count: 2) {
            // v15.23 batch46 · 双击进入重命名
            startRename(idx, current: tab.name)
        }
        .onTapGesture {
            if !isRenaming { onSwitch(idx) }
        }
        // v15.23 batch117 · 长按拖动重排序（不与 tap/double-tap 冲突 · NSItemProvider 标准 drag）
        .onDrag {
            draggedTab = tab
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: ["public.text"],
                delegate: TabReorderDropDelegate(item: tab,
                                                 tabs: $tabs,
                                                 draggedTab: $draggedTab,
                                                 activeIdx: $activeIdx,
                                                 onReorderEnd: { onReorder?() }))
    }

    // MARK: - v15.23 batch46 · 重命名操作

    private func startRename(_ idx: Int, current: String) {
        renamingIdx = idx
        renameDraft = current
    }

    private func commitRename(_ idx: Int) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, idx < tabs.count, trimmed != tabs[idx].name {
            onRename(idx, trimmed)
        }
        renamingIdx = nil
        renameDraft = ""
    }

    private func cancelRename() {
        renamingIdx = nil
        renameDraft = ""
    }
}

// MARK: - v15.23 batch117 · Tab 拖动重排序 DropDelegate

private struct TabReorderDropDelegate: DropDelegate {
    let item: FormulaTab
    @Binding var tabs: [FormulaTab]
    @Binding var draggedTab: FormulaTab?
    @Binding var activeIdx: Int
    let onReorderEnd: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedTab,
              dragged.id != item.id,
              let from = tabs.firstIndex(where: { $0.id == dragged.id }),
              let to = tabs.firstIndex(where: { $0.id == item.id }) else { return }
        // 维持 active tab：先记录其 ID · 移动后再 firstIndex 查回新位置
        let activeID: UUID? = (activeIdx >= 0 && activeIdx < tabs.count) ? tabs[activeIdx].id : nil
        withAnimation(.easeInOut(duration: 0.15)) {
            tabs.move(fromOffsets: IndexSet(integer: from),
                      toOffset: to > from ? to + 1 : to)
        }
        if let aid = activeID, let newIdx = tabs.firstIndex(where: { $0.id == aid }) {
            activeIdx = newIdx
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTab = nil
        onReorderEnd()
        return true
    }
}

#endif
