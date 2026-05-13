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
    /// CCI 周期（默认 14 · v15.11 WP-41 v4）
    public var cciPeriod: Int
    /// WR (Williams %R) 周期（默认 14 · v15.11 WP-41 v4 · 值域 -100~0）
    public var wrPeriod: Int
    /// DMI 周期（默认 14 · v15.13 · 输出 +DI/-DI 双线）
    public var dmiPeriod: Int
    /// Stochastic 参数（默认 [14, 3] · v15.13 · [period, smooth] · 输出 %K/%D 双线 · 视野 0~100）
    public var stochParams: [Int]
    /// ROC 周期（默认 12 · v15.13 · 单线 · 上下对称视野 · 0 参考线）
    public var rocPeriod: Int
    /// BIAS 周期（默认 6 · v15.13 · 单线 · 上下对称视野 · 0 参考线）
    public var biasPeriod: Int
    /// Aroon 周期（默认 14 · v15.18 · 输出 Up/Down/Osc 3 线 · 值域 -100~+100）
    public var aroonPeriod: Int
    /// STC 参数（默认 [23,50,10,10] · v15.18 · [fast,slow,period,smooth] · 单线 0-100）
    public var stcParams: [Int]
    /// ElderRay 周期（默认 13 · v15.18 · Bull/Bear 双线 · 0 参考）
    public var elderRayPeriod: Int
    /// Choppiness 周期（默认 14 · v15.18 · 单线 0-100 · 61.8/38.2 黄金分割阈值）
    public var choppinessPeriod: Int
    /// ForceIndex 周期（默认 13 · v15.18 · 单线 · 价量复合 · 0 参考）
    public var forceIndexPeriod: Int
    /// BBW 参数（默认 [20, 2] · v15.18+ batch13 · [period, stdDev] · 单线 · 0 基线 · % 单位）
    public var bbwParams: [Int]
    /// ATRP 周期（默认 14 · v15.18+ batch13 · 单线 · 0 基线 · % 单位）
    public var atrpPeriod: Int
    /// Swing High/Low lookback（默认 5 · v15.20 batch85 · 前后窗口大小 · 越大越稳）
    public var swingLookback: Int
    /// Swing 同向最小 bar 间距（默认 0 · v15.21 batch106 · >0 时密集合并保留更极值 · 减少视觉噪声）
    public var swingMinSpacing: Int
    /// TRIX 周期（默认 12 · v17.148 · 三重 EMA 趋势）
    public var trixPeriod: Int
    /// CMF 周期（默认 20 · v17.148 · 蔡金资金流）
    public var cmfPeriod: Int
    /// VR 周期（默认 26 · v17.148 · 成交量比）
    public var vrPeriod: Int
    /// ADX 周期（默认 14 · v17.148 · 平均趋向指数）
    public var adxPeriod: Int
    /// MFI 周期（默认 14 · v17.148 · 资金流量指数）
    public var mfiPeriod: Int
    /// CMO 周期（默认 14 · v17.148 · 钱德动量振荡器）
    public var cmoPeriod: Int

    public init(
        mainMAPeriods: [Int],
        mainBOLLParams: [Int],
        macdParams: [Int],
        kdjParams: [Int],
        rsiPeriod: Int,
        cciPeriod: Int = 14,
        wrPeriod: Int = 14,
        dmiPeriod: Int = 14,
        stochParams: [Int] = [14, 3],
        rocPeriod: Int = 12,
        biasPeriod: Int = 6,
        aroonPeriod: Int = 14,
        stcParams: [Int] = [23, 50, 10, 10],
        elderRayPeriod: Int = 13,
        choppinessPeriod: Int = 14,
        forceIndexPeriod: Int = 13,
        bbwParams: [Int] = [20, 2],
        atrpPeriod: Int = 14,
        swingLookback: Int = 5,
        swingMinSpacing: Int = 0,
        trixPeriod: Int = 12,
        cmfPeriod: Int = 20,
        vrPeriod: Int = 26,
        adxPeriod: Int = 14,
        mfiPeriod: Int = 14,
        cmoPeriod: Int = 14
    ) {
        self.mainMAPeriods = mainMAPeriods
        self.mainBOLLParams = mainBOLLParams
        self.macdParams = macdParams
        self.kdjParams = kdjParams
        self.rsiPeriod = rsiPeriod
        self.cciPeriod = cciPeriod
        self.wrPeriod = wrPeriod
        self.dmiPeriod = dmiPeriod
        self.stochParams = stochParams
        self.rocPeriod = rocPeriod
        self.biasPeriod = biasPeriod
        self.aroonPeriod = aroonPeriod
        self.stcParams = stcParams
        self.elderRayPeriod = elderRayPeriod
        self.choppinessPeriod = choppinessPeriod
        self.forceIndexPeriod = forceIndexPeriod
        self.bbwParams = bbwParams
        self.atrpPeriod = atrpPeriod
        self.swingLookback = swingLookback
        self.swingMinSpacing = swingMinSpacing
        self.trixPeriod = trixPeriod
        self.cmfPeriod = cmfPeriod
        self.vrPeriod = vrPeriod
        self.adxPeriod = adxPeriod
        self.mfiPeriod = mfiPeriod
        self.cmoPeriod = cmoPeriod
    }

    public static let `default` = IndicatorParamsBook(
        mainMAPeriods: [5, 20, 60],
        mainBOLLParams: [20, 2],
        macdParams: [12, 26, 9],
        kdjParams: [9, 3, 3],
        rsiPeriod: 14,
        cciPeriod: 14,
        wrPeriod: 14,
        dmiPeriod: 14,
        stochParams: [14, 3],
        rocPeriod: 12,
        biasPeriod: 6,
        aroonPeriod: 14,
        stcParams: [23, 50, 10, 10],
        elderRayPeriod: 13,
        choppinessPeriod: 14,
        forceIndexPeriod: 13,
        bbwParams: [20, 2],
        atrpPeriod: 14,
        swingLookback: 5,
        swingMinSpacing: 0,
        // v17.148 · 副图 6 个新指标 trader 标准默认
        trixPeriod: 12,
        cmfPeriod: 20,
        vrPeriod: 26,
        adxPeriod: 14,
        mfiPeriod: 14,
        cmoPeriod: 14
    )

    // MARK: - Codable · v15.11 加 cciPeriod/wrPeriod · v15.13 加 dmi/stoch/roc/bias 字段
    // decodeIfPresent fallback 默认值 · 让旧用户启动后无感升级 · 不丢已有偏好

    private enum CodingKeys: String, CodingKey {
        case mainMAPeriods, mainBOLLParams, macdParams, kdjParams, rsiPeriod
        case cciPeriod, wrPeriod
        case dmiPeriod, stochParams, rocPeriod, biasPeriod
        case aroonPeriod, stcParams, elderRayPeriod, choppinessPeriod, forceIndexPeriod
        case bbwParams, atrpPeriod
        case swingLookback, swingMinSpacing
        case trixPeriod, cmfPeriod, vrPeriod, adxPeriod, mfiPeriod, cmoPeriod   // v17.148
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mainMAPeriods  = try c.decode([Int].self, forKey: .mainMAPeriods)
        self.mainBOLLParams = try c.decode([Int].self, forKey: .mainBOLLParams)
        self.macdParams     = try c.decode([Int].self, forKey: .macdParams)
        self.kdjParams      = try c.decode([Int].self, forKey: .kdjParams)
        self.rsiPeriod      = try c.decode(Int.self,   forKey: .rsiPeriod)
        self.cciPeriod      = try c.decodeIfPresent(Int.self, forKey: .cciPeriod) ?? 14
        self.wrPeriod       = try c.decodeIfPresent(Int.self, forKey: .wrPeriod) ?? 14
        self.dmiPeriod      = try c.decodeIfPresent(Int.self, forKey: .dmiPeriod) ?? 14
        self.stochParams    = try c.decodeIfPresent([Int].self, forKey: .stochParams) ?? [14, 3]
        self.rocPeriod      = try c.decodeIfPresent(Int.self, forKey: .rocPeriod) ?? 12
        self.biasPeriod     = try c.decodeIfPresent(Int.self, forKey: .biasPeriod) ?? 6
        // v15.18 · 5 个新指标参数（旧用户启动 fallback 默认 · 不丢偏好）
        self.aroonPeriod      = try c.decodeIfPresent(Int.self, forKey: .aroonPeriod) ?? 14
        self.stcParams        = try c.decodeIfPresent([Int].self, forKey: .stcParams) ?? [23, 50, 10, 10]
        self.elderRayPeriod   = try c.decodeIfPresent(Int.self, forKey: .elderRayPeriod) ?? 13
        self.choppinessPeriod = try c.decodeIfPresent(Int.self, forKey: .choppinessPeriod) ?? 14
        self.forceIndexPeriod = try c.decodeIfPresent(Int.self, forKey: .forceIndexPeriod) ?? 13
        // v15.18+ batch13 · BBW / ATRP（旧用户启动 fallback 默认）
        self.bbwParams        = try c.decodeIfPresent([Int].self, forKey: .bbwParams) ?? [20, 2]
        self.atrpPeriod       = try c.decodeIfPresent(Int.self, forKey: .atrpPeriod) ?? 14
        // v15.20 batch85 · Swing lookback（旧用户启动 fallback 5）
        self.swingLookback    = try c.decodeIfPresent(Int.self, forKey: .swingLookback) ?? 5
        // v15.21 batch106 · Swing 同向最小间距（旧用户启动 fallback 0 不过滤）
        self.swingMinSpacing  = try c.decodeIfPresent(Int.self, forKey: .swingMinSpacing) ?? 0
        // v17.148 · 副图 6 个新指标 period（旧用户启动 fallback trader 标准默认）
        self.trixPeriod       = try c.decodeIfPresent(Int.self, forKey: .trixPeriod) ?? 12
        self.cmfPeriod        = try c.decodeIfPresent(Int.self, forKey: .cmfPeriod) ?? 20
        self.vrPeriod         = try c.decodeIfPresent(Int.self, forKey: .vrPeriod) ?? 26
        self.adxPeriod        = try c.decodeIfPresent(Int.self, forKey: .adxPeriod) ?? 14
        self.mfiPeriod        = try c.decodeIfPresent(Int.self, forKey: .mfiPeriod) ?? 14
        self.cmoPeriod        = try c.decodeIfPresent(Int.self, forKey: .cmoPeriod) ?? 14
    }

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

    public var cciParamsDecimal: [Decimal] {
        [Decimal(cciPeriod)]
    }

    public var wrParamsDecimal: [Decimal] {
        [Decimal(wrPeriod)]
    }

    public var dmiParamsDecimal: [Decimal] {
        [Decimal(dmiPeriod)]
    }

    public var stochParamsDecimal: [Decimal] {
        stochParams.map { Decimal($0) }
    }

    public var rocParamsDecimal: [Decimal] {
        [Decimal(rocPeriod)]
    }

    public var biasParamsDecimal: [Decimal] {
        [Decimal(biasPeriod)]
    }

    // v15.18 · 5 个新指标 Decimal helper

    public var aroonParamsDecimal: [Decimal] {
        [Decimal(aroonPeriod)]
    }

    public var stcParamsDecimal: [Decimal] {
        stcParams.map { Decimal($0) }
    }

    public var elderRayParamsDecimal: [Decimal] {
        [Decimal(elderRayPeriod)]
    }

    public var choppinessParamsDecimal: [Decimal] {
        [Decimal(choppinessPeriod)]
    }

    public var forceIndexParamsDecimal: [Decimal] {
        [Decimal(forceIndexPeriod)]
    }

    // v15.18+ batch13 · BBW / ATRP Decimal helper

    public var bbwParamsDecimal: [Decimal] {
        bbwParams.map { Decimal($0) }
    }

    public var atrpParamsDecimal: [Decimal] {
        [Decimal(atrpPeriod)]
    }

    // v17.148 · 副图 6 个新指标 Decimal helper

    public var trixParamsDecimal: [Decimal] { [Decimal(trixPeriod)] }
    public var cmfParamsDecimal: [Decimal]  { [Decimal(cmfPeriod)] }
    public var vrParamsDecimal: [Decimal]   { [Decimal(vrPeriod)] }
    public var adxParamsDecimal: [Decimal]  { [Decimal(adxPeriod)] }
    public var mfiParamsDecimal: [Decimal]  { [Decimal(mfiPeriod)] }
    public var cmoParamsDecimal: [Decimal]  { [Decimal(cmoPeriod)] }
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

// MARK: - 副图独立参数 overrides（v15.7 · 按副图槽位 0~3 独立调参）

/// 副图独立参数 overrides 持久化（key = "indicators.subOverrides.v1"）
/// 数据形态：`[Int: IndicatorParamsBook]` · int = 副图槽位 0~3 · 不存在 = 用全局 IndicatorParamsBook 默认
/// 使用场景：用户同时开两个 RSI 副图 · 一个 RSI(14) 一个 RSI(7) 对比
public enum SubChartParamsOverridesStore {
    public static let key = "indicators.subOverrides.v1"

    public static func load(defaults: UserDefaults = .standard) -> [Int: IndicatorParamsBook]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // JSON 不支持 Int 作 dict key · 用 [String: IndicatorParamsBook] 中转
        guard let stringDict = try? JSONDecoder().decode([String: IndicatorParamsBook].self, from: data)
        else { return nil }
        var result: [Int: IndicatorParamsBook] = [:]
        for (k, v) in stringDict {
            if let i = Int(k) { result[i] = v }
        }
        return result
    }

    public static func save(_ overrides: [Int: IndicatorParamsBook], defaults: UserDefaults = .standard) {
        let stringDict = Dictionary(uniqueKeysWithValues: overrides.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(stringDict) else { return }
        defaults.set(data, forKey: key)
    }
}
