// WP-65 v15.22 batch38 · 麦语言公式大纲解析（Linux 可测 · 跨平台）
//
// 功能：提取公式中所有变量定义（NAME:=expr 中间变量 / NAME:expr 输出）
// 用途：编辑器大纲面板 / 文档生成 / 公式预览的变量列表
//
// 设计：
// - 行级 tolerant 解析（不深度词法 · 不抛错 · 错误行直接跳过）
// - 跳过 // 行注释 + { ... } 块注释（含跨行块注释）
// - NAME 合法标识符校验：首位非数字 · 仅字母数字下划线
// - 排除保留字（避免 IF:THEN 等被误识别）

import Foundation

/// 公式大纲条目（变量定义 + 1-based 行号 + 是否输出）
public struct MaiLangOutlineEntry: Sendable, Equatable {
    public let name: String
    public let line: Int       // 1-based
    public let isOutput: Bool  // false = `:=` 中间变量 · true = `:` 输出绘图

    public init(name: String, line: Int, isOutput: Bool) {
        self.name = name
        self.line = line
        self.isOutput = isOutput
    }
}

/// 公式大纲解析器
public enum MaiLangOutline {

    /// 解析公式 source 返回所有变量定义（按行号顺序）
    public static func parse(_ source: String) -> [MaiLangOutlineEntry] {
        let lines = source.components(separatedBy: "\n")
        var result: [MaiLangOutlineEntry] = []
        var inBlockComment = false
        for (idx, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if inBlockComment {
                if trimmed.contains("}") { inBlockComment = false }
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.hasPrefix("{") {
                if !trimmed.contains("}") { inBlockComment = true }
                continue
            }
            if trimmed.isEmpty { continue }
            // := 优先于 :（避免 := 被解析为 :+= ）
            let isOutput: Bool
            let assignRange: Range<String.Index>?
            if let r = trimmed.range(of: ":=") {
                assignRange = r
                isOutput = false
            } else if let r = trimmed.range(of: ":") {
                assignRange = r
                isOutput = true
            } else {
                continue
            }
            guard let r = assignRange else { continue }
            let name = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  let first = name.first,
                  first.isLetter || first == "_",
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { continue }
            if MaiLangSyntaxHighlighter.isReservedWord(name) { continue }
            result.append(MaiLangOutlineEntry(name: name, line: idx + 1, isOutput: isOutput))
        }
        return result
    }
}
