// WP-65 v15.23 batch134 · 麦语言变量依赖测试

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangDependencies · WP-65 公式变量依赖图")
struct MaiLangDependenciesTests {

    @Test("空字符串 → 空数组")
    func empty() {
        #expect(MaiLangDependencies.analyze("") == [])
    }

    @Test("单变量无依赖 · uses 空 · usedBy 空")
    func singleVar() {
        let src = "MA5:=MA(CLOSE,5);"
        let r = MaiLangDependencies.analyze(src)
        #expect(r.count == 1)
        #expect(r[0].name == "MA5")
        #expect(r[0].uses.isEmpty)
        #expect(r[0].usedBy.isEmpty)
    }

    @Test("DIF/DEA/MACD 链式依赖")
    func chainDependency() {
        let src = """
        DIF:=EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:=EMA(DIF,9);
        MACD:(DIF-DEA)*2,COLORRED;
        """
        let r = MaiLangDependencies.analyze(src)
        #expect(r.count == 3)
        // DIF · 无依赖（CLOSE 是内置函数 · 不在 outline 里 · 不算）
        #expect(r[0].name == "DIF")
        #expect(r[0].uses.isEmpty)
        #expect(r[0].usedBy.contains("DEA"))
        #expect(r[0].usedBy.contains("MACD"))
        // DEA · 引用 DIF
        #expect(r[1].name == "DEA")
        #expect(r[1].uses == ["DIF"])
        #expect(r[1].usedBy == ["MACD"])
        // MACD · 引用 DIF + DEA
        #expect(r[2].name == "MACD")
        #expect(r[2].uses.sorted() == ["DEA", "DIF"])
        #expect(r[2].usedBy.isEmpty)
    }

    @Test("注释中提到变量名不算引用（tokenize 排除 comment）")
    func commentNotCount() {
        let src = """
        TEMP:=1;
        {TEMP 仅供注释}
        OUT:CLOSE;
        """
        let r = MaiLangDependencies.analyze(src)
        let temp = r.first { $0.name == "TEMP" }
        #expect(temp != nil)
        #expect(temp?.usedBy.isEmpty == true)
    }

    @Test("大小写不敏感 · dif 引用 DIF 视为同变量")
    func caseInsensitive() {
        let src = """
        DIF:=EMA(CLOSE,12);
        OUT:dif*2;
        """
        let r = MaiLangDependencies.analyze(src)
        let dif = r.first { $0.name == "DIF" }
        #expect(dif?.usedBy == ["OUT"])
    }

    @Test("自引用不算依赖 · 防递归 sanity")
    func selfReferenceIgnored() {
        // 麦语言不允许 self ref · 但 tokenize 会找到 LHS 名 · 我们应排除自身
        let src = "MA5:=MA(CLOSE,5)+MA5;"  // 假设 trader typo
        let r = MaiLangDependencies.analyze(src)
        #expect(r.count == 1)
        #expect(r[0].uses.isEmpty)
    }
}
