// ReplayCore · K 线回放（沉浸式复盘）
// WP-24 占位骨架 · 后续 WP-51 填充
// 职责：历史日期 + 品种选择、回放控制（播放/暂停/2x-8x/倒退/单步）、成交点叠加
// 依赖：DataCore 的统一 DataSource 协议（历史 + 实时通用）

import Foundation
import Shared
import DataCore

public enum ReplayCoreModule {
    public static let version = "0.1.0-skeleton"
}
