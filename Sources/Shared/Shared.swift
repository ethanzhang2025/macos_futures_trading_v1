// Shared · 跨端共用的模型 / 协议 / 工具
// WP-24 占位骨架 · 后续 WP-30 归入 Legacy Sources/Shared/Models/*
// 职责：跨 Core 共用的值类型（KLine / Tick / Order / Trade / Position / Contract / Account）
// 禁做：不放任何 UI / 平台特有代码；所有类型必须是 Sendable

import Foundation

/// Shared 模块元信息
public enum SharedModule {
    /// 模块版本 · 遵循 semver，骨架期用 0.x
    public static let version = "0.1.0-skeleton"
}
