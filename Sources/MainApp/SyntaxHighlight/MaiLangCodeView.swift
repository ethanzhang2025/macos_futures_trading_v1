// WP-65 v15.22 batch3 · 麦语言代码编辑器 SwiftUI 包装
// NSTextView NSViewRepresentable · 实时 syntax 高亮 · 与 ChartScene NSColor 用法一致（macOS only）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import Shared

/// SwiftUI 麦语言代码编辑器 · 实时 syntax 高亮 + 双 binding 同步
public struct MaiLangCodeView: NSViewRepresentable {
    @Binding var text: String
    let scheme: SyntaxColorScheme
    let fontSize: CGFloat

    public init(text: Binding<String>, scheme: SyntaxColorScheme = .dark, fontSize: CGFloat = 13) {
        self._text = text
        self.scheme = scheme
        self.fontSize = fontSize
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
        storage.endEditing()
        // 恢复 cursor / selection（避免高亮触发跳到首字符）
        if savedRange.location <= fullRange.length {
            tv.setSelectedRange(NSRange(location: savedRange.location, length: min(savedRange.length, fullRange.length - savedRange.location)))
        }
    }

    private func nsColor(_ rgb: SyntaxRGB) -> NSColor {
        NSColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
    }
}
#endif
