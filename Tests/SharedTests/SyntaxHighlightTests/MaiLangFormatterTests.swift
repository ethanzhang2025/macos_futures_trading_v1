// WP-65 v15.23 batch40 · 麦语言公式格式化器测试

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangFormatter · WP-65 公式格式化")
struct MaiLangFormatterTests {

    // MARK: - Whitespace 归一化

    @Test("tab → 4 空格")
    func tabToSpaces() {
        let src = "MA5\t:=\tMA(CLOSE,5);"
        let out = MaiLangFormatter.format(src)
        #expect(!out.contains("\t"))
        #expect(out.contains("MA5    :=    MA(CLOSE, 5);"))
    }

    @Test("行尾空白 trim")
    func trimTrailing() {
        let src = "MA5:=MA(CLOSE,5);   \nMA10:=MA(CLOSE,10);  \t"
        let out = MaiLangFormatter.format(src)
        for line in out.components(separatedBy: "\n") {
            #expect(line == line.trimmingCharacters(in: .whitespaces) || !line.hasSuffix(" "))
            #expect(!line.hasSuffix("\t"))
        }
    }

    // MARK: - 空行折叠

    @Test("3+ 连续空行折叠为 1")
    func collapseBlankLines() {
        let src = "A:=1;\n\n\n\n\nB:=2;"
        let out = MaiLangFormatter.format(src)
        let blankRuns = out.components(separatedBy: "\n").map { $0.isEmpty }
        // 期望 [false, true, false]
        #expect(blankRuns == [false, true, false])
    }

    @Test("单空行保留")
    func preserveSingleBlankLine() {
        let src = "A:=1;\n\nB:=2;"
        let out = MaiLangFormatter.format(src)
        let lines = out.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[1].isEmpty)
    }

    // MARK: - 保留字大写

    @Test("内置函数小写转大写")
    func uppercaseBuiltinFunc() {
        let src = "mid:=ma(close,20);"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("MA(CLOSE, 20)"))
    }

    @Test("关键字大写")
    func uppercaseKeyword() {
        let src = "if x>0 then y:=1 else y:=0;"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("IF"))
        #expect(out.contains("THEN"))
        #expect(out.contains("ELSE"))
    }

    @Test("绘图属性大写")
    func uppercaseDrawAttribute() {
        let src = "VOL:VOLUME,colorred,linethick2;"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("COLORRED"))
        #expect(out.contains("LINETHICK2"))
    }

    @Test("用户变量名不动")
    func preserveUserIdentifier() {
        let src = "MyVar:=MA(CLOSE,5);"
        let out = MaiLangFormatter.format(src)
        // MyVar 不在保留字表 · 应保留原大小写
        #expect(out.contains("MyVar"))
    }

    // MARK: - 字符串 / 注释保护

    @Test("字符串内容不被大写")
    func stringContentNotUppercased() {
        // 'ma is up' 是字符串字面量 · 内部 'ma' 不应被识别为函数名大写
        let src = "MA(close,5)+'ma is up'"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("'ma is up'"))
        #expect(out.contains("CLOSE"))
    }

    @Test("注释内容不被大写")
    func commentContentNotUppercased() {
        let src = "{ ma is here } ma5:=ma(close,5);"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("{ ma is here }"))
        #expect(out.contains("MA(CLOSE, 5)"))
    }

    // MARK: - 逗号后空格

    @Test("逗号后插空格")
    func spaceAfterComma() {
        let src = "MA(CLOSE,5);"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("MA(CLOSE, 5)"))
    }

    @Test("逗号后已有空格不重复")
    func spaceAfterCommaIdempotent() {
        let src = "MA(CLOSE, 5);"
        let out = MaiLangFormatter.format(src)
        // 不应该出现两个空格
        #expect(!out.contains("  "))
        #expect(out.contains("MA(CLOSE, 5)"))
    }

    @Test("字符串内的逗号不动")
    func commaInStringPreserved() {
        let src = "x:='a,b,c';"
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("'a,b,c'"))
    }

    // MARK: - 端到端

    @Test("综合：典型公式格式化")
    func endToEnd() {
        let src = """
        ma5:=ma(close,5);
        ma20:=ma(close,20);


        if ma5>ma20 then x:=1;

        vol:volume,colorred,linethick2;
        """
        let out = MaiLangFormatter.format(src)
        #expect(out.contains("MA(CLOSE, 5)"))
        #expect(out.contains("MA(CLOSE, 20)"))
        #expect(out.contains("IF"))
        #expect(out.contains("THEN"))
        #expect(out.contains("VOLUME, COLORRED, LINETHICK2"))
    }

    @Test("幂等 · 二次 format 结果不变")
    func idempotent() {
        let src = """
        ma5:=ma(close,5);
        if ma5>0 then x:=1;
        """
        let once = MaiLangFormatter.format(src)
        let twice = MaiLangFormatter.format(once)
        #expect(once == twice)
    }

    @Test("空字符串安全")
    func emptyInput() {
        #expect(MaiLangFormatter.format("") == "")
    }
}
