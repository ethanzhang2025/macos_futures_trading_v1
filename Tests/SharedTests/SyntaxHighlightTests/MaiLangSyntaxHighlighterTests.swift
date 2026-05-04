// WP-65 v15.22 batch1 · MaiLangSyntaxHighlighter token 化测试

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangSyntaxHighlighter · WP-65 syntax 高亮 token 化")
struct MaiLangSyntaxHighlighterTests {

    @Test("空字符串 → 空 token")
    func empty() {
        #expect(MaiLangSyntaxHighlighter.tokenize("") == [])
    }

    @Test("数字 · 整数 / 小数 / 前缀点（.5）")
    func numbers() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("123 3.14 .5")
        #expect(tokens.count == 3)
        #expect(tokens.allSatisfy { $0.kind == .number })
        #expect(tokens[0].text == "123")
        #expect(tokens[1].text == "3.14")
        #expect(tokens[2].text == ".5")
    }

    @Test("字符串 · 单引号 / 双引号")
    func strings() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("'abc' \"def\"")
        #expect(tokens.count == 2)
        #expect(tokens.allSatisfy { $0.kind == .string })
        #expect(tokens[0].text == "'abc'")
        #expect(tokens[1].text == "\"def\"")
    }

    @Test("字符串 · 未闭合 tolerant（吃到行尾或 EOF）")
    func unclosedString() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("'未闭合")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .string)
    }

    @Test("注释 · 块 {...} + 行 // ...")
    func comments() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("{这是注释}\n//行注释\nMA")
        #expect(tokens.count == 3)
        #expect(tokens[0].kind == .comment)
        #expect(tokens[1].kind == .comment)
        #expect(tokens[2].kind == .builtinFunc)
        #expect(tokens[2].text == "MA")
    }

    @Test("注释 · 块未闭合 tolerant")
    func unclosedBlockComment() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("{未闭合")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .comment)
    }

    @Test("关键字 · AND / OR / NOT / IF / THEN / ELSE")
    func keywords() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("AND OR NOT IF THEN ELSE")
        #expect(tokens.count == 6)
        #expect(tokens.allSatisfy { $0.kind == .keyword })
    }

    @Test("内置函数 · MA / EMA / CLOSE / HHV / IF / 等")
    func builtinFuncs() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("MA EMA CLOSE HHV REF SUM")
        #expect(tokens.count == 6)
        // IF 既是关键字又是函数 · 当前归 keyword
        #expect(tokens[0].kind == .builtinFunc)   // MA
        #expect(tokens[2].kind == .builtinFunc)   // CLOSE
        #expect(tokens[5].kind == .builtinFunc)   // SUM
    }

    @Test("绘图属性 · 颜色 / 线型 / 线宽 · COLORRED / DOTLINE / LINETHICK2")
    func drawAttributes() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("COLORRED DOTLINE LINETHICK2 NODRAW")
        #expect(tokens.count == 4)
        #expect(tokens.allSatisfy { $0.kind == .drawAttribute })
    }

    @Test("绘图属性 · COLOR + hex 前缀（COLORFF8800）")
    func drawAttributeHexColor() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("COLORFF8800")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .drawAttribute)
    }

    @Test("用户标识符 · 非关键字非函数 → identifier")
    func userIdentifier() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("MyVar _temp ABC123")
        #expect(tokens.count == 3)
        #expect(tokens.allSatisfy { $0.kind == .identifier })
    }

    @Test("运算符 · 单字符 + - * / % ( ) , ; = < >")
    func operatorsSingle() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("+ - * / % ( ) , ; = < >")
        #expect(tokens.count == 12)
        #expect(tokens.allSatisfy { $0.kind == .operatorPunct })
    }

    @Test("运算符 · 双字符 := <= >= <>")
    func operatorsDouble() {
        let tokens = MaiLangSyntaxHighlighter.tokenize(":= <= >= <>")
        #expect(tokens.count == 4)
        #expect(tokens.allSatisfy { $0.kind == .operatorPunct })
        #expect(tokens.allSatisfy { $0.range.length == 2 })
    }

    @Test("非法字符 · 中文字母 / @ / # 都进 .error · tolerant 不抛")
    func errorChars() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("MA@中#")
        // MA = builtinFunc · @ = error · 中 = error · # = error
        #expect(tokens.count == 4)
        #expect(tokens[0].kind == .builtinFunc)
        #expect(tokens[1].kind == .error)
        #expect(tokens[2].kind == .error)
        #expect(tokens[3].kind == .error)
    }

    @Test("综合 · 完整 MACD 公式")
    func macdFormula() {
        let formula = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2,COLORRED;
        """
        let tokens = MaiLangSyntaxHighlighter.tokenize(formula)
        // 验证关键 token 存在
        let kinds = tokens.map(\.kind)
        #expect(kinds.contains(.builtinFunc))     // EMA / CLOSE
        #expect(kinds.contains(.number))          // 12 / 26 / 9 / 2
        #expect(kinds.contains(.operatorPunct))   // := / - / * / 等
        #expect(kinds.contains(.identifier))      // DIF / DEA / MACD
        #expect(kinds.contains(.drawAttribute))   // COLORRED
    }

    @Test("range UTF-16 偏移正确（基础）")
    func rangeOffset() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("MA(5)")
        // MA[0..2) ( [2..3) 5 [3..4) ) [4..5)
        #expect(tokens.count == 4)
        #expect(tokens[0].range == NSRange(location: 0, length: 2))
        #expect(tokens[1].range == NSRange(location: 2, length: 1))
        #expect(tokens[2].range == NSRange(location: 3, length: 1))
        #expect(tokens[3].range == NSRange(location: 4, length: 1))
    }

    @Test("空白跳过 · 不输出 token")
    func skipWhitespace() {
        let tokens = MaiLangSyntaxHighlighter.tokenize("  \n\t MA  \t \n  ")
        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .builtinFunc)
        #expect(tokens[0].text == "MA")
    }
}
