// MainApp · Shell · v17.0 PoC Step 1
// Pane 切分布局枚举（1/2/4/6/9 预设 + custom）

import Foundation

public enum PaneLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case single          // 1
    case twoVertical     // 2 上下
    case twoHorizontal   // 2 左右
    case four            // 2x2
    case sixGrid         // 2x3（2 行 3 列）
    case nineGrid        // 3x3
    case custom          // 自由拖拽（v17.2+ 实装）

    public var id: String { rawValue }

    public var paneCount: Int {
        switch self {
        case .single:                            return 1
        case .twoVertical, .twoHorizontal:       return 2
        case .four:                              return 4
        case .sixGrid:                           return 6
        case .nineGrid:                          return 9
        case .custom:                            return -1
        }
    }

    public var displayName: String {
        switch self {
        case .single:         return "单图"
        case .twoVertical:    return "上下双图"
        case .twoHorizontal:  return "左右双图"
        case .four:           return "四宫格"
        case .sixGrid:        return "六宫格"
        case .nineGrid:       return "九宫格"
        case .custom:         return "自定义"
        }
    }

    public var emoji: String {
        switch self {
        case .single:         return "▢"
        case .twoVertical:    return "⬓"
        case .twoHorizontal:  return "◫"
        case .four:           return "⊞"
        case .sixGrid:        return "▦"
        case .nineGrid:       return "▩"
        case .custom:         return "⌗"
        }
    }
}
