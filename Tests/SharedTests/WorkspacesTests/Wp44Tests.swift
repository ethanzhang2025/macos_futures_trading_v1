// WP-44 数据模型层测试 · PeriodSwitcher + WindowGrid
// 9 周期映射 / 反查 / 6 网格预设 / 归一化坐标 / applyTo

import Testing
import Foundation
@testable import Shared

// MARK: - 1. PeriodSwitcher

@Suite("PeriodSwitcher · 9 周期默认快捷键")
struct PeriodSwitcherTests {

    @Test("default9Periods 顺序与数量")
    func default9PeriodsList() {
        let periods = PeriodSwitcher.default9Periods
        #expect(periods.count == 9)
        #expect(periods == [.minute1, .minute5, .minute15, .minute30,
                           .hour1, .hour4,
                           .daily, .weekly, .monthly])
    }

    @Test("Cmd+1 → 1m / Cmd+9 → 月")
    func defaultShortcutsBoundary() {
        let s1m = PeriodSwitcher.defaultShortcut(for: .minute1)
        let sMonthly = PeriodSwitcher.defaultShortcut(for: .monthly)
        #expect(s1m?.modifierFlags == 0x100000)
        #expect(s1m?.keyCode == 18)  // 数字键 1 keyCode
        #expect(sMonthly?.keyCode == 25)  // 数字键 9 keyCode
    }

    @Test("非默认 9 周期返回 nil")
    func nonDefaultPeriodReturnsNil() {
        #expect(PeriodSwitcher.defaultShortcut(for: .second1) == nil)
        #expect(PeriodSwitcher.defaultShortcut(for: .minute3) == nil)  // 3m 不在 default9
        #expect(PeriodSwitcher.defaultShortcut(for: .hour2) == nil)
    }

    @Test("反查：Cmd+1 → 1m / Cmd+5 → 1h")
    func periodForShortcutLookup() {
        let cmd1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x100000)
        let cmd5 = WorkspaceShortcut(keyCode: 23, modifierFlags: 0x100000)  // 数字 5 keyCode
        #expect(PeriodSwitcher.period(forShortcut: cmd1) == .minute1)
        #expect(PeriodSwitcher.period(forShortcut: cmd5) == .hour1)
    }

    @Test("反查：modifier 不对返回 nil（仅 Cmd+ 数字识别）")
    func wrongModifierReturnsNil() {
        let shift1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x20000)  // shift
        let optionCmd1 = WorkspaceShortcut(keyCode: 18, modifierFlags: 0x180000)  // option+cmd
        #expect(PeriodSwitcher.period(forShortcut: shift1) == nil)
        #expect(PeriodSwitcher.period(forShortcut: optionCmd1) == nil)
    }

    @Test("反查：未知 keyCode 返回 nil")
    func unknownKeyCodeReturnsNil() {
        let unknown = WorkspaceShortcut(keyCode: 99, modifierFlags: 0x100000)
        #expect(PeriodSwitcher.period(forShortcut: unknown) == nil)
    }

    @Test("defaultShortcutMap 提供 9 条完整映射")
    func defaultShortcutMapCompleteness() {
        let map = PeriodSwitcher.defaultShortcutMap
        #expect(map.count == 9)
        #expect(map.first?.period == .minute1)
        #expect(map.last?.period == .monthly)
        // 所有 modifier 都是 Cmd
        #expect(map.allSatisfy { $0.shortcut.modifierFlags == 0x100000 })
    }

    @Test("正反查闭环（每个 default period → shortcut → period 一致）")
    func roundTripConsistency() {
        for period in PeriodSwitcher.default9Periods {
            let shortcut = PeriodSwitcher.defaultShortcut(for: period)
            let back = shortcut.flatMap { PeriodSwitcher.period(forShortcut: $0) }
            #expect(back == period)
        }
    }
}

// MARK: - 2. WindowGridPreset

@Suite("WindowGridPreset · 网格预设属性")
struct WindowGridPresetPropertiesTests {

    @Test("6 个预设全枚举")
    func allCases() {
        #expect(WindowGridPreset.allCases.count == 6)
        #expect(Set(WindowGridPreset.allCases.map(\.rawValue))
                == Set(["single", "horizontal2", "vertical2", "grid2x2", "grid2x3", "grid3x2"]))
    }

    @Test("maxWindows 各预设")
    func maxWindowsPerPreset() {
        #expect(WindowGridPreset.single.maxWindows == 1)
        #expect(WindowGridPreset.horizontal2.maxWindows == 2)
        #expect(WindowGridPreset.vertical2.maxWindows == 2)
        #expect(WindowGridPreset.grid2x2.maxWindows == 4)
        #expect(WindowGridPreset.grid2x3.maxWindows == 6)
        #expect(WindowGridPreset.grid3x2.maxWindows == 6)
    }

    @Test("dimensions (rows, cols)")
    func dimensionsPerPreset() {
        #expect(WindowGridPreset.single.dimensions == (1, 1))
        #expect(WindowGridPreset.horizontal2.dimensions == (1, 2))
        #expect(WindowGridPreset.vertical2.dimensions == (2, 1))
        #expect(WindowGridPreset.grid2x2.dimensions == (2, 2))
        #expect(WindowGridPreset.grid2x3.dimensions == (2, 3))
        #expect(WindowGridPreset.grid3x2.dimensions == (3, 2))
    }
}

@Suite("WindowGridPreset · 归一化布局计算")
struct WindowGridLayoutTests {

    @Test("single 满屏单窗口")
    func singleFullscreen() {
        let frames = WindowGridPreset.single.layout(forWindowCount: 1)
        #expect(frames.count == 1)
        #expect(frames[0] == LayoutFrame(x: 0, y: 0, width: 1, height: 1))
    }

    @Test("horizontal2 左右 2 等分")
    func horizontalSplit() {
        let frames = WindowGridPreset.horizontal2.layout(forWindowCount: 2)
        #expect(frames.count == 2)
        #expect(frames[0] == LayoutFrame(x: 0, y: 0, width: 0.5, height: 1))
        #expect(frames[1] == LayoutFrame(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    @Test("vertical2 上下 2 等分")
    func verticalSplit() {
        let frames = WindowGridPreset.vertical2.layout(forWindowCount: 2)
        #expect(frames.count == 2)
        #expect(frames[0] == LayoutFrame(x: 0, y: 0, width: 1, height: 0.5))
        #expect(frames[1] == LayoutFrame(x: 0, y: 0.5, width: 1, height: 0.5))
    }

    @Test("grid2x2 4 等分（左上→右上→左下→右下）")
    func grid2x2() {
        let frames = WindowGridPreset.grid2x2.layout(forWindowCount: 4)
        #expect(frames.count == 4)
        #expect(frames[0] == LayoutFrame(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(frames[1] == LayoutFrame(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(frames[2] == LayoutFrame(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(frames[3] == LayoutFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test("grid2x3 6 个窗口正确分布（2 行 3 列）")
    func grid2x3() {
        let frames = WindowGridPreset.grid2x3.layout(forWindowCount: 6)
        #expect(frames.count == 6)
        // 第 0 个：左上
        #expect(frames[0].x == 0)
        #expect(frames[0].y == 0)
        // 第 2 个：右上
        let third = frames[2]
        #expect(abs(third.x - 2.0/3.0) < 0.0001)
        #expect(third.y == 0)
        // 第 3 个：第二行第一列
        #expect(frames[3].x == 0)
        #expect(frames[3].y == 0.5)
        // 总宽度覆盖 1.0（横向）
        #expect(abs(frames[2].x + frames[2].width - 1.0) < 0.0001)
    }

    @Test("超出 maxWindows 时截断到 maxWindows")
    func windowCountExceedsMax() {
        let frames = WindowGridPreset.single.layout(forWindowCount: 10)
        #expect(frames.count == 1)

        let g4 = WindowGridPreset.grid2x2.layout(forWindowCount: 100)
        #expect(g4.count == 4)
    }

    @Test("少于 maxWindows 时只填充实际数量")
    func partialFill() {
        let frames = WindowGridPreset.grid2x2.layout(forWindowCount: 2)
        #expect(frames.count == 2)
        // 前 2 个仍按 grid2x2 算（左上 + 右上）
        #expect(frames[0] == LayoutFrame(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(frames[1] == LayoutFrame(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    @Test("0 / 负数 windowCount 返回空")
    func zeroOrNegativeReturnsEmpty() {
        #expect(WindowGridPreset.single.layout(forWindowCount: 0).isEmpty)
        #expect(WindowGridPreset.grid2x2.layout(forWindowCount: -1).isEmpty)
    }
}

@Suite("WindowGridPreset · applyTo 套到 windows")
struct WindowGridApplyTests {

    private func makeWindow(_ instrumentID: String) -> WindowLayout {
        WindowLayout(
            instrumentID: instrumentID,
            period: .minute5,
            indicatorIDs: ["MA"],
            frame: LayoutFrame(x: 999, y: 999, width: 999, height: 999)  // 旧值
        )
    }

    @Test("applyTo 替换 frame，保留其他字段")
    func applyReplacesFrameKeepsOtherFields() {
        let windows = [makeWindow("rb2510"), makeWindow("hc2510")]
        let result = WindowGridPreset.horizontal2.applyTo(windows)

        #expect(result.count == 2)
        #expect(result[0].frame == LayoutFrame(x: 0, y: 0, width: 0.5, height: 1))
        #expect(result[1].frame == LayoutFrame(x: 0.5, y: 0, width: 0.5, height: 1))

        // 其他字段保留
        #expect(result[0].instrumentID == "rb2510")
        #expect(result[1].instrumentID == "hc2510")
        #expect(result[0].period == .minute5)
        #expect(result[0].indicatorIDs == ["MA"])
    }

    @Test("applyTo 多余窗口被截断")
    func applyTrimsExcess() {
        let windows = (0..<10).map { makeWindow("ag\($0)") }
        let result = WindowGridPreset.grid2x2.applyTo(windows)
        #expect(result.count == 4)
        #expect(result.map(\.instrumentID) == ["ag0", "ag1", "ag2", "ag3"])
    }

    @Test("applyTo 空数组返回空")
    func applyEmpty() {
        #expect(WindowGridPreset.grid2x2.applyTo([]).isEmpty)
    }
}
