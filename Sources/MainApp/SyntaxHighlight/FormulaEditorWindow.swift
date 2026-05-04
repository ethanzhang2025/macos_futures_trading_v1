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

    private var scheme: SyntaxColorScheme {
        schemeRaw == "light" ? .light : .dark
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            MaiLangCodeView(text: $sourceText, scheme: scheme, errorMarker: errorMarker)
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
            Button {
                copyAllToPasteboard()
            } label: {
                Label("复制全文", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("复制全部公式到剪贴板（⌘⇧C）")
            // v15.22 batch5 · 编译验证（⌘B · 走 IndicatorCore Lexer + Parser · 第一个错误精确定位）
            Button {
                compileNow()
            } label: {
                Label("编译验证", systemImage: "checkmark.shield")
            }
            .keyboardShortcut("b", modifiers: [.command])
            .help("用 IndicatorCore Lexer + Parser 验证公式 · 错误显示行列（⌘B）")
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

    private func textStats(_ s: String) -> (chars: Int, lines: Int) {
        let chars = s.count
        let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
        return (chars, lines)
    }
}
#endif
