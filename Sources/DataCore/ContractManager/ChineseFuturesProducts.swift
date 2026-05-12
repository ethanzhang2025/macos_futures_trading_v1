// 中国期货市场品种规格库（v15.26 · 行情列表大补全 · WP-行情库 batch1）
//
// 设计：单一 source of truth · 替代以往 hardcoded 8 合约（rb/i/au/IF/cu）
// 范围：6 大交易所 60+ 主流品种 · 覆盖 ~95% 真实市场流动性
// 字段值：multiplier / 保证金率 / priceTick 取自 2025-2026 真实交易所规则（近似值）
//
// 下游消费：
//   - SimulatedContractDefaults.list ← 派生主连续 + 主力月份合约
//   - MarketDataPipeline.supportedContracts ← 派生支持合约清单
//   - MockWatchlistBook.generate ← 派生 8 大类目分组（金属/黑色/化工/油脂/农产品/股指/国债/贵金属/能化）
//   - WatchlistWindow 搜索 ← byCategory / byExchange 索引
//
// 真实市场对接（M5+）：本表换成 CTP MdApi.ReqQryInstrument 拉真合约 ✓ 框架预留 ProductSpecLoader

import Foundation
import Shared

public enum ChineseFuturesProducts {

    // MARK: - 类目（用户视角分类 · 与交易所正交）

    public enum Category: String, CaseIterable, Sendable {
        case 黑色   = "黑色"     // rb hc i j jm sf sm
        case 有色   = "有色"     // cu al zn pb sn ni bc
        case 贵金属 = "贵金属"   // au ag
        case 农产品 = "农产品"   // a b m c cs jd
        case 油脂   = "油脂"     // y p oi rm
        case 化工   = "化工"     // l pp v eg eb pg ta ma fg sa ur px
        case 能化   = "能化"     // sc lu nr fu bu ru sp
        case 软商品 = "软商品"   // sr cf ap cj pk
        case 股指   = "股指"     // IF IH IC IM
        case 国债   = "国债"     // T TF TS TL
        case 新能源 = "新能源"   // si lc
    }

    // MARK: - 单品种全量信息（spec + category）

    public struct CategorizedSpec: Sendable {
        public let spec: ProductSpec
        public let category: Category
        public let isFinancial: Bool   // 金融期货（股指/国债）· 不跳近月

        public var productID: String { spec.productID }
        public var name: String       { spec.name }
        public var exchange: Exchange { Exchange(rawValue: spec.exchange) ?? .SHFE }
    }

    // MARK: - 全量品种规格（hardcoded · 60+ 品种）

    /// 注意：marginRatio 是单边保证金率（CFTC/中国习惯不同 · 这里用中国习惯：单边）
    /// priceTick 单位：元（如 "1" = 1 元/吨 · "0.5" = 0.5 元/克）
    /// pinyin = 拼音首字母（用于搜索）
    public static let all: [CategorizedSpec] = [
        // ───── SHFE 上期所（15 品种） ─────
        spec("rb", "螺纹钢", "LWG", .SHFE,  10,  "1",   "0.07", "吨",  "21:00-23:00", .黑色),
        spec("hc", "热卷",   "RJ",  .SHFE,  10,  "1",   "0.07", "吨",  "21:00-23:00", .黑色),
        spec("cu", "沪铜",   "HT",  .SHFE,   5,  "10",  "0.10", "吨",  "21:00-01:00", .有色),
        spec("al", "沪铝",   "HL",  .SHFE,   5,  "5",   "0.08", "吨",  "21:00-01:00", .有色),
        spec("zn", "沪锌",   "HX",  .SHFE,   5,  "5",   "0.10", "吨",  "21:00-01:00", .有色),
        spec("pb", "沪铅",   "HQ",  .SHFE,   5,  "5",   "0.08", "吨",  "21:00-23:00", .有色),
        spec("sn", "沪锡",   "HX2", .SHFE,   1,  "10",  "0.10", "吨",  "21:00-01:00", .有色),
        spec("ni", "沪镍",   "HN",  .SHFE,   1,  "10",  "0.12", "吨",  "21:00-01:00", .有色),
        spec("au", "黄金",   "HJ",  .SHFE, 1000, "0.02","0.08", "克",  "21:00-02:30", .贵金属),
        spec("ag", "白银",   "BY",  .SHFE,  15,  "1",   "0.12", "千克","21:00-02:30", .贵金属),
        spec("fu", "燃料油", "RLY", .SHFE,  10,  "1",   "0.12", "吨",  "21:00-23:00", .能化),
        spec("bu", "沥青",   "LQ",  .SHFE,  10,  "2",   "0.10", "吨",  "21:00-23:00", .能化),
        spec("ru", "天然橡胶","TRJ",.SHFE,  10,  "5",   "0.10", "吨",  "21:00-23:00", .能化),
        spec("sp", "纸浆",   "ZJ",  .SHFE,  10,  "2",   "0.07", "吨",  "21:00-23:00", .能化),
        spec("ss", "不锈钢", "BXG", .SHFE,   5,  "5",   "0.08", "吨",  "21:00-01:00", .有色),

        // ───── INE 能源中心（4 品种） ─────
        spec("sc", "原油",     "YY", .INE, 1000, "0.1", "0.10", "桶",  "21:00-02:30", .能化),
        spec("lu", "低硫燃油", "DLY",.INE,   10, "1",   "0.12", "吨",  "21:00-23:00", .能化),
        spec("nr", "20号胶",   "EHJ",.INE,   10, "5",   "0.10", "吨",  "21:00-23:00", .能化),
        spec("bc", "国际铜",   "GJT",.INE,    5, "10",  "0.10", "吨",  "21:00-01:00", .有色),

        // ───── DCE 大商所（17 品种） ─────
        spec("a",  "黄大豆1号","HD1", .DCE, 10,  "1",   "0.08", "吨", "21:00-23:00", .农产品),
        spec("b",  "黄大豆2号","HD2", .DCE, 10,  "1",   "0.08", "吨", "21:00-23:00", .农产品),
        spec("m",  "豆粕",     "DP",  .DCE, 10,  "1",   "0.07", "吨", "21:00-23:00", .油脂),
        spec("y",  "豆油",     "DY",  .DCE, 10,  "2",   "0.07", "吨", "21:00-23:00", .油脂),
        spec("p",  "棕榈油",   "ZLY", .DCE, 10,  "2",   "0.08", "吨", "21:00-23:00", .油脂),
        spec("c",  "玉米",     "YM",  .DCE, 10,  "1",   "0.07", "吨", "21:00-23:00", .农产品),
        spec("cs", "玉米淀粉", "YMD", .DCE, 10,  "1",   "0.06", "吨", "21:00-23:00", .农产品),
        spec("i",  "铁矿石",   "TKS", .DCE, 100, "0.5", "0.13", "吨", "21:00-23:00", .黑色),
        spec("jm", "焦煤",     "JM",  .DCE,  60, "0.5", "0.15", "吨", "21:00-23:00", .黑色),
        spec("j",  "焦炭",     "JT",  .DCE, 100, "0.5", "0.15", "吨", "21:00-23:00", .黑色),
        spec("l",  "聚乙烯",   "JYX", .DCE,   5, "1",   "0.07", "吨", "21:00-23:00", .化工),
        spec("pp", "聚丙烯",   "JBX", .DCE,   5, "1",   "0.07", "吨", "21:00-23:00", .化工),
        spec("v",  "PVC",      "PVC", .DCE,   5, "1",   "0.07", "吨", "21:00-23:00", .化工),
        spec("eg", "乙二醇",   "YEC", .DCE,  10, "1",   "0.08", "吨", "21:00-23:00", .化工),
        spec("eb", "苯乙烯",   "BYX", .DCE,   5, "1",   "0.10", "吨", "21:00-23:00", .化工),
        spec("pg", "液化气",   "YHQ", .DCE,  20, "1",   "0.12", "吨", "21:00-23:00", .化工),
        spec("jd", "鸡蛋",     "JD",  .DCE,   5, "1",   "0.09", "500千克","",        .农产品),

        // ───── CZCE 郑商所（17 品种） ─────
        spec("SR", "白糖",     "BT",  .CZCE, 10,  "1",   "0.07", "吨",  "21:00-23:00", .软商品),
        spec("CF", "棉花",     "MH",  .CZCE,  5,  "5",   "0.07", "吨",  "21:00-23:00", .软商品),
        spec("TA", "PTA",      "PTA", .CZCE,  5,  "2",   "0.07", "吨",  "21:00-23:00", .化工),
        spec("FG", "玻璃",     "BL",  .CZCE, 20,  "1",   "0.09", "吨",  "21:00-23:00", .化工),
        spec("MA", "甲醇",     "JC",  .CZCE, 10,  "1",   "0.08", "吨",  "21:00-23:00", .化工),
        spec("RM", "菜籽粕",   "CZP", .CZCE, 10,  "1",   "0.09", "吨",  "21:00-23:00", .油脂),
        spec("OI", "菜籽油",   "CZY", .CZCE, 10,  "2",   "0.07", "吨",  "21:00-23:00", .油脂),
        spec("AP", "苹果",     "PG",  .CZCE, 10,  "1",   "0.12", "吨",  "",            .软商品),
        spec("CJ", "红枣",     "HZ",  .CZCE,  5,  "5",   "0.12", "吨",  "",            .软商品),
        spec("PK", "花生",     "HS",  .CZCE,  5,  "2",   "0.08", "吨",  "21:00-23:00", .软商品),
        spec("SA", "纯碱",     "CJ2", .CZCE, 20,  "1",   "0.10", "吨",  "21:00-23:00", .化工),
        spec("SF", "硅铁",     "GT",  .CZCE,  5,  "2",   "0.12", "吨",  "21:00-23:00", .黑色),
        spec("SM", "锰硅",     "MG",  .CZCE,  5,  "2",   "0.12", "吨",  "21:00-23:00", .黑色),
        spec("UR", "尿素",     "NS",  .CZCE, 20,  "1",   "0.07", "吨",  "21:00-23:00", .化工),
        spec("PX", "对二甲苯", "DEJB",.CZCE,  5,  "2",   "0.09", "吨",  "21:00-23:00", .化工),
        spec("SH", "烧碱",     "SJ",  .CZCE, 30,  "1",   "0.09", "吨",  "21:00-23:00", .化工),
        spec("PR", "瓶片",     "PP2", .CZCE, 15,  "2",   "0.07", "吨",  "21:00-23:00", .化工),

        // ───── CFFEX 中金所（8 品种 · 不跳近月 · 无夜盘） ─────
        financialSpec("IF", "沪深300",  "HS3", .CFFEX, 300,   "0.2",  "0.12", "点", .股指),
        financialSpec("IH", "上证50",   "SZ5", .CFFEX, 300,   "0.2",  "0.12", "点", .股指),
        financialSpec("IC", "中证500",  "ZZ5", .CFFEX, 200,   "0.2",  "0.14", "点", .股指),
        financialSpec("IM", "中证1000", "ZZ1K",.CFFEX, 200,   "0.2",  "0.15", "点", .股指),
        financialSpec("TS", "2年国债",  "ENG", .CFFEX, 20000, "0.005","0.005","元", .国债),
        financialSpec("TF", "5年国债",  "WNG", .CFFEX, 10000, "0.005","0.012","元", .国债),
        financialSpec("T",  "10年国债", "SNG", .CFFEX, 10000, "0.005","0.020","元", .国债),
        financialSpec("TL", "30年国债", "SSG", .CFFEX, 10000, "0.01", "0.035","元", .国债),

        // ───── GFEX 广期所（2 品种 · 新能源） ─────
        spec("si", "工业硅",   "GYG", .GFEX,  5,  "5",   "0.09", "吨",  "21:00-23:00", .新能源),
        spec("lc", "碳酸锂",   "TSL", .GFEX,  1,  "50",  "0.09", "吨",  "21:00-23:00", .新能源),
    ]

    // MARK: - 索引（O(1) 查询）

    /// productID（保留原大小写） → CategorizedSpec
    public static let byProductID: [String: CategorizedSpec] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.spec.productID, $0) })
    }()

    /// Category → 该类下所有品种 specs
    public static let byCategory: [Category: [CategorizedSpec]] = {
        Dictionary(grouping: all, by: { $0.category })
    }()

    /// Exchange → 该所所有品种 specs
    public static let byExchange: [Exchange: [CategorizedSpec]] = {
        Dictionary(grouping: all, by: { $0.exchange })
    }()

    /// productID 大小写无关 → CategorizedSpec（"RB" → rb spec / "if" → IF spec）
    /// hardcoded 表中 SHFE/DCE/INE/GFEX 用小写 · CZCE/CFFEX 用大写 · 调用方传 "RB0" 等大写主连续 ID 时需要回退
    public static let byProductIDCaseInsensitive: [String: CategorizedSpec] = {
        var map: [String: CategorizedSpec] = [:]
        for entry in all {
            map[entry.spec.productID.lowercased()] = entry
        }
        return map
    }()

    // MARK: - 价格精度（v17.98 · PricePrecisionMode.auto fallback）

    /// 从 instrumentID 反推合约价格小数位数（auto 模式下使用）
    /// - 算法：去除尾部数字得 productID prefix · 大小写无关查 byProductIDCaseInsensitive · 解析 priceTick 字符串小数位
    /// - 例："RB0" → "rb" → priceTick "1" → 0 位；"AU0" → "au" → "0.02" → 2 位；"IF0" → "IF" → "0.2" → 1 位
    /// - 找不到品种返 nil（调用方 fallback 默认 2）
    public static func priceTickDigits(forInstrumentID id: String) -> Int? {
        // 取首段非数字（trim 尾部所有 ASCII 数字）· "RB0" → "RB" · "rb2509" → "rb"
        let prefix = id.prefix { !$0.isASCII || !$0.isNumber }
        guard !prefix.isEmpty,
              let entry = byProductIDCaseInsensitive[prefix.lowercased()] else { return nil }
        let s = entry.spec.priceTick
        if let dot = s.firstIndex(of: ".") {
            return s.distance(from: s.index(after: dot), to: s.endIndex)
        }
        return 0
    }

    // MARK: - 派生：合约清单（主连续 + 主力月份）

    /// 全部品种主连续合约 ID（如 "RB0" / "IF0" / "AU0"）· 大写
    public static var allMainContinuousIDs: [String] {
        all.map { $0.productID.uppercased() + "0" }
    }

    /// 全部品种主力月份合约 ID（DominantMonthCalculator 派生 · 半年自动续期）
    /// 未在 DominantMonthCalculator 规则表的品种返 nil 自动跳过
    public static var allDominantMonthIDs: [String] {
        all.compactMap { entry in
            DominantMonthCalculator.dominantContract(prefix: entry.productID)
        }
    }

    /// 全部支持合约 ID（主连续 + 主力月份 · 去重 · MarketDataPipeline 直接消费）
    public static var allSupportedInstrumentIDs: [String] {
        Array(Set(allMainContinuousIDs + allDominantMonthIDs)).sorted()
    }

    /// 派生 Contract 列表（主连续 + 主力月份 · SimulatedContractDefaults 直接消费）
    public static var allContracts: [Contract] {
        var result: [Contract] = []
        for entry in all {
            // 主连续
            result.append(makeContract(entry: entry, suffix: "0", monthInt: 0))
            // 主力月份（动态派生）
            if let dominantID = DominantMonthCalculator.dominantContract(prefix: entry.productID) {
                let monthDigits = String(dominantID.suffix(2))
                let month = Int(monthDigits) ?? 0
                result.append(makeContract(entry: entry,
                                           suffix: String(dominantID.dropFirst(entry.productID.count)),
                                           monthInt: month))
            }
        }
        return result
    }

    // MARK: - private helpers

    private static func spec(
        _ productID: String, _ name: String, _ pinyin: String,
        _ exchange: Exchange, _ multiple: Int,
        _ priceTick: String, _ marginRatio: String,
        _ unit: String, _ nightSession: String,
        _ category: Category
    ) -> CategorizedSpec {
        CategorizedSpec(
            spec: ProductSpec(
                exchange: exchange.rawValue,
                productID: productID,
                name: name,
                pinyin: pinyin,
                multiple: multiple,
                priceTick: priceTick,
                marginRatio: marginRatio,
                unit: unit,
                nightSession: nightSession
            ),
            category: category,
            isFinancial: false
        )
    }

    private static func financialSpec(
        _ productID: String, _ name: String, _ pinyin: String,
        _ exchange: Exchange, _ multiple: Int,
        _ priceTick: String, _ marginRatio: String,
        _ unit: String,
        _ category: Category
    ) -> CategorizedSpec {
        CategorizedSpec(
            spec: ProductSpec(
                exchange: exchange.rawValue,
                productID: productID,
                name: name,
                pinyin: pinyin,
                multiple: multiple,
                priceTick: priceTick,
                marginRatio: marginRatio,
                unit: unit,
                nightSession: ""
            ),
            category: category,
            isFinancial: true
        )
    }

    private static func makeContract(entry: CategorizedSpec, suffix: String, monthInt: Int) -> Contract {
        let isMain = (suffix == "0")
        let id: String
        if isMain {
            id = entry.productID.uppercased() + "0"
        } else {
            id = entry.productID + suffix
        }
        let displayName = isMain
            ? entry.name + "连续"
            : entry.name + suffix
        // 字面量保证可解析（编码错为 fatal）
        guard let priceTick = Decimal(string: entry.spec.priceTick),
              let margin = Decimal(string: entry.spec.marginRatio) else {
            fatalError("ChineseFuturesProducts · 非法 priceTick/marginRatio 字面量：\(entry.productID)")
        }
        return Contract(
            instrumentID: id,
            instrumentName: displayName,
            exchange: entry.exchange,
            productID: entry.productID,
            volumeMultiple: entry.spec.multiple,
            priceTick: priceTick,
            deliveryMonth: monthInt,
            expireDate: "",
            longMarginRatio: margin,
            shortMarginRatio: margin,
            isTrading: true,
            productName: entry.name,
            pinyinInitials: entry.spec.pinyin
        )
    }
}
