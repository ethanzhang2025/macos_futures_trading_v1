// WP-65 v15.22 batch1 · 麦语言 syntax 高亮 · token 化（tolerant · 不抛错 · 编辑器实时高亮用）
//
// 与 IndicatorCore.Lexer 区别：
// - IndicatorCore.Lexer 严格语义 · 错误 throw（用于 Interpreter 执行）
// - MaiLangSyntaxHighlighter tolerant · 错误字符仍输出 .error token（用于编辑器实时刷新）
//
// 设计：
// - token 含 NSRange（UTF-16 偏移量 · 适配 NSAttributedString / NSTextView）
// - 分类语义（keyword / builtinFunc / number / string / comment / drawAttribute / operatorPunct / identifier / error）
// - 不返回 Color · 由 UI 层根据 SyntaxColorKind 选具体配色（深/浅主题适配）

import Foundation

/// token 的颜色语义分类
public enum SyntaxColorKind: String, Sendable, Equatable, CaseIterable {
    case keyword           // AND / OR / NOT / IF / THEN / ELSE
    case builtinFunc       // MA / EMA / CLOSE / HHV / IFELSE 等 60+
    case number            // 123 / 3.14
    case string            // "文字" / '文字'
    case comment           // {...} / //...
    case drawAttribute     // COLORRED / LINETHICK2 / DOTLINE
    case operatorPunct     // + - * / % : := = > < <= >= <>
    case identifier        // 用户变量 / 未识别（CLOSE/OPEN 等保留字也归这里 · 不强分）
    case error             // 无法识别字符（仍输出 · UI 标红）
}

/// 一个高亮 token · UTF-16 NSRange 适配 NSAttributedString
public struct SyntaxToken: Sendable, Equatable {
    public let kind: SyntaxColorKind
    public let range: NSRange      // UTF-16 偏移
    public let text: String        // 原文片段（调试 + 测试可读）

    public init(kind: SyntaxColorKind, range: NSRange, text: String) {
        self.kind = kind
        self.range = range
        self.text = text
    }
}

/// 麦语言 syntax 高亮 token 化器（tolerant · 不抛错）
public enum MaiLangSyntaxHighlighter {

    /// v15.22 batch9 · 自动补全候选词全集（关键字 + 内置函数 + 绘图属性 · 已大写）
    public static var allCompletionCandidates: [String] {
        Array(keywords).sorted() + Array(builtinFuncs).sorted() + Array(drawAttributesExact).sorted()
    }

    /// v15.22 batch31 · 判断 word 是否为麦语言保留字（任一类 · 用于编辑器智能大写转换）
    /// 大小写不敏感（内部 uppercased 后查表）
    public static func isReservedWord(_ word: String) -> Bool {
        let upper = word.uppercased()
        return keywords.contains(upper)
            || builtinFuncs.contains(upper)
            || drawAttributesExact.contains(upper)
    }

    /// 逻辑 / 控制流关键字（与 IndicatorCore.Lexer logicKeywords 一致 + IF/THEN/ELSE 控制流）
    static let keywords: Set<String> = [
        "AND", "OR", "NOT",
        "IF", "THEN", "ELSE", "ELSIF",   // 部分方言支持
    ]

    /// 内置函数名（与 IndicatorCore.BuiltinFunctions.all 同步 · 60+ 函数）
    /// 后续可加脚本验证 / 生成保持一致
    static let builtinFuncs: Set<String> = [
        // 均线
        "MA", "EMA", "SMA", "DMA", "WMA",
        // 引用
        "REF", "BARSLAST", "HHVBARS", "LLVBARS",
        "BARSSINCE", "BARSCOUNT", "VALUEWHEN", "FILTER", "BACKSET",
        // 统计
        "HHV", "LLV", "COUNT", "SUM", "STD", "AVEDEV",
        "VARIANCE", "RANGE", "MEDIAN", "LASTPEAK",
        // 逻辑
        "IF", "CROSS", "CROSSDOWN", "EVERY", "EXIST", "LONGCROSS",
        "BETWEEN", "IFF", "PEAKBARS", "TROUGHBARS",
        // 数学
        "ABS", "MAX", "MIN", "POW", "SQRT", "LOG", "EXP",
        "CEILING", "FLOOR", "INTPART", "MOD", "ROUND", "SIGN",
        "DEVSQ", "SUMBARS", "MULAR", "CONST", "LAST",
        // 高级
        "SLOPE", "FORCAST",
        // 时间
        "DATE", "TIME", "HOUR", "MINUTE",
        "YEAR", "MONTH", "DAY", "WEEKDAY",
        // 位置
        "ISLASTBAR", "BARPOS",
        // 价量字段（视为内置函数 / 数据源）
        "OPEN", "HIGH", "LOW", "CLOSE", "VOLUME", "AMOUNT", "OPI",
        // v15.96 · 30 个高频经典指标 · 与 MaiLangFunctionSignatures.entries 同步
        "ADX", "BBI", "BIAS", "CCI", "CMO", "AR", "BR", "AO", "COPPOCK",
        "AROONOSC", "AROONL", "AROONS",
        "CMF", "CHO", "ADL",
        "ATR", "ATRPCT", "CHOPPINESS", "ANNUALSTD",
        "CHANDELIERL", "CHANDELIERS",
        "BOLLU", "BOLLM", "BOLLL", "BOLLW", "BOLLPCT",
        "BASIS", "BETA", "CLAMPMAX", "CLAMPMIN",
    ]

    /// 绘图属性关键字（与 IndicatorCore.Lexer drawAttributes 同步）
    static let drawAttributesExact: Set<String> = [
        "COLORRED", "COLORGREEN", "COLORBLUE", "COLORWHITE", "COLORYELLOW",
        "COLORCYAN", "COLORMAGENTA", "COLORGRAY", "COLORBLACK",
        "DOTLINE", "POINTDOT", "CIRCLELINE", "CROSSDOT", "STICK",
        "VOLSTICK", "LINESTICK", "COLORSTICK",
        "LINETHICK1", "LINETHICK2", "LINETHICK3", "LINETHICK4",
        "LINETHICK5", "LINETHICK6", "LINETHICK7", "LINETHICK8", "LINETHICK9",
        "NODRAW", "NOTEXT", "DRAWABOVE",
    ]

    /// 主入口 · tolerant · 错误字符也输出 token（kind=.error）
    public static func tokenize(_ source: String) -> [SyntaxToken] {
        let nsSource = source as NSString
        let length = nsSource.length
        var tokens: [SyntaxToken] = []
        var i = 0

        while i < length {
            let ch = nsSource.character(at: i)
            let scalar = UnicodeScalar(ch)

            // 跳过空白（不输出 token · 编辑器渲染保留原文）
            if let s = scalar, CharacterSet.whitespacesAndNewlines.contains(s) {
                i += 1
                continue
            }

            // 块注释 { ... }
            if ch == 0x7B {  // '{'
                let start = i
                i += 1
                while i < length && nsSource.character(at: i) != 0x7D {  // '}'
                    i += 1
                }
                if i < length { i += 1 }  // 吃掉 '}'（不闭合也算 · tolerant）
                let range = NSRange(location: start, length: i - start)
                tokens.append(SyntaxToken(kind: .comment, range: range, text: nsSource.substring(with: range)))
                continue
            }

            // 行注释 //
            if ch == 0x2F && i + 1 < length && nsSource.character(at: i + 1) == 0x2F {
                let start = i
                while i < length && nsSource.character(at: i) != 0x0A {  // '\n'
                    i += 1
                }
                let range = NSRange(location: start, length: i - start)
                tokens.append(SyntaxToken(kind: .comment, range: range, text: nsSource.substring(with: range)))
                continue
            }

            // 字符串
            if ch == 0x27 || ch == 0x22 {  // ' "
                let quote = ch
                let start = i
                i += 1
                while i < length && nsSource.character(at: i) != quote && nsSource.character(at: i) != 0x0A {
                    i += 1
                }
                if i < length && nsSource.character(at: i) == quote { i += 1 }  // 吃掉闭合 · 不闭合也 tolerant
                let range = NSRange(location: start, length: i - start)
                tokens.append(SyntaxToken(kind: .string, range: range, text: nsSource.substring(with: range)))
                continue
            }

            // 数字
            if isDigit(ch) || (ch == 0x2E && i + 1 < length && isDigit(nsSource.character(at: i + 1))) {
                let start = i
                var hasDot = ch == 0x2E
                i += 1
                while i < length {
                    let c = nsSource.character(at: i)
                    if isDigit(c) {
                        i += 1
                    } else if c == 0x2E && !hasDot {
                        hasDot = true
                        i += 1
                    } else {
                        break
                    }
                }
                let range = NSRange(location: start, length: i - start)
                tokens.append(SyntaxToken(kind: .number, range: range, text: nsSource.substring(with: range)))
                continue
            }

            // 标识符 / 关键字 / 函数 / 绘图属性
            if isIdentStart(ch) {
                let start = i
                i += 1
                while i < length && isIdentContinue(nsSource.character(at: i)) {
                    i += 1
                }
                let range = NSRange(location: start, length: i - start)
                let raw = nsSource.substring(with: range)
                let kind = classifyIdentifier(raw)
                tokens.append(SyntaxToken(kind: kind, range: range, text: raw))
                continue
            }

            // 运算符 / 分隔符
            if let opLen = matchOperator(at: i, in: nsSource) {
                let range = NSRange(location: i, length: opLen)
                tokens.append(SyntaxToken(kind: .operatorPunct, range: range, text: nsSource.substring(with: range)))
                i += opLen
                continue
            }

            // 无法识别 · tolerant 输出 .error 单字符
            let range = NSRange(location: i, length: 1)
            tokens.append(SyntaxToken(kind: .error, range: range, text: nsSource.substring(with: range)))
            i += 1
        }

        return tokens
    }

    // MARK: - 内部分类

    static func classifyIdentifier(_ raw: String) -> SyntaxColorKind {
        let upper = raw.uppercased()
        if keywords.contains(upper) { return .keyword }
        if drawAttributesExact.contains(upper) { return .drawAttribute }
        if upper.hasPrefix("COLOR") || upper.hasPrefix("LINETHICK") { return .drawAttribute }
        if builtinFuncs.contains(upper) { return .builtinFunc }
        return .identifier
    }

    /// 匹配运算符（含双字符 := <= >= <>）· 返回长度（1 或 2）· 没匹配返回 nil
    private static func matchOperator(at i: Int, in s: NSString) -> Int? {
        let ch = s.character(at: i)
        // 双字符
        if i + 1 < s.length {
            let next = s.character(at: i + 1)
            switch (ch, next) {
            case (0x3A, 0x3D): return 2   // :=
            case (0x3C, 0x3D): return 2   // <=
            case (0x3E, 0x3D): return 2   // >=
            case (0x3C, 0x3E): return 2   // <>
            default: break
            }
        }
        // 单字符
        switch ch {
        case 0x2B, 0x2D, 0x2A, 0x2F, 0x25,         // + - * / %
             0x28, 0x29, 0x2C, 0x3B,               // ( ) , ;
             0x3D, 0x3C, 0x3E, 0x3A:               // = < > :
            return 1
        default:
            return nil
        }
    }

    private static func isDigit(_ ch: unichar) -> Bool {
        ch >= 0x30 && ch <= 0x39
    }

    private static func isIdentStart(_ ch: unichar) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) ||  // A-Z
        (ch >= 0x61 && ch <= 0x7A) ||  // a-z
        ch == 0x5F                      // _
    }

    private static func isIdentContinue(_ ch: unichar) -> Bool {
        isIdentStart(ch) || isDigit(ch)
    }
}
