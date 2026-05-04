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

    public init(text: Binding<String>, scheme: SyntaxColorScheme = .dark,
                fontSize: CGFloat = 13, errorMarker: CodeErrorMarker? = nil) {
        self._text = text
        self.scheme = scheme
        self.fontSize = fontSize
        self.errorMarker = errorMarker
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false   // 防"智能"引号破坏字符串
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        applyTheme(to: tv)
        // 初始文本
        tv.string = text
        applyHighlight(to: tv)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // 外部 text 变化（如 sheet 重新打开）→ 同步
        if tv.string != text {
            let cursor = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(cursor.location, text.utf16.count), length: 0))
        }
        applyTheme(to: tv)
        applyHighlight(to: tv)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MaiLangCodeView
        init(_ parent: MaiLangCodeView) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // 文本变更 → 双 binding 同步 + 重新高亮
            DispatchQueue.main.async {
                self.parent.text = tv.string
                self.parent.applyHighlight(to: tv)
            }
        }

        /// v15.22 batch10 · Tab 键插入 4 空格（替代默认 \t · 与 Swift 缩进习惯一致）
        /// 仅在无补全 popup 时触发（popup 时 Tab 由 NSTextView 内部消化用于选中候选 · 不会进 doCommandBy）
        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }

        /// v15.22 batch9 · 自动补全候选（NSTextView 默认 F5 / Esc 触发 popup）
        /// trader 输入"M" → Esc → 弹 MA / MAX / MIN / MEDIAN / MOD / MULAR 等候选
        public func textView(_ textView: NSTextView,
                             completions words: [String],
                             forPartialWordRange charRange: NSRange,
                             indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String]? {
            let prefix = (textView.string as NSString).substring(with: charRange).uppercased()
            guard !prefix.isEmpty else { return nil }
            let candidates = MaiLangSyntaxHighlighter.allCompletionCandidates
                .filter { $0.hasPrefix(prefix) }
            // 默认选中第一个（trader 直接 Tab 即可补全）
            if !candidates.isEmpty, index != nil {
                index!.pointee = 0
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
        }
        // v15.22 batch6 · 错误位置红色背景标注（编译失败后定位）
        if let marker = errorMarker,
           let errRange = lineColumnToRange(marker, in: source) {
            let safe = NSIntersectionRange(errRange, fullRange)
            if safe.length > 0 {
                storage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.35), range: safe)
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
