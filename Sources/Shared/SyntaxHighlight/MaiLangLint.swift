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
    /// v16.74 · 严重度（铺路 minimap 颜色区分 / 排序优先级）· 默认 .warning
    public let severity: Severity

    public enum Kind: String, Sendable, Equatable {
        case unusedVariable        // 中间变量定义但全文无其他引用
        case duplicateDefinition   // 同名变量被定义两次及以上（可能是 typo · 后续覆盖前定义）
        case missingColorAttribute // 输出变量未指定 COLORxxx 属性（默认色不醒目）
        case undefinedVariable     // v16.66 · 引用了未定义的标识符（非保留字 · 非已声明变量 · 可能 typo）

        /// v16.74 · 默认严重度（undefined 是 error · 其他是 warning）
        public var defaultSeverity: Severity {
            switch self {
            case .undefinedVariable: return .error
            case .duplicateDefinition: return .error
            case .unusedVariable, .missingColorAttribute: return .warning
            }
        }
    }

    /// v16.74 · 严重度（minimap 颜色 / outline 排序权重）
    public enum Severity: String, Sendable, Equatable, Comparable {
        case warning  // 提醒类（unused / missingColor）
        case error    // 紧急类（undefined / duplicateDef）

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            // error > warning（排序时 error 优先）
            lhs == .warning && rhs == .error
        }
    }

    public init(line: Int, kind: Kind, message: String, severity: Severity? = nil) {
        self.line = line; self.kind = kind; self.message = message
        self.severity = severity ?? kind.defaultSeverity
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

        // v16.66 规则 4：未定义的标识符（可能 typo）· 非保留字 + 非已声明变量
        // 用 outline 名集合 + isReservedWord 反向过滤 identifier tokens
        let definedNames: Set<String> = Set(outline.map { $0.name.uppercased() })
        // 按 token location 计算行号 · 预算 lineStarts O(n) 后二分 O(log n) 查询
        let ns = source as NSString
        var lineStarts: [Int] = [0]
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            lineStarts.append(i + 1)
        }
        func lineOf(_ loc: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1, ans = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if lineStarts[mid] <= loc { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
            }
            return ans + 1
        }
        var reported: Set<String> = []
        // v16.93 · 已知名集合（builtin + 已定义）· 用于 typo 建议
        let knownNames: Set<String> = MaiLangSyntaxHighlighter.allCompletionCandidates.reduce(into: definedNames) {
            $0.insert($1)
        }
        for t in tokens where t.kind == .identifier {
            let upper = t.text.uppercased()
            // 仅检测全大写英文字母+数字（trader 麦语言习惯）· 跳过中文/特殊字符
            guard upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                  upper.first?.isLetter == true,
                  upper.count >= 2 else { continue }
            if MaiLangSyntaxHighlighter.isReservedWord(upper) { continue }
            if definedNames.contains(upper) { continue }
            // 已报告同名只警告一次（首次出现）
            if reported.contains(upper) { continue }
            reported.insert(upper)
            // v16.93 · typo 建议（Levenshtein 距离 ≤ 2 且长度差 ≤ 2 的最近已知名）
            var message = "未定义的标识符 \(t.text)（可能 typo · 检查是否拼错变量名或缺定义）"
            if let suggestion = closestKnownName(upper, in: knownNames) {
                message += " · 可能是 `\(suggestion)`？"
            }
            warnings.append(MaiLangLintWarning(
                line: lineOf(t.range.location),
                kind: .undefinedVariable,
                message: message))
        }

        return warnings.sorted { $0.line < $1.line }
    }

    /// v16.93 · 找最近已知名（Levenshtein 距离 ≤ 2 + 长度差 ≤ 2 + 距离最小 · 平局取最短）
    /// 返回 nil 表示无足够接近的建议
    static func closestKnownName(_ word: String, in known: Set<String>) -> String? {
        guard word.count >= 3 else { return nil }   // 短词建议噪音大
        var best: (name: String, dist: Int)? = nil
        for name in known {
            // 性能优化：长度差超 2 直接跳过
            guard abs(name.count - word.count) <= 2 else { continue }
            let d = levenshtein(word, name)
            if d == 0 { continue }   // 相等（已 reserved/defined 检查过 · 防御）
            if d > 2 { continue }
            if best == nil || d < best!.dist || (d == best!.dist && name.count < best!.name.count) {
                best = (name, d)
            }
        }
        return best?.name
    }

    /// Levenshtein 距离（动态规划 O(m*n)）· 仅小字符串使用
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aa = Array(a)
        let bb = Array(b)
        let m = aa.count
        let n = bb.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,        // 删
                    curr[j - 1] + 1,    // 插
                    prev[j - 1] + cost  // 替换
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
