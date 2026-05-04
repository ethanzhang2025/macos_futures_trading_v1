// WP-55 v15.19 batch38 · 工作区场景预设（trader 一键新建常用布局）
//
// 设计取舍：
// - 纯函数 · 不副作用 · 输入 ScenePreset → 返回 WorkspaceTemplate
// - 5 类场景：盯盘 / 复盘 / 训练 / 盘前 / 盘后
// - 默认合约 RB0（用户可后续编辑）· 默认 frame zero（UI 层重排布）
// - 与 WorkspaceTemplate.Kind 关联（盯盘/盘前=preMarket/inMarket · 复盘/盘后=postMarket · 训练=custom）

import Foundation

public enum WorkspaceScenePreset: String, Sendable, CaseIterable, Identifiable {
    case watching       // 盯盘
    case reviewing      // 复盘
    case training       // 训练
    case preTrade       // 盘前分析
    case postTrade      // 盘后总结

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .watching:  return "盯盘"
        case .reviewing: return "复盘"
        case .training:  return "训练"
        case .preTrade:  return "盘前分析"
        case .postTrade: return "盘后总结"
        }
    }

    public var helpText: String {
        switch self {
        case .watching:  return "主图 5m + 15m + 1h 三周期 · 盘中实时跟踪"
        case .reviewing: return "主图日线 + 周线 · 用于回顾近期波动"
        case .training: return "主图 K 线回放 · 模拟训练"
        case .preTrade:  return "自选合约扫盘 · 多合约小图对比"
        case .postTrade: return "复盘窗口 + 日志窗口 · 写交易笔记"
        }
    }

    public var kind: WorkspaceTemplate.Kind {
        switch self {
        case .watching:  return .inMarket
        case .reviewing: return .postMarket
        case .training:  return .custom
        case .preTrade:  return .preMarket
        case .postTrade: return .postMarket
        }
    }

    /// 默认窗口布局（frame=zero · UI 层根据屏幕大小重新分配）
    public func defaultWindows(instrumentID: String = "RB0") -> [WindowLayout] {
        switch self {
        case .watching:
            return [
                WindowLayout(instrumentID: instrumentID, period: .minute5,  zIndex: 2),
                WindowLayout(instrumentID: instrumentID, period: .minute15, zIndex: 1),
                WindowLayout(instrumentID: instrumentID, period: .hour1,    zIndex: 0)
            ]
        case .reviewing:
            return [
                WindowLayout(instrumentID: instrumentID, period: .daily,  zIndex: 1),
                WindowLayout(instrumentID: instrumentID, period: .weekly, zIndex: 0)
            ]
        case .training:
            return [
                WindowLayout(instrumentID: instrumentID, period: .minute15, zIndex: 0)
            ]
        case .preTrade:
            return [
                WindowLayout(instrumentID: instrumentID, period: .daily, zIndex: 1),
                WindowLayout(instrumentID: instrumentID, period: .hour1, zIndex: 0)
            ]
        case .postTrade:
            return [
                WindowLayout(instrumentID: instrumentID, period: .minute15, zIndex: 0)
            ]
        }
    }

    /// 生成 WorkspaceTemplate
    public func makeTemplate(name: String? = nil, instrumentID: String = "RB0",
                             now: Date = Date()) -> WorkspaceTemplate {
        WorkspaceTemplate(
            name: name ?? displayName,
            kind: kind,
            windows: defaultWindows(instrumentID: instrumentID),
            createdAt: now,
            updatedAt: now
        )
    }
}
