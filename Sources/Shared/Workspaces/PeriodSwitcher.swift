// WP-44 数据模型 1 · 9 周期默认快捷键映射
// D2 §2 多周期切换：1m/5m/15m/30m/1h/4h/日/周/月 → Cmd+1 ~ Cmd+9
// D1 §3 原则 5 键盘一等：所有常用周期都有快捷键
//
// 数据模型层只承担"映射数据"，UI 层负责实际键盘事件绑定（监听 + 触发周期切换）

import Foundation

/// 9 周期快捷键映射 · 静态数据 · UI 层引用此处定义实际绑定键盘
public enum PeriodSwitcher {

    /// Stage A 主推的 9 个周期（按用户切换频率排序）
    public static let default9Periods: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30,
        .hour1, .hour4,
        .daily, .weekly, .monthly,
    ]

    /// macOS Carbon kVK_ANSI_1..9 → 数字键 1-9 的 keyCode
    /// 注意：1-9 在 keyCode 上不是连续的（Apple HID Usage 顺序）
    private static let digitKeyCodes: [UInt16] = [
        18,  // 1
        19,  // 2
        20,  // 3
        21,  // 4
        23,  // 5
        22,  // 6
        26,  // 7
        28,  // 8
        25,  // 9
    ]

    /// NSEvent.ModifierFlags.command rawValue
    public static let commandModifier: UInt32 = 0x100000

    /// 周期 → 默认快捷键（Cmd+1..9）；不在 default9Periods 内返回 nil
    public static func defaultShortcut(for period: KLinePeriod) -> WorkspaceShortcut? {
        guard let index = default9Periods.firstIndex(of: period) else { return nil }
        return WorkspaceShortcut(keyCode: digitKeyCodes[index], modifierFlags: commandModifier)
    }

    /// 快捷键 → 周期（反查；非默认快捷键返回 nil）
    public static func period(forShortcut shortcut: WorkspaceShortcut) -> KLinePeriod? {
        guard shortcut.modifierFlags == commandModifier,
              let index = digitKeyCodes.firstIndex(of: shortcut.keyCode),
              index < default9Periods.count
        else { return nil }
        return default9Periods[index]
    }

    /// 默认 9 周期的全套快捷键映射（便于 UI 一次性注册）
    public static var defaultShortcutMap: [(period: KLinePeriod, shortcut: WorkspaceShortcut)] {
        zip(default9Periods, digitKeyCodes).map { period, keyCode in
            (period: period, shortcut: WorkspaceShortcut(keyCode: keyCode, modifierFlags: commandModifier))
        }
    }
}
