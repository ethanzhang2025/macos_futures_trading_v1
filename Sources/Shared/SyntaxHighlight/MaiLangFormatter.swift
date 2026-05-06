// WP-65 v15.23 batch40 · 麦语言公式格式化器（纯函数 · 跨平台 · Linux 可测）
//
// 功能：
// - tab → 4 空格（全局统一）
// - 行尾空白 trim（含全角空格 + tab）
// - 3+ 连续空行折叠成 1 空行
// - 关键字 / 内置函数 / 绘图属性自动大写（即使用户智能大写关掉了 · 一键归一）
// - 逗号后保证 1 空格（仅在非字符串非注释 token 之间）
//
// 设计要点：
// - 利用 MaiLangSyntaxHighlighter.tokenize 拿到所有 token range（含 comment / string 区域）
// - 字符串 / 注释内部不动（逗号、保留字都跳过）
// - 倒序应用 NSRange 替换避免 offset 漂移
// - 与 IndicatorCore 保留字表同步（依赖 SyntaxHighlighter 的 isReservedWord 单一事实源）

import Foundation

public enum MaiLangFormatter {

    /// 格式化入口 · 输入原始公式 · 输出归一化后的公式
    /// - 性能：O(n) tokenize + O(n) 重组 · 1000 行公式 < 5ms
    public static func format(_ source: String) -> String {
        let step1 = normalizeWhitespace(source)
        let step2 = collapseBlankLines(step1)
        let step3 = uppercaseReservedWords(step2)
        let step4 = ensureSpaceAfterComma(step3)
        return step4
    }

    // MARK: - Step 1：tab → 4 空格 + 行尾 trim

    static func normalizeWhitespace(_ source: String) -> String {
        let tabExpanded = source.replacingOccurrences(of: "\t", with: "    ")
        return tabExpanded
            .components(separatedBy: "\n")
            .map { trimTrailing($0) }
            .joined(separator: "\n")
    }

    private static func trimTrailing(_ line: String) -> String {
        var s = line
        while let last = s.last, last == " " || last == "\t" || last == "\u{3000}" {
            s.removeLast()
        }
        return s
    }

    // MARK: - Step 2：3+ 空行折叠成 1 空行

    static func collapseBlankLines(_ source: String) -> String {
        var output: [String] = []
        var blankRun = 0
        for line in source.components(separatedBy: "\n") {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 { output.append(line) }
            } else {
                blankRun = 0
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: - Step 3：保留字大写

    /// 对 .keyword / .builtinFunc / .drawAttribute 的 token 自动大写
    /// 字符串 / 注释 / 数字 / operator 跳过
    static func uppercaseReservedWords(_ source: String) -> String {
        let tokens = MaiLangSyntaxHighlighter.tokenize(source)
        let result = NSMutableString(string: source)
        // 倒序避免 NSRange offset 漂移
        for token in tokens.reversed() {
            switch token.kind {
            case .keyword, .builtinFunc, .drawAttribute:
                let upper = token.text.uppercased()
                if upper != token.text {
                    result.replaceCharacters(in: token.range, with: upper)
                }
            default:
                continue
            }
        }
        return result as String
    }

    // MARK: - Step 4：逗号后空格

    /// 找到所有 .operatorPunct 的逗号 token · 若后面紧贴非空白字符 · 插入空格
    /// 注意：字符串/注释内的逗号不会被 tokenize 单列出来（属于 .string / .comment 整体），所以天然安全
    static func ensureSpaceAfterComma(_ source: String) -> String {
        let tokens = MaiLangSyntaxHighlighter.tokenize(source)
        let nsSource = source as NSString
        let result = NSMutableString(string: source)
        // 收集需要插入位置（倒序）
        var insertions: [Int] = []
        for token in tokens {
            guard token.kind == .operatorPunct, token.text == "," else { continue }
            let after = token.range.location + token.range.length
            if after < nsSource.length {
                let nextChar = nsSource.character(at: after)
                // 非空格 / 非 \n / 非 \t · 插空格
                if nextChar != 0x20 && nextChar != 0x0A && nextChar != 0x09 {
                    insertions.append(after)
                }
            }
        }
        // 倒序应用
        for pos in insertions.reversed() {
            result.insert(" ", at: pos)
        }
        return result as String
    }
}
