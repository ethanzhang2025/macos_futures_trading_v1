// WP-65 v15.22 batch38 · 麦语言公式大纲解析测试

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangOutline · WP-65 公式大纲解析")
struct MaiLangOutlineTests {

    @Test("空字符串 → 空大纲")
    func empty() {
        #expect(MaiLangOutline.parse("") == [])
    }

    @Test("单 `:=` 中间变量")
    func singleIntermediate() {
        let src = "DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);"
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].name == "DIF")
        #expect(r[0].line == 1)
        #expect(r[0].isOutput == false)
    }

    @Test("单 `:` 输出绘图")
    func singleOutput() {
        let src = "MID:MA(CLOSE,20),COLORWHITE;"
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].name == "MID")
        #expect(r[0].isOutput == true)
    }

    @Test("MACD 标准 · 3 个定义（DIF/DEA 中间 · MACD 输出）")
    func macdStandard() {
        let src = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2,COLORRED,LINETHICK2;
        """
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 3)
        #expect(r.map { $0.name } == ["DIF", "DEA", "MACD"])
        #expect(r.map { $0.line } == [1, 2, 3])
        #expect(r.map { $0.isOutput } == [false, false, true])
    }

    @Test("跳过 // 行注释")
    func skipLineComment() {
        let src = """
        // SOMECOMMENT:=1;
        REAL:=2;
        """
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].name == "REAL")
        #expect(r[0].line == 2)
    }

    @Test("跳过 { ... } 单行块注释")
    func skipBlockCommentSingleLine() {
        let src = """
        {INNER:=1;}
        REAL:=2;
        """
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].name == "REAL")
    }

    @Test("跳过 { ... } 跨行块注释")
    func skipBlockCommentMultiLine() {
        let src = """
        {开头注释
        INNER1:=1;
        INNER2:=2;
        }
        REAL:=3;
        """
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].name == "REAL")
        #expect(r[0].line == 5)
    }

    @Test("排除保留字（IF:CLOSE 不识别为变量定义）")
    func skipReservedWords() {
        let src = """
        IF:1;
        CLOSE:=2;
        MA:=3;
        """
        // IF/CLOSE/MA 都是保留字 · 全部排除
        #expect(MaiLangOutline.parse(src).isEmpty)
    }

    @Test("非法标识符跳过（以数字开头 / 含空格）")
    func skipInvalidIdentifiers() {
        let src = """
        1ABC:=1;
        AB CD:=2;
        :=3;
        """
        #expect(MaiLangOutline.parse(src).isEmpty)
    }

    @Test("`:=` 优先于 `:` 识别（不会误把 := 拆成 : 和 =）")
    func assignOperatorPrecedence() {
        let src = "X:=Y;"
        let r = MaiLangOutline.parse(src)
        #expect(r.count == 1)
        #expect(r[0].isOutput == false)
    }
}
