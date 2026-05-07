// SyncCore · 多端同步抽象层（WP-60 · M1-M6 预埋 · M7 启用）
//
// 决策依据：
//   - D2 §M7-M9：iPad 基础版 + CloudKit 多端自选同步
//   - D4 G1：方案 A 分级存储 — 非敏感走 CloudKit / 敏感走阿里云自建（Stage B）
//   - A12 §6：先同步低风险数据（自选/模板/UI 偏好）
//
// 模块定位：
//   厂商无关的同步抽象层（不绑定 CloudKit / 不绑定阿里云）
//   下游 backend 实现 SyncBackend 协议即可接入
//   业务模块（Watchlist / WorkspaceTemplate / Settings）通过 Adapter 接 SyncCore
//
// 禁做：
//   ❌ 不在本模块 import CloudKit / 阿里云 SDK（保持跨端可移植）
//   ❌ 不做复杂 CRDT（LWW 已能覆盖自选/模板的合并需求）
//   ❌ 不把敏感数据加密策略硬编码（由 backend 分级实现）

import Foundation

public enum SyncCoreModule {
    public static let version = "0.1.0-skeleton"
}
