// 经典套利对预设（v15.27 · WP-套利分析 V1）
//
// 12 经典对 · 覆盖 4 大类目：
//   - 跨品种黑色 · 螺纹热卷 / 焦煤焦炭
//   - 跨品种油脂 · 豆粕豆油 / 棕榈豆油 / 菜油豆油
//   - 跨品种贵金属 · 金银比
//   - 跨品种有色 · 铜铝比
//   - 跨指数 · 沪深300-上证50 / 中证500-沪深300 / 中证1000-中证500
//   - 跨期限国债 · 10年-5年 / 10年-2年 / 30年-10年
//
// 月间套利推 V2（需要动态主力月规则匹配 · 跨年自动续期）

import Foundation

public enum SpreadPresets {

    /// 12 经典价差对（用主连续 X0 简化 · 真行情接入后可切动态主力月）
    public static let all: [SpreadPair] = [
        // ─── 跨品种 · 黑色 ───
        SpreadPair(
            id: "rb-hc", name: "螺纹热卷",
            category: .跨品种,
            leg1: SpreadLeg(instrumentID: "RB0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "HC0", ratio: -1),
            unitLabel: "元/吨",
            description: "钢材消费结构 · 建材（螺纹）vs 板材（热卷）· 偏弱缩价差"
        ),
        SpreadPair(
            id: "j-jm", name: "焦化利润",
            category: .产业链,
            leg1: SpreadLeg(instrumentID: "J0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "JM0", ratio: -1),
            unitLabel: "元/吨",
            description: "焦炭-焦煤 · 焦化厂利润 · 长趋势 + 短期回归"
        ),

        // ─── 跨品种 · 油脂 ───
        SpreadPair(
            id: "y-m", name: "豆油-豆粕",
            category: .产业链,
            leg1: SpreadLeg(instrumentID: "Y0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "M0", ratio: -1),
            unitLabel: "元/吨",
            description: "压榨利润 · 豆油-豆粕 · 季节性 + 大豆压榨周期"
        ),
        SpreadPair(
            id: "p-y", name: "棕榈-豆油",
            category: .跨品种,
            leg1: SpreadLeg(instrumentID: "P0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "Y0", ratio: -1),
            unitLabel: "元/吨",
            description: "油脂替代关系 · 棕榈油-豆油 · 春夏窄 / 秋冬宽"
        ),
        SpreadPair(
            id: "oi-y", name: "菜油-豆油",
            category: .跨品种,
            leg1: SpreadLeg(instrumentID: "OI0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "Y0", ratio: -1),
            unitLabel: "元/吨",
            description: "油脂跨市场 · 菜油-豆油 · 中加贸易摩擦风向标"
        ),

        // ─── 跨品种 · 贵金属 ───
        SpreadPair(
            id: "au-80ag", name: "金银比（au-80ag）",
            category: .跨品种,
            leg1: SpreadLeg(instrumentID: "AU0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "AG0", ratio: -80),
            unitLabel: "元/克",
            description: "经典金银比 · 1g 金 ~ 80g 银 · 危机时金银比扩大"
        ),

        // ─── 跨品种 · 有色 ───
        SpreadPair(
            id: "cu-3al", name: "铜铝比（cu-3al）",
            category: .跨品种,
            leg1: SpreadLeg(instrumentID: "CU0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "AL0", ratio: -3),
            unitLabel: "元/吨",
            description: "工业金属比 · 铜（强周期）vs 铝（中周期）· 4:1 近似"
        ),

        // ─── 跨指数（中金所股指） ───
        SpreadPair(
            id: "IF-IH", name: "沪深300-上证50",
            category: .跨指数,
            leg1: SpreadLeg(instrumentID: "IF0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "IH0", ratio: -1),
            unitLabel: "点",
            description: "大小盘风格 · 沪深300（更偏成长）-上证50（金融保险周期）"
        ),
        SpreadPair(
            id: "IC-IF", name: "中证500-沪深300",
            category: .跨指数,
            leg1: SpreadLeg(instrumentID: "IC0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "IF0", ratio: -1),
            unitLabel: "点",
            description: "成长风格 · 中证500（中盘成长）-沪深300（大盘价值）"
        ),
        SpreadPair(
            id: "IM-IC", name: "中证1000-中证500",
            category: .跨指数,
            leg1: SpreadLeg(instrumentID: "IM0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "IC0", ratio: -1),
            unitLabel: "点",
            description: "小盘风格 · 中证1000-中证500 · 流动性溢价指标"
        ),

        // ─── 跨期限国债 ───
        SpreadPair(
            id: "T-TF", name: "10年-5年国债",
            category: .跨期限,
            leg1: SpreadLeg(instrumentID: "T0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "TF0", ratio: -1),
            unitLabel: "元",
            description: "期限利差 · 10年-5年 · 收益率曲线斜率代理"
        ),
        SpreadPair(
            id: "TL-T", name: "30年-10年国债",
            category: .跨期限,
            leg1: SpreadLeg(instrumentID: "TL0", ratio: 1),
            leg2: SpreadLeg(instrumentID: "T0", ratio: -1),
            unitLabel: "元",
            description: "超长期利差 · 30年-10年 · 长端通胀 / 经济预期"
        ),
    ]

    /// 按分类索引（UI 分组渲染用）
    public static let byCategory: [SpreadPair.Category: [SpreadPair]] = {
        Dictionary(grouping: all, by: { $0.category })
    }()

    /// 按 ID 索引
    public static let byID: [String: SpreadPair] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()
}
