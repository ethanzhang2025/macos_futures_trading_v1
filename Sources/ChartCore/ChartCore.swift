// ChartCore · Metal 图表渲染管线
// WP-24 占位骨架 · 后续 WP-40 填充 Metal 渲染 / 交互 / 多窗口布局
// 职责：60fps Metal 自研图表引擎 + SwiftUI/AppKit 交互桥接 + session-aware 时间轴
// 禁做：不在渲染线程算指标（靠 IndicatorCore）；不用 WebView 兜底；不混写 Shader 与 UI 状态
// 性能红线：10w K 线 60fps / 冷启动 <1s / 交互 <100ms / Tick <1ms / 内存 <500MB

import Foundation
import Shared
import DataCore
import IndicatorCore

public enum ChartCoreModule {
    public static let version = "0.1.0-skeleton"
}
