// WP-65 v15.22 batch3 · 麦语言代码编辑器 SwiftUI 包装
// NSTextView NSViewRepresentable · 实时 syntax 高亮 · 与 ChartScene NSColor 用法一致（macOS only）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import Shared

/// 编辑器错误标注（行/列 1-based · length token 长度）· v15.22 batch6
public struct CodeErrorMarker: Equatable, Sendable {
    public let line: Int      // 1-based
    public let column: Int    // 1-based
    public let length: Int    // 错误 token 长度（默认 1）
    public init(line: Int, column: Int, length: Int = 1) {
        self.line = line; self.column = column; self.length = length
    }
}

/// SwiftUI 麦语言代码编辑器 · 实时 syntax 高亮 + 双 binding 同步
public struct MaiLangCodeView: NSViewRepresentable {
    @Binding var text: String
    let scheme: SyntaxColorScheme
    let fontSize: CGFloat
    let errorMarker: CodeErrorMarker?
    /// v15.23 batch129 · 是否允许编辑（split 视图右 pane 设 false · 仅看不动 · 仍可选中复制）
    let isEditable: Bool
    /// v15.22 batch11 · 光标位置回调（line/col 均 1-based · 用于 status bar 显示当前位置）
    let onCursorChange: ((Int, Int) -> Void)?
    /// v15.22 batch23 · 选区范围回调（NSRange · 用于多行 ⌘/ 批量注释等需要 selection 的操作）
    let onSelectionChange: ((NSRange) -> Void)?
    /// v15.22 batch27 · 当前光标处 token 文本回调（nil = 无 token · 用于 status bar 函数签名实时显示）
    let onTokenAtCursor: ((String?) -> Void)?
    /// v15.22 batch29 · 跳转到指定行（1-based · 设非 nil 触发 updateNSView 跳转后自动清回 nil）
    /// 含 setSelectedRange + makeFirstResponder · 用于「跳转到行」sheet / outline 跳转
    @Binding var pendingGotoLine: Int?
    /// v15.22 batch39 · 插入文本到当前光标位置（设非 nil 触发 updateNSView 插入后自动清回 nil）
    @Binding var pendingInsertText: String?
    /// v15.23 batch107 · 仅滚动到指定行（不动光标 / 不抢 firstResponder · minimap 拖动用）
    @Binding var pendingScrollToLine: Int?
    /// v15.23 batch106 · 可视行回调（first/last 1-based · 监听 NSScrollView 滚动 + 文本变化）· minimap viewport 高亮用
    let onVisibleLinesChange: ((Int, Int) -> Void)?

    public init(text: Binding<String>, scheme: SyntaxColorScheme = .dark,
                fontSize: CGFloat = 13, errorMarker: CodeErrorMarker? = nil,
                isEditable: Bool = true,
                onCursorChange: ((Int, Int) -> Void)? = nil,
                onSelectionChange: ((NSRange) -> Void)? = nil,
                onTokenAtCursor: ((String?) -> Void)? = nil,
                pendingGotoLine: Binding<Int?> = .constant(nil),
                pendingInsertText: Binding<String?> = .constant(nil),
                pendingScrollToLine: Binding<Int?> = .constant(nil),
                onVisibleLinesChange: ((Int, Int) -> Void)? = nil) {
        self._text = text
        self.scheme = scheme
        self.fontSize = fontSize
        self.errorMarker = errorMarker
        self.isEditable = isEditable
        self.onCursorChange = onCursorChange
        self.onSelectionChange = onSelectionChange
        self.onTokenAtCursor = onTokenAtCursor
        self._pendingGotoLine = pendingGotoLine
        self._pendingInsertText = pendingInsertText
        self._pendingScrollToLine = pendingScrollToLine
        self.onVisibleLinesChange = onVisibleLinesChange
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        // v15.23 batch129 · split 视图右 pane 设 false 仅看不动 · 仍可选中复制
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false   // 防"智能"引号破坏字符串
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        // v15.22 batch30 · 启用 NSTextView 内置 find bar（⌘F 查找 · ⌘⌥F 查找替换 · trader 长公式标配）
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // v15.22 batch20 · 行号 gutter（NSRulerView · 与编译错误"第 N 行"对齐）
        let ruler = LineNumberRulerView(textView: tv, fontSize: fontSize)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        applyTheme(to: tv)
        // 初始文本
        tv.string = text
        applyHighlight(to: tv)
        // v15.23 batch106 · 监听滚动 → 报当前可视行（minimap viewport 高亮用）
        context.coordinator.attachVisibleLinesObserver(scrollView: scrollView, textView: tv)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // batch129 · 同步 isEditable 变化（toggle split 时切换）
        if tv.isEditable != isEditable { tv.isEditable = isEditable }
        // 外部 text 变化（如 sheet 重新打开）→ 同步
        if tv.string != text {
            let cursor = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(cursor.location, text.utf16.count), length: 0))
        }
        // v15.22 batch36 · 字号变化 → 同步 NSTextView.font（typing 字号 · applyHighlight 内会刷已有字符）
        if abs((tv.font?.pointSize ?? 0) - fontSize) > 0.1 {
            tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        applyTheme(to: tv)
        applyHighlight(to: tv)
        // v15.22 batch20 · 主题/文本变化后刷行号
        scrollView.verticalRulerView?.needsDisplay = true
        // v15.22 batch39 · 处理插入请求（在当前光标位置插入文本 · undo 单次回到原状）
        if let snippet = pendingInsertText, !snippet.isEmpty {
            tv.insertText(snippet, replacementRange: tv.selectedRange())
            tv.window?.makeFirstResponder(tv)
            DispatchQueue.main.async { self.pendingInsertText = nil }
        }
        // v15.22 batch29 · 处理跳转请求（行号 1-based · 含光标移动 + 抢 firstResponder）
        if let target = pendingGotoLine, target > 0 {
            if let lineStart = Self.utf16Offset(forLine: target, in: tv.string) {
                tv.setSelectedRange(NSRange(location: lineStart, length: 0))
                tv.scrollRangeToVisible(NSRange(location: lineStart, length: 0))
                tv.window?.makeFirstResponder(tv)
            }
            DispatchQueue.main.async { self.pendingGotoLine = nil }
        }
        // v15.23 batch107 · 仅滚动（不动光标 · minimap 拖动专用 · trader 边编辑边浏览全文）
        if let target = pendingScrollToLine, target > 0 {
            if let lineStart = Self.utf16Offset(forLine: target, in: tv.string) {
                tv.scrollRangeToVisible(NSRange(location: lineStart, length: 0))
            }
            DispatchQueue.main.async { self.pendingScrollToLine = nil }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MaiLangCodeView
        weak var textView: NSTextView?
        nonisolated(unsafe) var visibleObserver: NSObjectProtocol?
        /// 防 applyHighlight 内部 setSelectedRange 反递归触发 textViewDidChangeSelection 死循环
        /// （v15.25 Mac 切机暴露 · makeNSView 设 tv.string 即触发栈溢出 SIGSEGV）
        private var isApplyingHighlight = false

        init(_ parent: MaiLangCodeView) { self.parent = parent }

        deinit {
            if let obs = visibleObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        /// v15.23 batch106 · 订阅 NSScrollView contentView bounds 变化 → 报可视行（minimap viewport 同步）
        func attachVisibleLinesObserver(scrollView: NSScrollView, textView: NSTextView) {
            self.textView = textView
            guard parent.onVisibleLinesChange != nil else { return }
            scrollView.contentView.postsBoundsChangedNotifications = true
            visibleObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView, queue: .main
            ) { [weak self] _ in
                self?.reportVisibleLines()
            }
            // 首帧（layout 完成后）报一次
            DispatchQueue.main.async { [weak self] in self?.reportVisibleLines() }
        }

        func reportVisibleLines() {
            guard let tv = textView, let cb = parent.onVisibleLinesChange else { return }
            if let (s, e) = MaiLangCodeView.visibleLines(in: tv) { cb(s, e) }
        }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // 文本变更 → 双 binding 同步 + 重新高亮
            DispatchQueue.main.async {
                self.parent.text = tv.string
                self.parent.applyHighlight(to: tv)
                // batch106 · 文本变 → 行数变 → 可视行集合可能变（顶部 line 不变 · 底部可能 shift）
                self.reportVisibleLines()
                // v16.2 · 自动触发补全 · 光标前 ≥ 2 字母 word + 至少 1 个候选命中 → 弹 popup
                self.maybeTriggerAutoCompletion(tv)
            }
        }

        /// v16.2 · 自动补全触发 · trader 输入"M" → 不需手动按 Esc · 直接弹 MA / MAX / MIN / MEDIAN 候选
        ///
        /// 触发条件：
        /// 1. 光标无选区
        /// 2. 光标前是连续 ≥ 2 个 ASCII 字母（避免单字母 / 数字 / 中文 / 标点触发）
        /// 3. 该 prefix 至少有 1 个候选命中（避免空 popup 闪烁）
        ///
        /// 用 NSTextView.complete(_:) 调起内置补全 popup · 候选源由
        /// `textView(_:completions:forPartialWordRange:indexOfSelectedItem:)` 提供
        private func maybeTriggerAutoCompletion(_ tv: NSTextView) {
            let range = tv.selectedRange()
            guard range.length == 0, range.location > 0 else { return }
            let ns = tv.string as NSString
            var wordStart = range.location
            while wordStart > 0 {
                let codeUnit = ns.character(at: wordStart - 1)
                // ASCII A-Z (0x41-0x5A) / a-z (0x61-0x7A) · 直接 UTF-16 比较避免 String 转换开销
                let isLetter = (codeUnit >= 0x41 && codeUnit <= 0x5A) || (codeUnit >= 0x61 && codeUnit <= 0x7A)
                if isLetter { wordStart -= 1 } else { break }
            }
            let wordLen = range.location - wordStart
            guard wordLen >= 2 else { return }
            let prefix = ns.substring(with: NSRange(location: wordStart, length: wordLen)).uppercased()
            let hasCandidate = MaiLangSyntaxHighlighter.allCompletionCandidates.contains { $0.hasPrefix(prefix) }
            guard hasCandidate else { return }
            tv.complete(nil)
        }

        /// v15.22 batch11 · 光标位置变化（含点击/方向键/选区调整）→ 报行/列给 status bar
        /// v15.22 batch21 · 同步刷新当前行浅背景高亮
        /// v15.22 batch23 · 同步报选区范围（NSRange）给批量操作
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingHighlight else { return }
            guard let tv = notification.object as? NSTextView else { return }
            // batch21 · 光标移动时刷当前行高亮（不重 tokenize · 仅重 attribute · 短文档性能 OK）
            isApplyingHighlight = true
            parent.applyHighlight(to: tv)
            isApplyingHighlight = false
            let range = tv.selectedRange()
            if let cb = parent.onCursorChange {
                let (line, col) = lineColumn(in: tv.string, at: range.location)
                DispatchQueue.main.async { cb(line, col) }
            }
            if let cb = parent.onSelectionChange {
                DispatchQueue.main.async { cb(range) }
            }
            // batch27 · 找当前光标处 token（短文档 tokenize 性能 OK · 长文档可后续做 cache 优化）
            if let cb = parent.onTokenAtCursor {
                let loc = range.location
                let tokens = MaiLangSyntaxHighlighter.tokenize(tv.string)
                let tk = tokens.first { NSLocationInRange(loc, $0.range) || NSMaxRange($0.range) == loc }
                DispatchQueue.main.async { cb(tk?.text) }
            }
        }

        /// utf16 location → (line, col) · 均 1-based · 越界 clamp 到末尾
        private func lineColumn(in source: String, at utf16Loc: Int) -> (Int, Int) {
            let ns = source as NSString
            let length = min(max(0, utf16Loc), ns.length)
            var line = 1
            var lineStart = 0
            var i = 0
            while i < length {
                if ns.character(at: i) == 0x0A {
                    line += 1
                    lineStart = i + 1
                }
                i += 1
            }
            return (line, length - lineStart + 1)
        }

        /// v15.22 batch10 · Tab 键插入 4 空格（替代默认 \t · 与 Swift 缩进习惯一致）
        /// v15.22 batch14 · Enter 键保持上一行缩进（trader 写多行公式省手动空格）
        /// 仅在无补全 popup 时触发（popup 时由 NSTextView 内部消化）
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            // v15.22 batch16 · 配对 backspace · `(|)` 按 backspace 同删两侧（与 batch12/13 闭环）
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let ns = textView.string as NSString
                let range = textView.selectedRange()
                if range.length == 0, range.location > 0, range.location < ns.length {
                    let prev = ns.substring(with: NSRange(location: range.location - 1, length: 1))
                    let next = ns.substring(with: NSRange(location: range.location, length: 1))
                    let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "'": "'", "\"": "\""]
                    if let close = pairs[prev], close == next {
                        textView.insertText("", replacementRange: NSRange(location: range.location - 1, length: 2))
                        return true
                    }
                }
                return false   // 非配对场景走默认 backspace
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let ns = textView.string as NSString
                let loc = textView.selectedRange().location
                // 找当前行起始（loc 之前最近的 \n + 1，或文件开头）
                var lineStart = loc
                while lineStart > 0 && ns.character(at: lineStart - 1) != 0x0A {
                    lineStart -= 1
                }
                // 抓前置空白（space / tab）作为新行缩进
                var indent = ""
                var i = lineStart
                while i < loc {
                    let ch = ns.character(at: i)
                    if ch == 0x20 || ch == 0x09, let scalar = UnicodeScalar(ch) {
                        indent.append(Character(scalar))
                        i += 1
                    } else { break }
                }
                textView.insertText("\n" + indent, replacementRange: textView.selectedRange())
                return true
            }
            return false
        }

        /// v15.22 batch12+13+31 · 括号 / 引号自动配对 + 配对字符 skip + 智能大写关键字
        /// - 输入 `(` 自动补 `)` 光标停中间（5 类：( [ { ' "）
        /// - 输入闭括号且光标右已是同字符 → 仅光标右移 1
        /// - batch31 · trigger 字符（空格/换行/分号/逗号/括号/运算符）触发前一个 word 智能大写
        ///   （仅当 word 是麦语言保留字时 · 大小写不敏感匹配）
        /// 触发条件：单字符插入 + 无选中文本
        public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                             replacementString: String?) -> Bool {
            guard let s = replacementString, s.count == 1, affectedCharRange.length == 0 else { return true }
            let ns = textView.string as NSString
            // batch31 · 智能大写：trigger 前的 word 是保留字 → uppercased 替换（在配对/skip 之前做）
            let triggerSet: Set<Character> = [" ", "\t", "\n", ";", ",", "(", ")", "[", "]",
                                              "+", "-", "*", "/", "=", "<", ">", "%", ":"]
            if let ch = s.first, triggerSet.contains(ch) {
                var wordStart = affectedCharRange.location
                while wordStart > 0 {
                    let c = ns.character(at: wordStart - 1)
                    let isWord = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
                                 || (c >= 0x30 && c <= 0x39) || c == 0x5F
                    if isWord { wordStart -= 1 } else { break }
                }
                if wordStart < affectedCharRange.location {
                    let wordRange = NSRange(location: wordStart,
                                            length: affectedCharRange.location - wordStart)
                    let word = ns.substring(with: wordRange)
                    let upper = word.uppercased()
                    if word != upper, MaiLangSyntaxHighlighter.isReservedWord(word) {
                        textView.insertText(upper, replacementRange: wordRange)
                        // 替换完继续走默认 trigger 字符插入（return true 让 NSTextView 接管）
                    }
                }
            }
            // batch13 · 闭括号 / 引号 skip · 光标右侧已同字符 → 仅右移
            let closers: Set<String> = [")", "]", "}", "'", "\""]
            // 重新读 affectedCharRange.location（智能大写 word 长度等长 · 不偏移 · 安全）
            if closers.contains(s),
               affectedCharRange.location < ns.length,
               ns.substring(with: NSRange(location: affectedCharRange.location, length: 1)) == s {
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                return false
            }
            // batch12 · 开括号 / 引号 → 自动配对
            let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "'": "'", "\"": "\""]
            guard let close = pairs[s] else { return true }
            textView.insertText(s + close, replacementRange: affectedCharRange)
            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
            return false
        }

        /// v15.22 batch9 · 自动补全候选（NSTextView 默认 F5 / Esc 触发 popup）
        /// trader 输入"M" → Esc → 弹 MA / MAX / MIN / MEDIAN / MOD / MULAR 等候选
        public func textView(_ textView: NSTextView,
                             completions words: [String],
                             forPartialWordRange charRange: NSRange,
                             indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let prefix = (textView.string as NSString).substring(with: charRange).uppercased()
            guard !prefix.isEmpty else { return [] }
            let candidates = MaiLangSyntaxHighlighter.allCompletionCandidates
                .filter { $0.hasPrefix(prefix) }
            if !candidates.isEmpty, let idx = index {
                idx.pointee = 0
            }
            return candidates
        }
    }

    // MARK: - 主题 + 高亮

    private func applyTheme(to tv: NSTextView) {
        switch scheme {
        case .dark:
            tv.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            tv.insertionPointColor = NSColor(white: 1, alpha: 0.9)
        case .light:
            tv.backgroundColor = NSColor(red: 0.96, green: 0.965, blue: 0.972, alpha: 1)
            tv.insertionPointColor = NSColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        }
    }

    /// 计算 token + 应用 NSAttributedString 颜色（保留 selectedRange / cursor）
    private func applyHighlight(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let savedRange = tv.selectedRange()
        let source = tv.string
        let tokens = MaiLangSyntaxHighlighter.tokenize(source)

        // 默认色（identifier）覆盖整段（运算符 / 空白 fallback）
        let baseColor = nsColor(scheme.color(for: .identifier))
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .foregroundColor: baseColor,
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
        ], range: fullRange)
        for t in tokens {
            let color = nsColor(scheme.color(for: t.kind))
            // 保护 range 不越界（tokenize 输出基于同源 UTF-16 · 应不会越界 · 双保险）
            let safeRange = NSIntersectionRange(t.range, fullRange)
            if safeRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: color, range: safeRange)
            }
            // v15.23 batch42 · hover popover · 已知函数 token 加 toolTip 属性
            // NSTextView 内置悬停提示（系统 ~1s 延迟自动显示）· 不需 NSTrackingArea
            if t.kind == .builtinFunc, safeRange.length > 0,
               let sig = MaiLangFunctionSignatures.all[t.text.uppercased()] {
                let tip = "\(sig.formatted)\n\n📂 \(sig.category.rawValue)\n📝 \(sig.summary)"
                storage.addAttribute(.toolTip, value: tip as NSString, range: safeRange)
            }
        }
        // v15.22 batch21 · 当前光标所在行浅背景高亮（在错误标注之前 · 错误优先覆盖）
        let cursorLoc = tv.selectedRange().location
        let nsSource = source as NSString
        if cursorLoc <= nsSource.length {
            var lineStart = min(cursorLoc, nsSource.length)
            while lineStart > 0 && nsSource.character(at: lineStart - 1) != 0x0A { lineStart -= 1 }
            var lineEnd = min(cursorLoc, nsSource.length)
            while lineEnd < nsSource.length && nsSource.character(at: lineEnd) != 0x0A { lineEnd += 1 }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let highlightColor: NSColor = scheme == .dark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.05)
            if lineRange.length > 0 {
                let safe = NSIntersectionRange(lineRange, fullRange)
                if safe.length > 0 {
                    storage.addAttribute(.backgroundColor, value: highlightColor, range: safe)
                }
            }
        }
        // v15.22 batch6 · 错误位置红色标注（编译失败后定位）· v15.95 升级波浪线下划（IDE 风格 · 视觉更专业）
        // NSUnderlineStyle .single + .patternDot 组合接近 IDE 拼写错误波浪线 · macOS 13+ 原生支持
        if let marker = errorMarker,
           let errRange = lineColumnToRange(marker, in: source) {
            let safe = NSIntersectionRange(errRange, fullRange)
            if safe.length > 0 {
                let underline = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
                storage.addAttribute(.underlineStyle, value: underline, range: safe)
                storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: safe)
                storage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.15), range: safe)
            }
        }
        storage.endEditing()
        // 恢复 cursor / selection（避免高亮触发跳到首字符）
        if savedRange.location <= fullRange.length {
            tv.setSelectedRange(NSRange(location: savedRange.location, length: min(savedRange.length, fullRange.length - savedRange.location)))
        }
    }

    private func nsColor(_ rgb: SyntaxRGB) -> NSColor {
        NSColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
    }

    // MARK: - v15.22 batch20 · 行号 gutter（NSRulerView · 与编译错误"第 N 行"对齐 trader 一眼定位）

    final class LineNumberRulerView: NSRulerView {
        private weak var sourceTextView: NSTextView?
        private let labelFont: NSFont

        init(textView: NSTextView, fontSize: CGFloat) {
            self.sourceTextView = textView
            self.labelFont = NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 1), weight: .regular)
            super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
            self.clientView = textView
            self.ruleThickness = 40
            NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                name: NSText.didChangeNotification, object: textView)
            if let sv = textView.enclosingScrollView {
                sv.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                    name: NSView.boundsDidChangeNotification, object: sv.contentView)
            }
        }

        required init(coder: NSCoder) { fatalError() }

        @objc private func needsRedraw() { needsDisplay = true }

        /// v15.22 batch24 · 点击行号选中整行（trader 看编译错误"第 N 行" → 直接点 N 定位）
        override func mouseDown(with event: NSEvent) {
            guard let tv = sourceTextView,
                  let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return }
            let p = convert(event.locationInWindow, from: nil)
            let visibleRect = scrollView?.contentView.bounds ?? tv.visibleRect
            // ruler y 坐标 → textView y 坐标（加上滚动偏移）
            let yInTextView = p.y + visibleRect.origin.y - tv.textContainerOrigin.y
            let glyphIndex = lm.glyphIndex(for: NSPoint(x: 0, y: yInTextView), in: tc)
            let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
            let nsStr = tv.string as NSString
            // 行起止
            var lineStart = min(charIndex, nsStr.length)
            while lineStart > 0 && nsStr.character(at: lineStart - 1) != 0x0A { lineStart -= 1 }
            var lineEnd = lineStart
            while lineEnd < nsStr.length && nsStr.character(at: lineEnd) != 0x0A { lineEnd += 1 }
            tv.setSelectedRange(NSRange(location: lineStart, length: lineEnd - lineStart))
            tv.scrollRangeToVisible(NSRange(location: lineStart, length: 0))
            tv.window?.makeFirstResponder(tv)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.withAlphaComponent(0.5).setFill()
            dirtyRect.fill()
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height).fill()

            guard let tv = sourceTextView,
                  let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let visibleRect = scrollView?.contentView.bounds ?? tv.visibleRect
            let nsStr = tv.string as NSString
            let length = nsStr.length

            // 每行起始字符索引（含末尾空行）
            var lineStarts: [Int] = [0]
            for i in 0..<length {
                if nsStr.character(at: i) == 0x0A { lineStarts.append(i + 1) }
            }
            for (idx, start) in lineStarts.enumerated() {
                // 末尾空行（start == length）glyphIndexForCharacter 返回 numberOfGlyphs · 用 extraLineFragmentRect
                let glyphRect: NSRect
                if start >= length {
                    glyphRect = lm.extraLineFragmentRect.height > 0 ? lm.extraLineFragmentRect : .zero
                } else {
                    let glyphIndex = lm.glyphIndexForCharacter(at: start)
                    glyphRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                }
                let y = glyphRect.origin.y - visibleRect.origin.y + tv.textContainerOrigin.y + 2
                if y + glyphRect.height < 0 || y > bounds.height { continue }
                let str = "\(idx + 1)" as NSString
                let size = str.size(withAttributes: attrs)
                let x = ruleThickness - size.width - 6
                str.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }

    // MARK: - v15.23 batch106 · 可视行计算（layoutManager + visibleRect）

    /// 计算 NSTextView 当前可视区起止行号（1-based · 含 partial visible）· 失败返回 nil
    static func visibleLines(in tv: NSTextView) -> (Int, Int)? {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let rect = tv.visibleRect
        if rect.isEmpty { return nil }
        let glyphRange = lm.glyphRange(forBoundingRect: rect, in: tc)
        if glyphRange.length == 0 {
            // 空文档 / 文本未 layout 完
            return (1, 1)
        }
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let ns = tv.string as NSString
        let firstLine = lineNumber(forUTF16Loc: charRange.location, in: ns)
        let endLoc = max(charRange.location, NSMaxRange(charRange) - 1)
        let lastLine = lineNumber(forUTF16Loc: endLoc, in: ns)
        return (firstLine, lastLine)
    }

    /// 1-based 行号 → utf16 行起始 location · 越界返回 nil
    static func utf16Offset(forLine line: Int, in source: String) -> Int? {
        guard line > 0 else { return nil }
        let ns = source as NSString
        var currentLine = 1
        var lineStart = 0
        var i = 0
        while i < ns.length && currentLine < line {
            if ns.character(at: i) == 0x0A {
                currentLine += 1
                lineStart = i + 1
            }
            i += 1
        }
        return currentLine == line ? lineStart : nil
    }

    /// utf16 location → 1-based 行号 · 越界 clamp
    static func lineNumber(forUTF16Loc loc: Int, in ns: NSString) -> Int {
        let length = min(max(0, loc), ns.length)
        var line = 1
        var i = 0
        while i < length {
            if ns.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }

    /// v15.22 batch6 · 行/列（1-based）→ NSRange UTF-16 偏移 · 越界返回 nil
    private func lineColumnToRange(_ marker: CodeErrorMarker, in source: String) -> NSRange? {
        let ns = source as NSString
        let length = ns.length
        var currentLine = 1
        var lineStart = 0
        var i = 0
        while i < length && currentLine < marker.line {
            if ns.character(at: i) == 0x0A {  // '\n'
                currentLine += 1
                lineStart = i + 1
            }
            i += 1
        }
        guard currentLine == marker.line else { return nil }
        let col = max(1, marker.column)
        let location = lineStart + col - 1
        guard location < length else { return nil }
        let len = max(1, marker.length)
        return NSRange(location: location, length: min(len, length - location))
    }
}
#endif
