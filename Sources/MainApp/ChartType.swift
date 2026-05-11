// MainApp · 主图图表类型（v17.13 A1.1 · candlestick / heikinAshi）
//
// 设计要点（Karpathy "避免过度复杂"）：
// - v1 只两种：candlestick（默认 · 原始 OHLC）+ heikinAshi（平均 K 线 · 看趋势）
// - 变换只影响渲染层 candle 4 值 · 不影响 HUD/hover/indicators（保留原始 OHLC 显示）
// - UserDefaults 持久化 key=chartType.v1
//
// 未来扩展（按工作清单）：
// - A1.2 Renko / A1.3 Line/Area/Baseline / A1.4 Hollow/Bars OHLC

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation

enum ChartType: String, CaseIterable, Identifiable, Codable {
    case candlestick
    case heikinAshi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .candlestick: return "K 线"
        case .heikinAshi:  return "Heikin Ashi"
        }
    }

    var icon: String {
        switch self {
        case .candlestick: return "chart.bar.xaxis"
        case .heikinAshi:  return "chart.bar.doc.horizontal"
        }
    }
}

enum ChartTypeStore {
    static let key = "chartType.v1"

    static func load(defaults: UserDefaults = .standard) -> ChartType? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return ChartType(rawValue: raw)
    }

    static func save(_ type: ChartType, defaults: UserDefaults = .standard) {
        defaults.set(type.rawValue, forKey: key)
    }
}

#endif
