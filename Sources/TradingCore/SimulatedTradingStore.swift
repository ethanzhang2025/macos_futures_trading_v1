// WP-54 v15.6 · 模拟交易持久化（UserDefaults JSON · v1 简化）
//
// 不用 SQLite 的理由（v1 阶段）：
// - 数据量级（5000 trades + 5000 equity points + 100 orders + 10 positions）JSON 序列化 < 500KB · UserDefaults 完全可承受
// - 引入 SQLite store 需要 schema + migration · 工作量大
// - v2 数据撑爆 UserDefaults 时再升级到 SQLite · 接口不变（caller 走 SimulatedTradingStore 协议）
//
// 设计要点：
// - 完整 snapshot 替换写入 · 无 incremental 复杂度
// - defaults 参数注入测试隔离 suite（与 IndicatorParamsStore 同款）
// - load 失败 / 不存在 → nil（caller 决定 fallback default）

import Foundation

public enum SimulatedTradingStore {
    public static let key = "simulatedTrading.snapshot.v1"

    /// 从 UserDefaults 加载 · 失败/不存在返回 nil（caller 决定 fallback）
    /// defaults 参数允许测试注入隔离 suite · 默认 .standard
    public static func load(defaults: UserDefaults = .standard) -> SimulatedTradingSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SimulatedTradingSnapshot.self, from: data)
    }

    /// 写入 UserDefaults · 编码失败仅打印（持久化失败不影响主流程）
    /// defaults 参数允许测试注入隔离 suite · 默认 .standard
    public static func save(_ snapshot: SimulatedTradingSnapshot, defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key)
        } catch {
            print("⚠️ SimulatedTradingStore.save 编码失败：\(error)")
        }
    }

    /// 清除（重置账户用）
    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
