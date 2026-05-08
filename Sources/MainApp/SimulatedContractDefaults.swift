// MainApp · 模拟交易默认合约（v15.26 · 行情列表大补全）
//
// v1（v15.4）：4 主力 + 4 active 月份 hardcoded · 仅 8 合约
// v2（v15.26）：派生自 ChineseFuturesProducts.allContracts
//   · 60+ 品种 × (主连续 + 主力月份) ≈ 120 合约
//   · 单一 source of truth · 与 MarketDataPipeline / Watchlist 共享同一份品种规格
// v3（M5+）：换 CTP MdApi.ReqQryInstrument 拉真合约元数据 → ContractStore

import Foundation
import Shared
import DataCore

enum SimulatedContractDefaults {

    /// 派生自 ChineseFuturesProducts · 60+ 品种 × (主连续 + 主力月份) ≈ 120 合约
    static var list: [Contract] {
        ChineseFuturesProducts.allContracts
    }
}
