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
    /// v15.22 batch7 · 片段库 · 用户自定义公式模板（JSON 持久化 · 跨会话保留）
    @AppStorage("viewState.v1.formulaEditor.snippets") private var snippetsJSON: String = ""
    @State private var statusMessage: String = "未保存修改"
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
    /// v15.22 batch28 · 函数列表面板（⌘⇧L 切换 · 73 函数 9 分类）
    @State private var showFunctionsPanel: Bool = false

    private var scheme: SyntaxColorScheme {
        schemeRaw == "light" ? .light : .dark
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            MaiLangCodeView(text: $sourceText, scheme: scheme, errorMarker: errorMarker,
                            onCursorChange: { line, col in
                                cursorLine = line
                                cursorCol = col
                            },
                            onSelectionChange: { range in selectionRange = range },
                            onTokenAtCursor: { name in
                                if let n = name?.uppercased(),
                                   let s = MaiLangFunctionSignatures.all[n] {
                                    currentTokenSig = s.formatted
                                } else {
                                    currentTokenSig = nil
                                }
                            })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: sourceText) { _ in
                    // v15.22 batch6 · 用户改动后清错误标注（防陈旧 marker 误导）
                    if errorMarker != nil { errorMarker = nil }
                    if compileResult != nil { compileResult = nil }
                }
            Divider()
            statusBar
        }
        .frame(minWidth: 720, idealWidth: 920, minHeight: 480, idealHeight: 640)
        // v15.22 batch28 · 函数库 sheet（73 函数按 9 分类 List · 一键复制签名）
        .sheet(isPresented: $showFunctionsPanel) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("📚 麦语言函数库").font(.title2).bold()
                    Text("(\(MaiLangFunctionSignatures.entries.count) 个函数 · 9 大类)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("关闭") { showFunctionsPanel = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(12)
                Divider()
                List {
                    ForEach(MaiLangFunctionSignatures.byCategory, id: \.0) { (cat, sigs) in
                        Section(header: Text(cat.rawValue).font(.headline)) {
                            ForEach(sigs, id: \.name) { sig in
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
                                    Button("复制") {
                                        Pasteboard.copy(sig.formatted)
                                        statusMessage = "已复制：\(sig.formatted)"
                                    }
                                    .buttonStyle(.borderless)
                                    .help("复制 \(sig.formatted) 到剪贴板（再粘贴到编辑器）")
                                }
                                .padding(.vertical, 2)
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
            .help("从 .wh / .txt 文件加载（⌘O）")
            Button {
                saveFile()
            } label: {
                Label("保存为 .wh", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(sourceText.isEmpty)
            .help("保存到 .wh / .txt 文件（⌘S）")
            Menu {
                Button("复制全文（纯文本）") { copyAllToPasteboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                // v15.22 batch22 · 导出 Markdown 代码块（trader 分享聊天/笔记常用）
                Button("复制为 Markdown 代码块") { copyAsMarkdown() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .help("复制公式（⌘⇧C 纯文本 / ⌘⌥C Markdown 代码块）")
            // v15.22 batch5 · 编译验证（⌘B · 走 IndicatorCore Lexer + Parser · 第一个错误精确定位）
            Button {
                compileNow()
            } label: {
                Label("编译验证", systemImage: "checkmark.shield")
            }
            .keyboardShortcut("b", modifiers: [.command])
            .help("用 IndicatorCore Lexer + Parser 验证公式 · 错误显示行列（⌘B）")
            // v15.22 batch15 · 注释切换（⌘/ · 麦语言行注释 // · 当前行 toggle）
            Button {
                toggleLineComment()
            } label: {
                Label("注释切换", systemImage: "text.append")
            }
            .keyboardShortcut("/", modifiers: [.command])
            .help("注释 / 取消注释当前行（⌘/）")
            // v15.22 batch17 · 删除当前行（⌘⇧K · VSCode 经典）
            Button {
                deleteCurrentLine()
            } label: {
                Label("删除行", systemImage: "minus.rectangle")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .help("删除当前光标所在行（⌘⇧K）")
            // v15.22 batch18 · 复制当前行到下一行（⌘D · VSCode/Sublime 经典）
            Button {
                duplicateCurrentLine()
            } label: {
                Label("复制行", systemImage: "plus.rectangle.on.rectangle")
            }
            .keyboardShortcut("d", modifiers: [.command])
            .help("复制当前光标所在行到下一行（⌘D）")
            // v15.22 batch19 · 上下移动当前行（⌥↑/⌥↓ · VSCode/Sublime 经典）
            Button { moveCurrentLine(up: true) } label: { Image(systemName: "arrow.up.square") }
                .keyboardShortcut(.upArrow, modifiers: [.option])
                .help("当前行上移（⌥↑）")
            Button { moveCurrentLine(up: false) } label: { Image(systemName: "arrow.down.square") }
                .keyboardShortcut(.downArrow, modifiers: [.option])
                .help("当前行下移（⌥↓）")
            // v15.22 batch25 · 缩进/反缩进选中行（⌘]/⌘[ · VSCode 经典）
            Button { indentLines(by: 1) } label: { Image(systemName: "increase.indent") }
                .keyboardShortcut("]", modifiers: [.command])
                .help("缩进选中行（⌘]）")
            Button { indentLines(by: -1) } label: { Image(systemName: "decrease.indent") }
                .keyboardShortcut("[", modifiers: [.command])
                .help("反缩进选中行（⌘[）")
            // v15.22 batch28 · 函数库面板（73 函数 9 分类 · 浏览 + 复制函数签名）
            Button {
                showFunctionsPanel = true
            } label: {
                Label("函数库", systemImage: "function")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .help("浏览 73 个内置函数（⌘⇧L · 按分类 · 复制签名）")
            // v15.22 batch8 · 内置示例公式 Menu（trader 学习 · 一键加载标准实现）
            Menu {
                ForEach(Self.builtinExamples, id: \.name) { ex in
                    Button(ex.name) {
                        sourceText = ex.text
                        statusMessage = "已加载示例：\(ex.name)"
                    }
                    .help(ex.description)
                }
            } label: {
                Label("示例", systemImage: "books.vertical.fill")
            }
            .help("加载内置标准公式示例（MACD / KDJ / RSI / BOLL 等）")
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
            .help("保存当前公式为命名片段 / 加载已存片段（@AppStorage 持久化）")
            Spacer()
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
            // 字符数 / 行数
            let stats = textStats(sourceText)
            Text("行数 \(stats.lines)").font(.caption).foregroundColor(.secondary)
            Text("字符 \(stats.chars)").font(.caption).foregroundColor(.secondary)
            // v15.22 batch11 · 当前光标位置（行:列 · 与编译错误的"第 N 行第 M 列"对齐 trader 直接定位）
            Text("光标 \(cursorLine):\(cursorCol)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .help("当前光标位置（行:列 · 与编译错误定位对齐）")
            // v15.22 batch27 · 当前光标 token 函数签名（与 batch26 静态表联动 · IDE 教学体验）
            if let sig = currentTokenSig {
                Text("📖 \(sig)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("当前光标处函数签名（参考 batch26 内置签名表 · 73 个函数）")
            }
            // token 数（与 highlighter 同源）
            let tokenCount = MaiLangSyntaxHighlighter.tokenize(sourceText).count
            Text("token \(tokenCount)").font(.caption).foregroundColor(.secondary)
            // v15.22 batch5 · 编译状态 chip
            if let result = compileResult {
                Image(systemName: compileSucceeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundColor(compileSucceeded ? .green : .red)
                Text(result)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(compileSucceeded ? .green : .red)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        panel.title = "打开 .wh / 文本公式"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            sourceText = text
            statusMessage = "已加载 \(url.lastPathComponent) · \(text.count) 字符"
        } catch {
            statusMessage = "打开失败：\(error.localizedDescription)"
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.title = "保存麦语言公式"
        panel.allowedContentTypes = [.plainText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "formula_\(dateFmt.string(from: Date())).wh"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sourceText.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "已保存到 \(url.lastPathComponent)"
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

    /// utf16 location → 0-based 行号
    private func lineForUtf16(_ loc: Int, in s: NSString) -> Int {
        var line = 0
        let length = min(max(0, loc), s.length)
        for i in 0..<length {
            if s.character(at: i) == 0x0A { line += 1 }
        }
        return line
    }

    /// v15.22 batch17 · 删除当前光标所在行（⌘⇧K · 删空时保留 1 个空行避免 [].joined 异常）
    private func deleteCurrentLine() {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        let idx = max(0, min(cursorLine - 1, lines.count - 1))
        var newLines = lines
        newLines.remove(at: idx)
        if newLines.isEmpty { newLines = [""] }
        sourceText = newLines.joined(separator: "\n")
        statusMessage = "已删除第 \(idx + 1) 行"
    }

    /// v15.22 batch18 · 复制当前行到下一行（⌘D · trader 改参数前留备份常用）
    private func duplicateCurrentLine() {
        let lines = sourceText.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        let idx = max(0, min(cursorLine - 1, lines.count - 1))
        var newLines = lines
        newLines.insert(lines[idx], at: idx + 1)
        sourceText = newLines.joined(separator: "\n")
        statusMessage = "已复制第 \(idx + 1) 行"
    }

    /// v15.22 batch19 · 上下移动当前行（⌥↑/⌥↓ · trader 调整公式顺序常用）
    private func moveCurrentLine(up: Bool) {
        let lines = sourceText.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        let idx = max(0, min(cursorLine - 1, lines.count - 1))
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < lines.count else { return }
        var newLines = lines
        newLines.swapAt(idx, target)
        sourceText = newLines.joined(separator: "\n")
        cursorLine = target + 1   // 1-based · 跟随移动
        statusMessage = up ? "第 \(idx + 1) 行上移" : "第 \(idx + 1) 行下移"
    }

    private func textStats(_ s: String) -> (chars: Int, lines: Int) {
        let chars = s.count
        let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
        return (chars, lines)
    }
}
#endif
