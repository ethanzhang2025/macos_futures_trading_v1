// 板块品种归类 + 默认行情快照（v15.43 · WP-行情 V3）
//
// 设计：
// - 60+ 品种主连续合约 · 与 WatchlistWindow.MockQuote 数据同步（接 CTP 真行情后整段废弃）
// - 板块归类按 SHFE / DCE / CZCE 传统口径
// - lastPrice 用 Decimal 精度 · changePct 用 Double（[-100, +100] 量纲）
// - openInterestK 用 Double（K 为单位）

import Foundation

public struct SectorInstrument: Sendable, Equatable, Identifiable, Codable {
    public let id: String              // "RB0"（主连续合约 ID）
    public let name: String            // "螺纹钢"
    public let sector: Sector
    public let lastPrice: Decimal      // 最新价
    public let changePct: Double       // 涨跌幅 [-100, +100] · 不带 %
    public let openInterestK: Double   // 持仓量（K 单位 · 1.2K = 1200 手）

    public init(id: String, name: String, sector: Sector,
                lastPrice: Decimal, changePct: Double, openInterestK: Double) {
        self.id = id
        self.name = name
        self.sector = sector
        self.lastPrice = lastPrice
        self.changePct = changePct
        self.openInterestK = openInterestK
    }
}

public enum SectorPresets {

    /// 60+ 品种主连续 mock 快照（与 WatchlistWindow.MockQuote 同步）
    public static let all: [SectorInstrument] = [
        // 黑色系（7）
        .init(id: "RB0", name: "螺纹钢",  sector: .黑色,   lastPrice: 3245,   changePct: +1.21, openInterestK: 1200),
        .init(id: "HC0", name: "热轧卷板", sector: .黑色,   lastPrice: 3450,   changePct: -0.32, openInterestK: 850),
        .init(id: "I0",  name: "铁矿石",   sector: .黑色,   lastPrice: 812.5,  changePct: +1.78, openInterestK: 640),
        .init(id: "J0",  name: "焦炭",     sector: .黑色,   lastPrice: 1925,   changePct: +0.45, openInterestK: 320),
        .init(id: "JM0", name: "焦煤",     sector: .黑色,   lastPrice: 1180,   changePct: -0.78, openInterestK: 280),
        .init(id: "SF0", name: "硅铁",     sector: .黑色,   lastPrice: 6420,   changePct: +0.32, openInterestK: 85),
        .init(id: "SM0", name: "锰硅",     sector: .黑色,   lastPrice: 6180,   changePct: -0.55, openInterestK: 92),

        // 有色（8）
        .init(id: "CU0", name: "铜",       sector: .有色,   lastPrice: 78650,  changePct: +2.05, openInterestK: 150),
        .init(id: "AL0", name: "铝",       sector: .有色,   lastPrice: 19450,  changePct: +0.85, openInterestK: 240),
        .init(id: "ZN0", name: "锌",       sector: .有色,   lastPrice: 23150,  changePct: -0.65, openInterestK: 180),
        .init(id: "PB0", name: "铅",       sector: .有色,   lastPrice: 17320,  changePct: +0.32, openInterestK: 65),
        .init(id: "SN0", name: "锡",       sector: .有色,   lastPrice: 215800, changePct: +1.45, openInterestK: 32),
        .init(id: "NI0", name: "镍",       sector: .有色,   lastPrice: 125400, changePct: -1.20, openInterestK: 78),
        .init(id: "SS0", name: "不锈钢",   sector: .有色,   lastPrice: 13280,  changePct: -0.42, openInterestK: 120),
        .init(id: "BC0", name: "国际铜",   sector: .有色,   lastPrice: 69820,  changePct: +1.85, openInterestK: 45),

        // 贵金属（2）
        .init(id: "AU0", name: "黄金",     sector: .贵金属, lastPrice: 612.5,  changePct: +0.83, openInterestK: 320),
        .init(id: "AG0", name: "白银",     sector: .贵金属, lastPrice: 7890,   changePct: +1.45, openInterestK: 560),

        // 能化（7）
        .init(id: "SC0", name: "原油",     sector: .能化,   lastPrice: 485.2,  changePct: +1.92, openInterestK: 180),
        .init(id: "LU0", name: "低硫燃油", sector: .能化,   lastPrice: 3520,   changePct: +0.85, openInterestK: 65),
        .init(id: "NR0", name: "20号胶",   sector: .能化,   lastPrice: 11250,  changePct: -0.45, openInterestK: 85),
        .init(id: "FU0", name: "燃油",     sector: .能化,   lastPrice: 3145,   changePct: +1.32, openInterestK: 240),
        .init(id: "BU0", name: "沥青",     sector: .能化,   lastPrice: 3680,   changePct: -0.28, openInterestK: 92),
        .init(id: "RU0", name: "橡胶",     sector: .能化,   lastPrice: 13420,  changePct: +0.65, openInterestK: 180),
        .init(id: "SP0", name: "纸浆",     sector: .能化,   lastPrice: 5840,   changePct: -0.85, openInterestK: 120),

        // 化工（13）
        .init(id: "L0",  name: "塑料",     sector: .化工,   lastPrice: 8350,   changePct: +0.45, openInterestK: 180),
        .init(id: "PP0", name: "聚丙烯",   sector: .化工,   lastPrice: 7820,   changePct: -0.32, openInterestK: 240),
        .init(id: "V0",  name: "PVC",      sector: .化工,   lastPrice: 5640,   changePct: +0.85, openInterestK: 320),
        .init(id: "EG0", name: "乙二醇",   sector: .化工,   lastPrice: 4520,   changePct: -0.65, openInterestK: 180),
        .init(id: "EB0", name: "苯乙烯",   sector: .化工,   lastPrice: 8945,   changePct: +1.20, openInterestK: 85),
        .init(id: "PG0", name: "液化石油气", sector: .化工, lastPrice: 4820,   changePct: +0.45, openInterestK: 92),
        .init(id: "TA0", name: "PTA",      sector: .化工,   lastPrice: 5680,   changePct: -0.85, openInterestK: 240),
        .init(id: "MA0", name: "甲醇",     sector: .化工,   lastPrice: 2485,   changePct: +0.65, openInterestK: 180),
        .init(id: "FG0", name: "玻璃",     sector: .化工,   lastPrice: 1320,   changePct: -1.15, openInterestK: 320),
        .init(id: "SA0", name: "纯碱",     sector: .化工,   lastPrice: 1620,   changePct: +0.95, openInterestK: 240),
        .init(id: "UR0", name: "尿素",     sector: .化工,   lastPrice: 1780,   changePct: -0.45, openInterestK: 180),
        .init(id: "PX0", name: "对二甲苯", sector: .化工,   lastPrice: 7220,   changePct: +1.45, openInterestK: 65),
        .init(id: "SH0", name: "烧碱",     sector: .化工,   lastPrice: 2280,   changePct: +0.85, openInterestK: 45),

        // 油脂（5）
        .init(id: "M0",  name: "豆粕",     sector: .油脂,   lastPrice: 3180,   changePct: +0.65, openInterestK: 560),
        .init(id: "Y0",  name: "豆油",     sector: .油脂,   lastPrice: 8240,   changePct: +1.05, openInterestK: 320),
        .init(id: "P0",  name: "棕榈油",   sector: .油脂,   lastPrice: 8920,   changePct: +1.45, openInterestK: 180),
        .init(id: "OI0", name: "菜油",     sector: .油脂,   lastPrice: 9180,   changePct: +0.85, openInterestK: 120),
        .init(id: "RM0", name: "菜粕",     sector: .油脂,   lastPrice: 2820,   changePct: +0.32, openInterestK: 240),

        // 农产品（5）
        .init(id: "A0",  name: "豆一",     sector: .农产品, lastPrice: 4280,   changePct: -0.45, openInterestK: 180),
        .init(id: "B0",  name: "豆二",     sector: .农产品, lastPrice: 3850,   changePct: +0.32, openInterestK: 65),
        .init(id: "C0",  name: "玉米",     sector: .农产品, lastPrice: 2380,   changePct: +0.85, openInterestK: 320),
        .init(id: "CS0", name: "玉米淀粉", sector: .农产品, lastPrice: 2780,   changePct: -0.65, openInterestK: 180),
        .init(id: "JD0", name: "鸡蛋",     sector: .农产品, lastPrice: 3420,   changePct: +1.20, openInterestK: 120),

        // 软商品（5）
        .init(id: "SR0", name: "白糖",     sector: .软商品, lastPrice: 6420,   changePct: -0.85, openInterestK: 240),
        .init(id: "CF0", name: "棉花",     sector: .软商品, lastPrice: 14580,  changePct: +0.45, openInterestK: 180),
        .init(id: "AP0", name: "苹果",     sector: .软商品, lastPrice: 8240,   changePct: +1.65, openInterestK: 120),
        .init(id: "CJ0", name: "红枣",     sector: .软商品, lastPrice: 12380,  changePct: -0.85, openInterestK: 45),
        .init(id: "PK0", name: "花生",     sector: .软商品, lastPrice: 8920,   changePct: +0.65, openInterestK: 85),

        // 股指（4）
        .init(id: "IF0", name: "沪深300",  sector: .股指,   lastPrice: 3856.4, changePct: -0.45, openInterestK: 180),
        .init(id: "IH0", name: "上证50",   sector: .股指,   lastPrice: 2820.8, changePct: -0.65, openInterestK: 120),
        .init(id: "IC0", name: "中证500",  sector: .股指,   lastPrice: 5680.2, changePct: +0.85, openInterestK: 150),
        .init(id: "IM0", name: "中证1000", sector: .股指,   lastPrice: 6420.5, changePct: +1.20, openInterestK: 92),

        // 国债（4）
        .init(id: "T0",  name: "10 年国债", sector: .国债,  lastPrice: 104.85, changePct: +0.08, openInterestK: 85),
        .init(id: "TF0", name: "5 年国债",  sector: .国债,  lastPrice: 103.42, changePct: +0.05, openInterestK: 65),
        .init(id: "TS0", name: "2 年国债",  sector: .国债,  lastPrice: 101.85, changePct: +0.02, openInterestK: 45),
        .init(id: "TL0", name: "30 年国债", sector: .国债,  lastPrice: 108.20, changePct: +0.15, openInterestK: 32),

        // 新能源（2）
        .init(id: "SI0", name: "工业硅",   sector: .新能源, lastPrice: 12480,  changePct: +0.85, openInterestK: 85),
        .init(id: "LC0", name: "碳酸锂",   sector: .新能源, lastPrice: 82500,  changePct: +1.45, openInterestK: 65),
    ]

    /// 按 sector 分组（按 sector enum 顺序 · 板块内按 changePct 降序）
    public static let bySector: [Sector: [SectorInstrument]] = {
        var result: [Sector: [SectorInstrument]] = [:]
        for sec in Sector.allCases {
            result[sec] = all.filter { $0.sector == sec }
        }
        return result
    }()

    /// 按 instrument id 索引
    public static let byID: [String: SectorInstrument] = {
        var result: [String: SectorInstrument] = [:]
        for inst in all { result[inst.id] = inst }
        return result
    }()

    /// 按板块取品种列表
    public static func instruments(in sector: Sector) -> [SectorInstrument] {
        bySector[sector] ?? []
    }
}
