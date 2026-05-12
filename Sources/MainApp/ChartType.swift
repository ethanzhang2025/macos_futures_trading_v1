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
    // v17.52 A1.2 · Renko 砖块图（close-based · brickSize 价格阈值）
    case renko
    // v17.53 A1.3 · Line / Area / Baseline（路径图 · 非 candle 渲染）
    case line
    case area
    case baseline
    // v17.54 A1.4 · Hollow / Bars OHLC（candle 变体 · SwiftUI 自绘）
    case hollow
    case barsOHLC
    // v17.55 A1.5 · Point & Figure / Kagi（SwiftUI 自绘）
    case pointFigure
    case kagi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .candlestick: return "K 线"
        case .heikinAshi:  return "Heikin Ashi"
        case .renko:       return "Renko"
        case .line:        return "折线"
        case .area:        return "面积"
        case .baseline:    return "Baseline"
        case .hollow:      return "Hollow"
        case .barsOHLC:    return "Bars OHLC"
        case .pointFigure: return "P&F"
        case .kagi:        return "Kagi"
        }
    }

    var icon: String {
        switch self {
        case .candlestick: return "chart.bar.xaxis"
        case .heikinAshi:  return "chart.bar.doc.horizontal"
        case .renko:       return "square.grid.3x1.below.line.grid.1x2"
        case .line:        return "chart.line.uptrend.xyaxis"
        case .area:        return "chart.xyaxis.line"
        case .baseline:    return "chart.line.flattrend.xyaxis"
        case .hollow:      return "chart.bar"
        case .barsOHLC:    return "chart.bar.fill"
        case .pointFigure: return "xmark.diamond"
        case .kagi:        return "scribble.variable"
        }
    }

    /// 走 Metal candle 渲染（默认）/ 还是走 SwiftUI Canvas 自绘 overlay
    /// - candlestick / heikinAshi / renko 都是 OHLC candle 渲染 · 仅数据变换不同
    /// - 其他类型用 SwiftUI Canvas overlay 自绘 · 隐藏 Metal candle 层
    var usesCandleRenderer: Bool {
        switch self {
        case .candlestick, .heikinAshi, .renko: return true
        default: return false
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

// MARK: - v17.60 · A1.2/A1.5 算法参数（trader 可调 · UserDefaults 持久化）

/// Renko / P&F / Kagi 三种算法图表的参数（百分比基于 first close）
struct ChartTypeOptions: Codable, Equatable {
    /// Renko brickSize 百分比（默认 0.5%）
    var renkoBrickPercent: Double = 0.5
    /// P&F boxSize 百分比（默认 0.5%）
    var pnfBoxPercent: Double = 0.5
    /// P&F 反转 boxes 数（默认 3 · 经典）
    var pnfReversalBoxes: Int = 3
    /// Kagi 反转百分比（默认 1.0%）
    var kagiReversalPercent: Double = 1.0

    static let `default` = ChartTypeOptions()
}

enum ChartTypeOptionsStore {
    static let key = "chartType.options.v1"

    static func load(defaults: UserDefaults = .standard) -> ChartTypeOptions {
        guard let data = defaults.data(forKey: key),
              let opts = try? JSONDecoder().decode(ChartTypeOptions.self, from: data)
        else { return .default }
        return opts
    }

    static func save(_ opts: ChartTypeOptions, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(opts) {
            defaults.set(data, forKey: key)
        }
    }
}

#endif
