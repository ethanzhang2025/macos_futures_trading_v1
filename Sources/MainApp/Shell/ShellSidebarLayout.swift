// MainApp · Shell · v17.64 · Sidebar gadget 协议（用户可配置 section 顺序 / 显隐）
//
// 调研 P2.1 · trader 自定义 sidebar 内容 · UserDefaults 持久化
//
// 5 section（与 ShellSidebar 实装对齐）：
//   - watchlist（自选）
//   - sector（板块）
//   - position（持仓）
//   - anomaly（异动）
//   - training（训练）
//
// 默认顺序：watchlist > sector > position > anomaly > training（与 v17.0 Step 6 一致）
// 默认全部可见

#if canImport(SwiftUI) && os(macOS)
import Foundation

public enum SidebarSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case watchlist
    case sector
    case position
    case anomaly
    case training
    case alertHistory   // v17.70 · 预警历史 mini section（接 SQLiteAlertHistoryStore）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .watchlist:    return "自选"
        case .sector:       return "板块"
        case .position:     return "持仓"
        case .anomaly:      return "异动"
        case .training:     return "训练"
        case .alertHistory: return "预警"
        }
    }

    public var emoji: String {
        switch self {
        case .watchlist:    return "⭐"
        case .sector:       return "🗂"
        case .position:     return "💼"
        case .anomaly:      return "⚠️"
        case .training:     return "🎯"
        case .alertHistory: return "🔔"
        }
    }
}

public struct SidebarLayoutSettings: Codable, Equatable {
    /// 顺序（前 → 后 显示）· 默认 5 section 全可见
    public var order: [SidebarSection]
    /// 隐藏的 section
    public var hidden: Set<SidebarSection>

    public init(order: [SidebarSection] = SidebarSection.allCases, hidden: Set<SidebarSection> = []) {
        self.order = order
        self.hidden = hidden
    }

    /// 可见 section（按 order 顺序 · 排除 hidden）
    public var visibleSections: [SidebarSection] {
        order.filter { !hidden.contains($0) }
    }

    /// 把 section 上移一位（同时跳过 hidden）
    public mutating func moveUp(_ s: SidebarSection) {
        guard let idx = order.firstIndex(of: s), idx > 0 else { return }
        order.swapAt(idx, idx - 1)
    }

    /// 把 section 下移一位
    public mutating func moveDown(_ s: SidebarSection) {
        guard let idx = order.firstIndex(of: s), idx < order.count - 1 else { return }
        order.swapAt(idx, idx + 1)
    }

    /// 切换显隐
    public mutating func toggleHidden(_ s: SidebarSection) {
        if hidden.contains(s) { hidden.remove(s) } else { hidden.insert(s) }
    }

    /// 重置默认（全可见 + 默认顺序）
    public static let `default` = SidebarLayoutSettings()
}

public enum SidebarLayoutStore {
    public static let key = "shell.v1.sidebarLayout"

    public static func load(defaults: UserDefaults = .standard) -> SidebarLayoutSettings {
        guard let data = defaults.data(forKey: key),
              var s = try? JSONDecoder().decode(SidebarLayoutSettings.self, from: data)
        else { return .default }
        // 兼容：缺失的 section（如未来新增）追加到末尾 · 仍可见
        let allCases = SidebarSection.allCases
        for sec in allCases where !s.order.contains(sec) {
            s.order.append(sec)
        }
        // 顺序里多余的（已被删除的 case）过滤掉
        s.order = s.order.filter { allCases.contains($0) }
        return s
    }

    public static func save(_ s: SidebarLayoutSettings, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
    }
}

#endif
