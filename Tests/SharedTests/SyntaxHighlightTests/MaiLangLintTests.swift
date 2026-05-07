// WP-65 v15.23 batch111 · 麦语言 lint 静态检查测试

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangLint · WP-65 公式 lint 检查")
struct MaiLangLintTests {

    @Test("空字符串 → 无警告")
    func empty() {
        #expect(MaiLangLint.analyze("") == [])
    }

    @Test("中间变量未引用 → 警告")
    func unusedIntermediate() {
        let src = """
        TEMP:=MA(CLOSE,5);
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2,COLORRED;
        """
        let warns = MaiLangLint.analyze(src)
        #expect(warns.count == 1)
        #expect(warns[0].line == 1)
        #expect(warns[0].kind == .unusedVariable)
        #expect(warns[0].message.contains("TEMP"))
    }

    @Test("中间变量被后续引用 → 无警告")
    func usedIntermediate() {
        let src = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2;
        """
        #expect(MaiLangLint.analyze(src).isEmpty)
    }

    @Test("输出变量未引用 → 不警告（绘图输出本就供绘图）")
    func unusedOutputAllowed() {
        let src = "MA20:MA(CLOSE,20),COLORWHITE;"
        #expect(MaiLangLint.analyze(src).isEmpty)
    }

    @Test("大小写不敏感引用")
    func caseInsensitiveReference() {
        let src = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        OUT:dif*2;
        """
        // OUT 引用了小写 dif · 应识别为已引用
        #expect(MaiLangLint.analyze(src).isEmpty)
    }

    @Test("多个未使用变量 → 多条警告 · 按行号升序")
    func multipleUnused() {
        let src = """
        A:=1;
        B:=2;
        C:=A+1;
        OUT:C,COLORRED;
        """
        // B 未使用 · A 被 C 引用 · C 被 OUT 引用 · OUT 是输出
        let warns = MaiLangLint.analyze(src)
        #expect(warns.count == 1)
        #expect(warns[0].line == 2)
    }

    @Test("同名变量重复定义 → 警告（首次定义行号回报）")
    func duplicateDefinition() {
        let src = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DIF:=EMA(CLOSE,5)-EMA(CLOSE,10);
        OUT:DIF*2;
        """
        let warns = MaiLangLint.analyze(src)
        // 第 2 行重复定义 DIF · 应有 1 条 duplicateDefinition warning
        let dupes = warns.filter { $0.kind == .duplicateDefinition }
        #expect(dupes.count == 1)
        #expect(dupes[0].line == 2)
        #expect(dupes[0].message.contains("DIF"))
        #expect(dupes[0].message.contains("第 1 行"))
    }

    @Test("重复定义 + 大小写不敏感（dif vs DIF）")
    func duplicateCaseInsensitive() {
        let src = """
        DIF:=EMA(CLOSE,12);
        dif:=EMA(CLOSE,26);
        OUT:DIF*2;
        """
        let warns = MaiLangLint.analyze(src)
        let dupes = warns.filter { $0.kind == .duplicateDefinition }
        #expect(dupes.count == 1)
        #expect(dupes[0].line == 2)
    }

    @Test("注释中提到的变量名不算引用")
    func commentMentionDoesNotCount() {
        let src = """
        TEMP:=MA(CLOSE,5);
        {TEMP 是中间值 · 此处仅注释}
        OUT:CLOSE,COLORWHITE;
        """
        // tokenize 把 { ... } 整体识别为 comment token · 内部 TEMP 不会作为 identifier
        let warns = MaiLangLint.analyze(src)
        #expect(warns.count == 1)
        #expect(warns[0].line == 1)
    }
}
