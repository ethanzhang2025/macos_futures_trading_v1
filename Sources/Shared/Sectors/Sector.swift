// 板块定义（v15.43 · WP-行情 V3 板块联动 · trader 经常按板块看盘）
//
// 国内期货传统板块归类（基于 SHFE / DCE / CZCE / CFFEX / INE 交易所传统聚类）
// 命名用中文 rawValue 是因为 trader 看盘用中文 · UI 直接绑

import Foundation

public enum Sector: String, CaseIterable, Sendable, Codable, Identifiable {
    case 黑色   = "黑色系"   // 螺纹/热卷/铁矿/焦炭/焦煤/锰硅/硅铁
    case 有色   = "有色"     // 铜/铝/锌/铅/锡/镍/不锈钢/国际铜
    case 贵金属 = "贵金属"   // 黄金/白银
    case 能化   = "能化"     // 原油/燃油/沥青/橡胶/纸浆等
    case 化工   = "化工"     // 塑料/PP/PVC/EG/EB/PG/TA/MA/玻璃等
    case 油脂   = "油脂"     // 豆粕/豆油/棕榈/菜油/菜粕
    case 农产品 = "农产品"   // 豆一/豆二/玉米/淀粉/鸡蛋
    case 软商品 = "软商品"   // 白糖/棉花/苹果/红枣/花生
    case 股指   = "股指"     // IF/IH/IC/IM
    case 国债   = "国债"     // T/TF/TS/TL
    case 新能源 = "新能源"   // 工业硅/碳酸锂

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    /// 板块图标（SF Symbols · 视觉标识）
    public var icon: String {
        switch self {
        case .黑色:   return "square.stack.3d.down.right"
        case .有色:   return "circle.hexagongrid.fill"
        case .贵金属: return "sparkles"
        case .能化:   return "drop.fill"
        case .化工:   return "atom"
        case .油脂:   return "leaf.fill"
        case .农产品: return "carrot.fill"
        case .软商品: return "ladybug.fill"
        case .股指:   return "chart.line.uptrend.xyaxis"
        case .国债:   return "banknote.fill"
        case .新能源: return "bolt.fill"
        }
    }
}
