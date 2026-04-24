// JournalCore · 交易日志 + 复盘分析
// WP-24 占位骨架 · 后续 WP-50（复盘 8 图）+ WP-53（交易日志）填充
// 职责：交割单 CSV 导入、交易日志（原因/情绪/偏差/教训）、复盘 8 图数据聚合
// 禁做：不把原始交割单直接当业务模型（必须走 Trade 标准模型）；不让日志编辑反向污染成交
// 敏感数据：日志内容必须走 SQLCipher 加密存储

import Foundation
import Shared
import DataCore

public enum JournalCoreModule {
    public static let version = "0.1.0-skeleton"
}
