// MainApp · HUD 自定义字段 v15.14
// 让用户选 HUD 显示哪些信息（默认仅 .debug · 与 v15.13 行为一致 · 用户主动加才显其他字段）
//
// 设计要点（Karpathy "避免过度复杂"）：
// - 6 个 case 固定（不让用户自加 · 简化数据流）
// - 全局共享 · 不按合约/周期隔离（用户期望"我的 HUD 偏好跨合约一致"）
// - Codable Set 持久化 UserDefaults · v1 单独 key · UserDefaults 不存在则 fallback default
// - debug 默认开（保 v13.x 之前行为 · 用户实战不需可关）
// - ohlc/change/volume/openInterest/timestamp 默认关（用户主动加才显示 · 避免 HUD 冲突主图）

import Foundation

/// HUD 可选字段
public enum HUDFieldKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case ohlc          // 最新 K 线 OHLC（开高低收）
    case change        // 涨跌幅 vs preSettle（与 priceTopBar 重复 · 移到 HUD 时关闭顶栏）
    case amplitude     // v15.20 batch54 · 振幅 = (visible.high - visible.low) / preSettle %
    case volume        // 最新 K 线 volume
    case volumeRatio   // v15.20 batch54 · 量比 = 当根 / 前 5 根均值
    case openInterest  // 最新 K 线 OI（期货特有）
    case atr           // v15.20 batch54 · ATR(14) Wilder · trader 设止损用
    case timestamp     // 最新 K 线时间戳
    case sectorInfo    // v15.56 · 板块归属 + 板块平均涨跌 + 龙头/弱势（trader 横向感知）
    case debug         // 调试信息（视野/起点/帧时 · v13.x 之前默认行为）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ohlc:         return "OHLC（开高低收）"
        case .change:       return "涨跌幅"
        case .amplitude:    return "振幅（visible 高低 / 昨结）"
        case .volume:       return "成交量"
        case .volumeRatio:  return "量比（当根 / 前 5 根均值）"
        case .openInterest: return "持仓量"
        case .atr:          return "ATR(14) 真实波幅均值"
        case .timestamp:    return "时间戳"
        case .sectorInfo:   return "板块归属（板块均值 / 龙头 / 弱势）"
        case .debug:        return "调试信息（可见/起点/帧时）"
        }
    }

    /// v15.16 hotfix #10：HUD 渲染顺序（与 ChartScene.hud 内 if 链顺序一致 · 用户视觉对齐）
    /// 时间戳放最上 · debug 放最下 · 中间是数据字段
    /// v15.20 batch54：amplitude 跟 change 后 · volumeRatio 跟 volume 后 · atr 跟 openInterest 后
    /// v15.56：sectorInfo 放 atr 后 / debug 前（横向板块对比 · 与 ATR 同视觉权重）
    public static let displayOrder: [HUDFieldKind] = [
        .timestamp, .ohlc, .change, .amplitude, .volume, .volumeRatio, .openInterest, .atr, .sectorInfo, .debug
    ]
}

/// HUD 字段偏好（全局 · 跨合约共享）
public struct HUDFieldsBook: Sendable, Codable, Equatable {
    public var fields: Set<HUDFieldKind>

    public init(fields: Set<HUDFieldKind>) {
        self.fields = fields
    }

    public static let `default` = HUDFieldsBook(fields: [.debug])
}

// MARK: - UserDefaults 加载/保存

public enum HUDFieldsStore {
    public static let key = "hudFields.v1"

    /// 从 UserDefaults 加载 · 失败/不存在返回 nil（caller 决定 fallback default）
    public static func load(defaults: UserDefaults = .standard) -> HUDFieldsBook? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HUDFieldsBook.self, from: data)
    }

    /// 写入 UserDefaults · 失败静默
    public static func save(_ book: HUDFieldsBook, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }
}
