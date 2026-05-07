// WP-65 v15.23 batch111 · 麦语言公式 lint 静态检查（Linux 可测 · 跨平台）
//
// 功能：检测「定义了但全文未引用」的中间变量（NAME:=expr · 非输出绘图）
// 用途：编辑器 minimap 橙色 warning marker · trader 写完一眼看 dead code
//
// 设计：
// - 复用 MaiLangOutline.parse（变量定义抽取）+ MaiLangSyntaxHighlighter.tokenize（identifier 全文计数）
// - 输出变量（NAME:expr,attr;）即使无后续引用也是合法绘图输出 · 不警告
// - 大小写不敏感比对（麦语言保留字传统大写 · trader 写 ma5 / MA5 应等同）
// - tolerant：不抛错 · 解析失败默认空数组

import Foundation

/// lint 警告条目（kind + 行号 + 描述）
public struct MaiLangLintWarning: Sendable, Equatable {
    public let line: Int       // 1-based
    public let kind: Kind
    public let message: String

    public enum Kind: String, Sendable, Equatable {
        case unusedVariable        // 中间变量定义但全文无其他引用
        case duplicateDefinition   // 同名变量被定义两次及以上（可能是 typo · 后续覆盖前定义）
        case missingColorAttribute // 输出变量未指定 COLORxxx 属性（默认色不醒目）
    }

    public init(line: Int, kind: Kind, message: String) {
        self.line = line; self.kind = kind; self.message = message
    }
}

public enum MaiLangLint {

    /// 全文 lint 检查 · 返回所有 warning（按行号升序）
    public static func analyze(_ source: String) -> [MaiLangLintWarning] {
        let outline = MaiLangOutline.parse(source)
        guard !outline.isEmpty else { return [] }
        let tokens = MaiLangSyntaxHighlighter.tokenize(source)

        // identifier token 全文出现次数（含定义自身）· 大小写不敏感
        var refCount: [String: Int] = [:]
        for t in tokens where t.kind == .identifier {
            refCount[t.text.uppercased(), default: 0] += 1
        }
        // 同名定义计数（罕见 · 但需要从 ref 中扣除以求"引用"次数）
        var defCount: [String: Int] = [:]
        for entry in outline {
            defCount[entry.name.uppercased(), default: 0] += 1
        }

        var warnings: [MaiLangLintWarning] = []

        // 规则 1：未使用的中间变量
        for entry in outline where !entry.isOutput {
            let key = entry.name.uppercased()
            let usage = (refCount[key] ?? 0) - (defCount[key] ?? 0)
            if usage <= 0 {
                warnings.append(MaiLangLintWarning(
                    line: entry.line,
                    kind: .unusedVariable,
                    message: "未使用的中间变量 \(entry.name)"))
            }
        }

        // 规则 2：重复定义（同名变量定义 ≥ 2 次 · 后续覆盖首次 · 可能 typo）
        var firstSeenLine: [String: Int] = [:]
        for entry in outline {
            let key = entry.name.uppercased()
            if let firstLine = firstSeenLine[key] {
                warnings.append(MaiLangLintWarning(
                    line: entry.line,
                    kind: .duplicateDefinition,
                    message: "重复定义：\(entry.name)（首次定义在第 \(firstLine) 行）"))
            } else {
                firstSeenLine[key] = entry.line
            }
        }

        // 规则 3：输出变量未指定 COLORxxx 属性（默认色不醒目 · 多输出时难区分）
        let lines = source.components(separatedBy: "\n")
        for entry in outline where entry.isOutput {
            let lineIdx = entry.line - 1
            guard lineIdx >= 0 && lineIdx < lines.count else { continue }
            let upperLine = lines[lineIdx].uppercased()
            if !upperLine.contains("COLOR") {
                warnings.append(MaiLangLintWarning(
                    line: entry.line,
                    kind: .missingColorAttribute,
                    message: "输出变量 \(entry.name) 未指定颜色（建议加 COLORRED / COLORBLUE 等）"))
            }
        }

        return warnings.sorted { $0.line < $1.line }
    }
}
