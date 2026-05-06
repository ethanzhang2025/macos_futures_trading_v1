// WP-65 v15.22 batch26 · 麦语言函数签名静态表测试 · 一致性 + 格式化覆盖

import Testing
import Foundation
@testable import Shared

@Suite("MaiLangFunctionSignatures · WP-65 函数签名静态表")
struct MaiLangFunctionSignaturesTests {

    @Test("entries 中函数 name 唯一（无重复）")
    func uniqueNames() {
        let names = MaiLangFunctionSignatures.entries.map { $0.name }
        #expect(Set(names).count == names.count)
    }

    @Test("all 字典与 entries 数量一致（构造无丢失）")
    func dictMatchesEntries() {
        #expect(MaiLangFunctionSignatures.all.count == MaiLangFunctionSignatures.entries.count)
    }

    @Test("Highlighter.builtinFuncs 中每个函数都有签名（一致性）")
    func consistencyWithHighlighter() {
        let sigNames = Set(MaiLangFunctionSignatures.entries.map { $0.name })
        for name in MaiLangSyntaxHighlighter.builtinFuncs {
            #expect(sigNames.contains(name), "缺签名：\(name)")
        }
    }

    @Test("签名表无多余函数（不在 builtinFuncs 中的不应出现）")
    func noExtraFunctions() {
        let highlighter = MaiLangSyntaxHighlighter.builtinFuncs
        for sig in MaiLangFunctionSignatures.entries {
            #expect(highlighter.contains(sig.name), "签名表多余：\(sig.name)")
        }
    }

    @Test("formatted · 有参函数")
    func formattedWithParams() {
        guard let ma = MaiLangFunctionSignatures.all["MA"] else {
            #expect(Bool(false), "MA 缺失"); return
        }
        #expect(ma.formatted == "MA(序列, 周期 N)")
    }

    @Test("formatted · 无参函数（CLOSE / DATE 等）")
    func formattedZeroParams() {
        guard let close = MaiLangFunctionSignatures.all["CLOSE"] else {
            #expect(Bool(false), "CLOSE 缺失"); return
        }
        #expect(close.formatted == "CLOSE()")
        guard let date = MaiLangFunctionSignatures.all["DATE"] else {
            #expect(Bool(false), "DATE 缺失"); return
        }
        #expect(date.formatted == "DATE()")
    }

    @Test("分类全覆盖（Category.allCases 每个都在 entries 中至少出现 1 次）")
    func allCategoriesUsed() {
        let usedCats = Set(MaiLangFunctionSignatures.entries.map { $0.category })
        for c in MaiLangFunctionSignature.Category.allCases {
            #expect(usedCats.contains(c), "未使用分类：\(c.rawValue)")
        }
    }

    @Test("byCategory · 9 个分类有序输出")
    func byCategoryOrder() {
        let groups = MaiLangFunctionSignatures.byCategory
        #expect(groups.count == MaiLangFunctionSignature.Category.allCases.count)
        // 第一组应为均线（首位 case）
        #expect(groups.first?.0 == .均线)
    }

    @Test("摘要非空（每个签名都有 summary）")
    func summariesNonEmpty() {
        for sig in MaiLangFunctionSignatures.entries {
            #expect(!sig.summary.isEmpty, "缺摘要：\(sig.name)")
        }
    }

    @Test("60+ 函数（接近 builtinFuncs 规模）")
    func sizeReasonable() {
        #expect(MaiLangFunctionSignatures.entries.count >= 60)
    }
}
