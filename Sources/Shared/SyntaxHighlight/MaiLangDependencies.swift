// WP-65 v15.23 batch134 · 麦语言公式变量依赖图（跨平台 · Linux 可测）
//
// 用途：trader 看复杂公式时一眼知道每个变量
//   - 引用了谁（其表达式中用到的其他变量）
//   - 被谁引用（其他变量的表达式中提到它）
// outline sheet 直接展示 + 跳转
//
// 设计：
// - 复用 MaiLangOutline.parse 抽变量定义 + MaiLangSyntaxHighlighter.tokenize 抽 identifier
// - tokenize 自动排除 string / comment 内容（不会把 "MA5" 注释中的字符当 identifier）
// - 大小写不敏感（uppercased 后匹配）

import Foundation

/// 变量依赖（uses = 该变量定义中引用的其他变量 · usedBy = 引用该变量的其他变量）
public struct MaiLangVarDependency: Sendable, Equatable {
    public let name: String           // 变量名（uppercased · 与定义一致）
    public let line: Int              // 定义所在行 1-based
    public let uses: [String]         // 它依赖的其他变量（按字母序）
    public let usedBy: [String]       // 引用它的其他变量（按字母序）

    public init(name: String, line: Int, uses: [String], usedBy: [String]) {
        self.name = name; self.line = line; self.uses = uses; self.usedBy = usedBy
    }
}

public enum MaiLangDependencies {

    /// 全文变量依赖分析 · 返回每个 outline 变量的 uses + usedBy（按定义行号升序）
    public static func analyze(_ source: String) -> [MaiLangVarDependency] {
        let outline = MaiLangOutline.parse(source)
        guard !outline.isEmpty else { return [] }
        let tokens = MaiLangSyntaxHighlighter.tokenize(source)
        let known = Set(outline.map { $0.name.uppercased() })
        let varByLine: [Int: String] = Dictionary(uniqueKeysWithValues:
            outline.map { ($0.line, $0.name.uppercased()) })

        // line 计算：utf16 location → 1-based 行号
        let ns = source as NSString
        var lineStarts: [Int] = [0]
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            lineStarts.append(i + 1)
        }
        func lineFor(_ loc: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            var ans = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if lineStarts[mid] <= loc { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
            }
            return ans + 1
        }

        // 收集每个变量"使用"集（identifier 出现在该变量定义行 · 且非自身 · 且属于已知变量）
        var usesMap: [String: Set<String>] = [:]
        for t in tokens where t.kind == .identifier {
            let line = lineFor(t.range.location)
            guard let owner = varByLine[line] else { continue }
            let referenced = t.text.uppercased()
            if known.contains(referenced) && referenced != owner {
                usesMap[owner, default: []].insert(referenced)
            }
        }
        // 反向构建 usedBy（B in usesMap[A] → usedBy[B] 含 A）
        var usedByMap: [String: Set<String>] = [:]
        for (owner, deps) in usesMap {
            for d in deps {
                usedByMap[d, default: []].insert(owner)
            }
        }

        return outline.map { entry in
            let key = entry.name.uppercased()
            return MaiLangVarDependency(
                name: entry.name,
                line: entry.line,
                uses: (usesMap[key] ?? []).sorted(),
                usedBy: (usedByMap[key] ?? []).sorted())
        }
    }
}
