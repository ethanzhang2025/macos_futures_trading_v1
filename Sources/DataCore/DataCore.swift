// DataCore · Tick / K 线 / 合约 / 数据源协议
// WP-24 占位骨架 · 后续 WP-30 归入 Legacy Sources/MarketData/* + Sources/ContractManager/*
// 职责：行情数据的接入 / 聚合 / 缓存 / 数据源抽象（CTP/SimNow/历史回放统一协议）
// 禁做：不处理渲染；不把历史与实时拆两套 UI 逻辑

import Foundation
import Shared

public enum DataCoreModule {
    public static let version = "0.1.0-skeleton"
}
