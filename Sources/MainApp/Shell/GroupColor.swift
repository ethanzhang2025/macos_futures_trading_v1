// MainApp · Shell · v17.0 PoC Step 1
// 彩色 group · 同合约联动（杀手锏 · IBKR 7 色 + 富牛 12 色折中 6 色）
// 同色 Pane 共享：symbol / period / 十字光标时间
// v17.0 Step 1：只定枚举 · v17.1 实现联动逻辑
//
// enum 本身跨平台 · SwiftUI Color extension 仅 macOS 守护

import Foundation

public enum GroupColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .red:    return "红组"
        case .orange: return "橙组"
        case .yellow: return "黄组"
        case .green:  return "绿组"
        case .blue:   return "蓝组"
        case .purple: return "紫组"
        }
    }
}

/// 同组共享的绑定数据（symbol/period/crosshair）
public struct SymbolBinding: Equatable, Codable, Sendable {
    public var symbol: String
    public var periodRaw: String?
    public var crosshairUnixTime: Double?
    /// v18 · publish 源 Pane ID 字符串 · 用于 effectiveCrosshair 排除自身回流（避免 ChartScene 同时画本地+外部光标重叠）
    public var crosshairSourcePaneIDString: String?

    public init(
        symbol: String,
        periodRaw: String? = nil,
        crosshairUnixTime: Double? = nil,
        crosshairSourcePaneIDString: String? = nil
    ) {
        self.symbol = symbol
        self.periodRaw = periodRaw
        self.crosshairUnixTime = crosshairUnixTime
        self.crosshairSourcePaneIDString = crosshairSourcePaneIDString
    }
}

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

extension GroupColor {
    public var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        }
    }
}

#endif
