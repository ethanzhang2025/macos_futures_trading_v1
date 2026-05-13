// v17.141 · GlobalShortcutsCatalog 数据契约 + 完整性测试

import Testing
import Foundation
@testable import Shared

@Suite("GlobalShortcutsCatalog · 全工程快捷键速查 catalog")
struct GlobalShortcutsCatalogTests {

    @Test("ShortcutWindowScope allCases 11 类完整 · 顺序固定")
    func scopeAllCases() {
        let cases = ShortcutWindowScope.allCases
        #expect(cases.count == 11)
        #expect(cases.first == .global)
        #expect(cases.contains(.chart))
        #expect(cases.contains(.watchlist))
        #expect(cases.contains(.formulaEditor))
        #expect(cases.contains(.sheet))
    }

    @Test("ShortcutWindowScope displayName 全 11 类中文化非空")
    func scopeDisplayNames() {
        for s in ShortcutWindowScope.allCases {
            #expect(!s.displayName.isEmpty, "scope \(s.rawValue) displayName 为空")
        }
        #expect(ShortcutWindowScope.global.displayName.contains("全局"))
        #expect(ShortcutWindowScope.chart.displayName.contains("主图"))
        #expect(ShortcutWindowScope.formulaEditor.displayName.contains("公式编辑器"))
    }

    @Test("sections 至少含 5 个 scope 章节（global / chart / watchlist / formulaEditor / sheet）")
    func sectionsCoverage() {
        let scopes = GlobalShortcutsCatalog.sections.map(\.scope)
        #expect(scopes.contains(.global))
        #expect(scopes.contains(.chart))
        #expect(scopes.contains(.watchlist))
        #expect(scopes.contains(.formulaEditor))
        #expect(scopes.contains(.sheet))
        // global 章节应在第一位（trader UX）
        #expect(GlobalShortcutsCatalog.sections.first?.scope == .global)
    }

    @Test("global section 含核心开窗与帮助快捷键")
    func globalSectionHasCoreShortcuts() {
        guard let section = GlobalShortcutsCatalog.section(for: .global) else {
            Issue.record("global section 缺失"); return
        }
        // 平铺所有 entries
        let allEntries = section.groups.flatMap(\.entries)
        let allKeys = allEntries.map(\.key)
        // 帮助
        #expect(allKeys.contains("⌘⇧/"), "缺 ⌘⇧/ 帮助快捷键")
        // 核心开窗 6 个
        #expect(allKeys.contains("⌘N"))      // 新建主图
        #expect(allKeys.contains("⌘L"))      // 自选合约
        #expect(allKeys.contains("⌘R"))      // 复盘
        #expect(allKeys.contains("⌘B"))      // 预警
        #expect(allKeys.contains("⌘J"))      // 交易日志
        #expect(allKeys.contains("⌘T"))      // 模拟交易
        // ⌘⌥ 系列（主菜单 15 个分析窗口快捷键）
        #expect(allKeys.contains("⌘⌥M"))
        #expect(allKeys.contains("⌘⌥F"))     // 公式编辑器
        #expect(allKeys.contains("⌘⌥K"))     // 公式回测
        #expect(allKeys.contains("⌘⇧D"))     // 主题切换
    }

    @Test("chart section 含周期 / 视口 / 测距核心快捷键")
    func chartSectionHasCoreShortcuts() {
        guard let section = GlobalShortcutsCatalog.section(for: .chart) else {
            Issue.record("chart section 缺失"); return
        }
        let allEntries = section.groups.flatMap(\.entries)
        let allKeys = allEntries.map(\.key)
        #expect(allKeys.contains("⌘1-6"))      // 周期
        #expect(allKeys.contains("⌘0"))        // 重置缩放
        #expect(allKeys.contains("⌘⇧M"))       // 测距
        #expect(allKeys.contains("⌘\\"))       // 画线显隐
        #expect(allKeys.contains("⌘⇧H"))       // HUD 显隐
        #expect(allKeys.contains("⌘⌥1-6"))     // v17.138 时间范围预设
        #expect(allKeys.contains("⌘P"))        // 截图
    }

    @Test("formulaEditor section 含 ⌘/ 注释切换")
    func formulaEditorSectionHasCommentToggle() {
        guard let section = GlobalShortcutsCatalog.section(for: .formulaEditor) else {
            Issue.record("formulaEditor section 缺失"); return
        }
        let allEntries = section.groups.flatMap(\.entries)
        let allKeys = allEntries.map(\.key)
        #expect(allKeys.contains("⌘/"), "缺 ⌘/ 注释切换 · 这是公式编辑器最重要的快捷键之一")
    }

    @Test("sheet section 含 Return / Esc 通用约定")
    func sheetSectionHasStandardKeys() {
        guard let section = GlobalShortcutsCatalog.section(for: .sheet) else {
            Issue.record("sheet section 缺失"); return
        }
        let keys = section.groups.flatMap(\.entries).map(\.key)
        #expect(keys.contains("Return"))
        #expect(keys.contains("Esc"))
    }

    @Test("section(for:) 不存在 scope 返回 nil（非 catalog 列出的 scope）")
    func sectionForMissingScopeReturnsNil() {
        // 这些 scope 在 catalog 中暂未列章节 · 应返回 nil
        // 这是 catalog 故意只覆盖核心窗口的 scope · 其他窗口 scope 在 sheet 显示空
        #expect(GlobalShortcutsCatalog.section(for: .journal) == nil)
        #expect(GlobalShortcutsCatalog.section(for: .review) == nil)
        #expect(GlobalShortcutsCatalog.section(for: .alert) == nil)
    }

    @Test("totalEntries 大于 30（防止 catalog 退化丢条目）")
    func totalEntriesNonTrivial() {
        #expect(GlobalShortcutsCatalog.totalEntries >= 30,
                "catalog 总条目数过低 = \(GlobalShortcutsCatalog.totalEntries)")
    }

    @Test("所有 entry 的 key 与 description 都非空")
    func entriesAllNonEmpty() {
        for section in GlobalShortcutsCatalog.sections {
            for group in section.groups {
                #expect(!group.title.isEmpty, "scope \(section.scope.rawValue) 含空 title")
                for entry in group.entries {
                    #expect(!entry.key.isEmpty,
                            "scope \(section.scope.rawValue) / group '\(group.title)' 含空 key")
                    #expect(!entry.description.isEmpty,
                            "scope \(section.scope.rawValue) / group '\(group.title)' / key '\(entry.key)' description 为空")
                }
            }
        }
    }

    @Test("ShortcutEntry / ShortcutGroup / ShortcutSection Equatable 正常")
    func dataTypesEquatable() {
        let e1 = ShortcutEntry("⌘N", "新建")
        let e2 = ShortcutEntry("⌘N", "新建")
        let e3 = ShortcutEntry("⌘L", "自选")
        #expect(e1 == e2)
        #expect(e1 != e3)
        let g1 = ShortcutGroup("窗口", [e1])
        let g2 = ShortcutGroup("窗口", [e1])
        let g3 = ShortcutGroup("视口", [e1])
        #expect(g1 == g2)
        #expect(g1 != g3)
    }
}
