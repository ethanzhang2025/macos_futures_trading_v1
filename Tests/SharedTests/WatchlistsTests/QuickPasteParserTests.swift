// v15.20 batch55 · QuickPasteParser 单测
// 覆盖：换行/空格/逗号/分号/Tab/顿号/中文符号 / 注释剥离 / 数字过滤 / 去重保序

import Testing
import Foundation
@testable import Shared

@Suite("QuickPasteParser · 自由粘贴合约代码")
struct QuickPasteParserTests {

    @Test("换行分隔 · 基础")
    func newline() {
        let result = QuickPasteParser.parse("rb0\nif0\nau2606")
        #expect(result == ["rb0", "if0", "au2606"])
    }

    @Test("空格分隔（IM 单行复制场景）")
    func space() {
        let result = QuickPasteParser.parse("rb0 if0 au2606")
        #expect(result == ["rb0", "if0", "au2606"])
    }

    @Test("半角逗号 + 全角逗号 + 分号 + 顿号 混合")
    func mixedDelimiters() {
        let result = QuickPasteParser.parse("rb0,if0，au2606;ag2412；cu0、al0")
        #expect(result == ["rb0", "if0", "au2606", "ag2412", "cu0", "al0"])
    }

    @Test("Tab 分隔（Excel 复制场景）")
    func tab() {
        let result = QuickPasteParser.parse("rb0\tif0\tau2606")
        #expect(result == ["rb0", "if0", "au2606"])
    }

    @Test("行尾 # 注释剥离")
    func commentStripping() {
        let result = QuickPasteParser.parse("rb0 # 螺纹\nif0 # 沪深 300")
        #expect(result == ["rb0", "if0"])
    }

    @Test("纯数字 token 过滤（价格/数量误粘）")
    func filterNumeric() {
        let result = QuickPasteParser.parse("rb0 3850 if0 4200")
        #expect(result == ["rb0", "if0"])  // 3850 / 4200 被过滤
    }

    @Test("无字母 token 过滤（仅数字 / 仅符号）")
    func requireLetter() {
        let result = QuickPasteParser.parse("rb0 --- 3850 if0 ###")
        #expect(result == ["rb0", "if0"])
    }

    @Test("去重保序（首次出现保留）")
    func dedupePreserveOrder() {
        let result = QuickPasteParser.parse("rb0 if0 rb0 au2606 if0")
        #expect(result == ["rb0", "if0", "au2606"])
    }

    @Test("大小写保留（trader 输入即期望 · 不归一化）")
    func preserveCase() {
        let result = QuickPasteParser.parse("RB0\nIF0\nau2606")
        #expect(result == ["RB0", "IF0", "au2606"])
    }

    @Test("中文括号 + 引号 token 两端剥离")
    func trimBrackets() {
        let result = QuickPasteParser.parse("\"rb0\" 'if0' (au2606) 【ag2412】")
        #expect(result == ["rb0", "if0", "au2606", "ag2412"])
    }

    @Test("空文本 → 空数组")
    func emptyInput() {
        #expect(QuickPasteParser.parse("") == [])
        #expect(QuickPasteParser.parse("   \n  \t  ") == [])
    }

    @Test("仅注释行 → 空数组")
    func onlyComments() {
        let result = QuickPasteParser.parse("# 这一行全是注释\n  # 缩进注释  ")
        #expect(result == [])
    }

    @Test("混合换行 + 空格 + 注释 + 重复（综合场景）")
    func realisticPaste() {
        let text = """
        # 我的关注列表 2026-05
        rb0  # 螺纹钢
        IF0   3850
        rb0   # 重复 · 应被去重
        au2606,ag2412 cu0
        # 注释行
        """
        let result = QuickPasteParser.parse(text)
        #expect(result == ["rb0", "IF0", "au2606", "ag2412", "cu0"])
    }
}
