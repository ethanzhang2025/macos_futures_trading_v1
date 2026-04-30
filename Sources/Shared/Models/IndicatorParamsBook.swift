// MainApp · 自定义指标参数 v15.x
// 主图 MA 3 条周期 / BOLL 双参 / 副图 MACD/KDJ/RSI 参数 · 全部用户可调 · UserDefaults 跨合约共享
//
// 设计要点（Karpathy "避免过度复杂"）：
// - 条数固定（3 条 MA · 不让用户加减）· 用户只改默认值
// - 全局共享 · 不按 (instrumentID, period) 隔离 · 用户期望"我的 MA 喜好跨合约一致"
// - Codable JSON 持久化 UserDefaults · v1 单独 key · 旧版本启动 fallback default
// - 守卫模式：isParamsLoaded 标记位 · 与 v15.0 状态持久化矩阵风格一致

import Foundation

/// 自定义指标参数本（全局 · 跨合约共享）
public struct IndicatorParamsBook: Sendable, Codable, Equatable {
    /// 主图 3 条 MA 周期（默认 [5, 20, 60]）· 顺序 = MA1/MA2/MA3 渲染顺序
    public var mainMAPeriods: [Int]
    /// 主图 BOLL 参数（默认 [20, 2]）· [period, stdDevMultiple]
    public var mainBOLLParams: [Int]
    /// MACD 参数（默认 [12, 26, 9]）· [fast, slow, signal]
    public var macdParams: [Int]
    /// KDJ 参数（默认 [9, 3, 3]）· [period, smoothK, smoothD]
    public var kdjParams: [Int]
    /// RSI 周期（默认 14）
    public var rsiPeriod: Int

    public init(
        mainMAPeriods: [Int],
        mainBOLLParams: [Int],
        macdParams: [Int],
        kdjParams: [Int],
        rsiPeriod: Int
    ) {
        self.mainMAPeriods = mainMAPeriods
        self.mainBOLLParams = mainBOLLParams
        self.macdParams = macdParams
        self.kdjParams = kdjParams
        self.rsiPeriod = rsiPeriod
    }

    public static let `default` = IndicatorParamsBook(
        mainMAPeriods: [5, 20, 60],
        mainBOLLParams: [20, 2],
        macdParams: [12, 26, 9],
        kdjParams: [9, 3, 3],
        rsiPeriod: 14
    )

    // MARK: - Decimal 转换 helper（IndicatorCore.calculate 接受 [Decimal]）

    public var mainMAPeriodsDecimal: [[Decimal]] {
        mainMAPeriods.map { [Decimal($0)] }
    }

    public var mainBOLLParamsDecimal: [Decimal] {
        mainBOLLParams.map { Decimal($0) }
    }

    public var macdParamsDecimal: [Decimal] {
        macdParams.map { Decimal($0) }
    }

    public var kdjParamsDecimal: [Decimal] {
        kdjParams.map { Decimal($0) }
    }

    public var rsiParamsDecimal: [Decimal] {
        [Decimal(rsiPeriod)]
    }
}

// MARK: - UserDefaults 加载/保存

public enum IndicatorParamsStore {
    public static let key = "indicators.params.v1"

    /// 从 UserDefaults 加载 · 失败/不存在返回 nil（caller 决定 fallback default）
    /// defaults 参数允许测试注入隔离 suite · 默认 .standard
    public static func load(defaults: UserDefaults = .standard) -> IndicatorParamsBook? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IndicatorParamsBook.self, from: data)
    }

    /// 写入 UserDefaults · 失败静默（持久化层失败不影响功能）
    /// defaults 参数允许测试注入隔离 suite · 默认 .standard
    public static func save(_ book: IndicatorParamsBook, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }
}
