// WP-65 v15.22 batch26 · 麦语言函数签名静态表（60+ 内置函数 · 教学/补全/hover 复用）
//
// 用途：
// - 编辑器自动补全候选词的签名提示（hover popover / status bar）
// - 函数列表面板（按分类浏览 · 一键插入）
// - 文档生成 / trader 学习参考
//
// 与 MaiLangSyntaxHighlighter.builtinFuncs Set 保持一致（一致性测试覆盖 · 漏一个即测试红）

import Foundation

/// 麦语言函数签名（参数列表 + 摘要 + 分类）
public struct MaiLangFunctionSignature: Sendable, Equatable {
    public let name: String
    public let parameters: [String]
    public let summary: String
    public let category: Category

    public init(name: String, parameters: [String], summary: String, category: Category) {
        self.name = name
        self.parameters = parameters
        self.summary = summary
        self.category = category
    }

    /// 格式化为 "MA(序列, 周期 N)" · 无参函数 = "DATE()"
    public var formatted: String {
        "\(name)(\(parameters.joined(separator: ", ")))"
    }

    public enum Category: String, Sendable, Equatable, CaseIterable {
        case 均线 = "均线"
        case 引用 = "引用"
        case 统计 = "统计"
        case 逻辑 = "逻辑"
        case 数学 = "数学"
        case 时间 = "时间"
        case 位置 = "位置"
        case 价量 = "价量"
        case 高级 = "高级"
    }
}

/// 静态签名注册表（与 builtinFuncs 一致 · 一致性测试覆盖）
public enum MaiLangFunctionSignatures {

    /// 字典查询（O(1)）· 用于 hover / status bar 实时显示
    public static let all: [String: MaiLangFunctionSignature] = {
        var dict: [String: MaiLangFunctionSignature] = [:]
        for s in entries { dict[s.name] = s }
        return dict
    }()

    /// 全部签名（按分类有序 · 用于函数列表面板渲染）
    public static let entries: [MaiLangFunctionSignature] = [
        // 均线
        sig("MA",   ["序列", "周期 N"], "简单移动平均（N 日均值）",      .均线),
        sig("EMA",  ["序列", "周期 N"], "指数移动平均（近期权重高）",    .均线),
        sig("SMA",  ["序列", "周期 N", "权重 M"], "平滑移动平均 SMA(X,N,M)=(M·X + (N-M)·SMA1)/N", .均线),
        sig("DMA",  ["序列", "权重序列"], "动态移动平均（每日权重变化）",   .均线),
        sig("WMA",  ["序列", "周期 N"], "加权移动平均（线性递减权重）",    .均线),
        // 引用
        sig("REF",  ["序列", "偏移 N"], "向前引用 N 周期前的值",          .引用),
        sig("BARSLAST", ["条件"], "上次条件成立至今的周期数",             .引用),
        sig("HHVBARS",  ["序列", "周期 N"], "N 周期内最高值距今周期数",     .引用),
        sig("LLVBARS",  ["序列", "周期 N"], "N 周期内最低值距今周期数",     .引用),
        sig("BARSSINCE", ["条件"], "首次条件成立至今周期数",              .引用),
        sig("BARSCOUNT", ["序列"], "序列有效数据周期数",                  .引用),
        sig("VALUEWHEN", ["条件", "序列"], "条件最近一次成立时的序列值",     .引用),
        sig("FILTER",   ["条件", "周期 N"], "条件去重过滤（连续命中只保留首次）", .引用),
        sig("BACKSET",  ["条件", "周期 N"], "向前回填 N 周期",            .引用),
        // 统计
        sig("HHV",   ["序列", "周期 N"], "N 周期内最高值",               .统计),
        sig("LLV",   ["序列", "周期 N"], "N 周期内最低值",               .统计),
        sig("COUNT", ["条件", "周期 N"], "N 周期内条件成立次数",          .统计),
        sig("SUM",   ["序列", "周期 N"], "N 周期内序列累加",             .统计),
        sig("STD",   ["序列", "周期 N"], "N 周期标准差",                 .统计),
        sig("AVEDEV", ["序列", "周期 N"], "N 周期平均绝对偏差",          .统计),
        sig("VARIANCE", ["序列", "周期 N"], "N 周期方差",               .统计),
        sig("RANGE", ["X", "A", "B"], "X 是否在 [A, B] 区间（含端点）",  .统计),
        sig("MEDIAN", ["序列", "周期 N"], "N 周期中位数",               .统计),
        sig("LASTPEAK", ["序列", "周期 N"], "N 周期最后一个峰值",         .统计),
        // 逻辑
        sig("IF",    ["条件", "真值", "假值"], "三元（条件成立返真值否则假值）", .逻辑),
        sig("CROSS", ["A", "B"], "A 上穿 B（A 上一周期 ≤ B · 当前 > B）",  .逻辑),
        sig("CROSSDOWN", ["A", "B"], "A 下穿 B",                       .逻辑),
        sig("EVERY", ["条件", "周期 N"], "N 周期内条件每次都成立",         .逻辑),
        sig("EXIST", ["条件", "周期 N"], "N 周期内条件曾经成立",           .逻辑),
        sig("LONGCROSS", ["A", "B", "周期 N"], "A 持续 N 周期低于 B 后上穿", .逻辑),
        sig("BETWEEN", ["X", "A", "B"], "X 在 [A, B] 之间（含端点）",     .逻辑),
        sig("IFF",   ["条件", "真值", "假值"], "IF 别名",                .逻辑),
        sig("PEAKBARS", ["序列", "周期 N", "M"], "第 M 个峰距今周期数",   .逻辑),
        sig("TROUGHBARS", ["序列", "周期 N", "M"], "第 M 个谷距今周期数",  .逻辑),
        // 数学
        sig("ABS",  ["X"], "绝对值",                                  .数学),
        sig("MAX",  ["A", "B"], "较大值",                            .数学),
        sig("MIN",  ["A", "B"], "较小值",                            .数学),
        sig("POW",  ["底", "指数"], "幂",                             .数学),
        sig("SQRT", ["X"], "平方根",                                 .数学),
        sig("LOG",  ["X"], "自然对数",                                .数学),
        sig("EXP",  ["X"], "e^X",                                   .数学),
        sig("CEILING", ["X"], "向上取整",                             .数学),
        sig("FLOOR",   ["X"], "向下取整",                             .数学),
        sig("INTPART", ["X"], "取整数部分",                           .数学),
        sig("MOD",  ["A", "B"], "A 对 B 取余",                       .数学),
        sig("ROUND", ["X", "小数位"], "四舍五入",                      .数学),
        sig("SIGN", ["X"], "符号（>0 返 1 / =0 返 0 / <0 返 -1）",     .数学),
        sig("DEVSQ", ["序列", "周期 N"], "N 周期偏差平方和",            .数学),
        sig("SUMBARS", ["序列", "目标"], "累加至序列和达目标的周期数",     .数学),
        sig("MULAR", ["序列", "周期 N"], "N 周期连乘",                 .数学),
        sig("CONST", ["X"], "返回常量",                               .数学),
        sig("LAST",  ["条件", "起", "止"], "条件持续成立的周期数",        .数学),
        // 高级
        sig("SLOPE",   ["序列", "周期 N"], "线性回归斜率",               .高级),
        sig("FORCAST", ["序列", "周期 N"], "线性回归外推",               .高级),
        // 时间
        sig("DATE",    [], "当前日期（YYYYMMDD）",                     .时间),
        sig("TIME",    [], "当前时间（HHMMSS）",                       .时间),
        sig("HOUR",    [], "当前小时（0-23）",                         .时间),
        sig("MINUTE",  [], "当前分钟（0-59）",                         .时间),
        sig("YEAR",    [], "当前年（4 位）",                           .时间),
        sig("MONTH",   [], "当前月（1-12）",                           .时间),
        sig("DAY",     [], "当前日（1-31）",                           .时间),
        sig("WEEKDAY", [], "星期（0-6 · 0=周日）",                     .时间),
        // 位置
        sig("ISLASTBAR", [], "是否末根 K 线（1=是 / 0=否）",             .位置),
        sig("BARPOS",    [], "当前 K 线序号（1-based）",                .位置),
        // 价量
        sig("OPEN",   [], "开盘价",                                   .价量),
        sig("HIGH",   [], "最高价",                                   .价量),
        sig("LOW",    [], "最低价",                                   .价量),
        sig("CLOSE",  [], "收盘价",                                   .价量),
        sig("VOLUME", [], "成交量",                                   .价量),
        sig("AMOUNT", [], "成交额",                                   .价量),
        sig("OPI",    [], "持仓量",                                   .价量),
        // v15.96 补 30 个高频经典指标签名（trader 必用 · BuiltinFunction 注册表已有）
        // 趋势/振荡/动量经典 9 个
        sig("ADX",        ["周期 N"],            "平均趋向指标 ADX（趋势强度 · 默认 14）", .高级),
        sig("BBI",        [],                   "多空指标 BBI（3/6/12/24 均线均值）",      .高级),
        sig("BIAS",       ["周期 N"],            "乖离率（收盘价偏离均线百分比）",          .高级),
        sig("CCI",        ["周期 N"],            "顺势指标 CCI（默认 14）",                .高级),
        sig("CMO",        ["周期 N"],            "钱德动量振荡 CMO（默认 14）",            .高级),
        sig("AR",         ["周期 N"],            "人气指标（默认 26）",                    .高级),
        sig("BR",         ["周期 N"],            "意愿指标（默认 26）",                    .高级),
        sig("AO",         [],                   "动量振荡 AO（5/34 SMA 差）",             .高级),
        sig("COPPOCK",    ["N1", "N2", "N3"],    "库柏克曲线（默认 11/14/10）",            .高级),
        // Aroon 体系 3
        sig("AROONOSC",   ["周期 N"],            "Aroon 振荡器（默认 14）",                .高级),
        sig("AROONL",     ["周期 N"],            "Aroon 多头线",                          .高级),
        sig("AROONS",     ["周期 N"],            "Aroon 空头线",                          .高级),
        // 资金流 / 成交量 3
        sig("CMF",        ["周期 N"],            "蔡金资金流 CMF（默认 20）",              .高级),
        sig("CHO",        ["快周期", "慢周期"],   "蔡金波动指数（默认 3/10）",              .高级),
        sig("ADL",        [],                   "累积/派发线 ADL",                        .高级),
        // 波动相关 5
        sig("ATR",        ["周期 N"],            "真实波动幅度（默认 14）",                .高级),
        sig("ATRPCT",     ["周期 N"],            "ATR 百分比（ATR/CLOSE × 100）",          .高级),
        sig("CHOPPINESS", ["周期 N"],            "震荡指数（>61.8 震荡 / <38.2 趋势）",    .高级),
        sig("ANNUALSTD",  ["周期 N"],            "年化标准差（√252 缩放）",                .高级),
        sig("CHANDELIERL", ["周期 N"],           "吊灯止损多头",                           .高级),
        sig("CHANDELIERS", ["周期 N"],           "吊灯止损空头",                           .高级),
        // BOLL 派生 5
        sig("BOLLU",      ["周期 N", "倍数 M"],  "布林上轨（MID + M × STD · 默认 20/2）",  .高级),
        sig("BOLLM",      ["周期 N"],            "布林中轨（默认 20 周期均线）",            .高级),
        sig("BOLLL",      ["周期 N", "倍数 M"],  "布林下轨（MID - M × STD）",              .高级),
        sig("BOLLW",      ["周期 N", "倍数 M"],  "布林带宽（UPPER-LOWER）",                .高级),
        sig("BOLLPCT",    ["周期 N", "倍数 M"],  "布林位置 %B（价格在带内位置）",          .高级),
        // 跨期/跨品种 + 数学辅助 4
        sig("BASIS",      [],                   "基差（现货 - 期货）",                     .高级),
        sig("BETA",       ["周期 N"],            "Beta 系数（与基准波动相关性）",           .统计),
        sig("CLAMPMAX",   ["X", "上限"],         "上限钳位（X > 上限 取上限）",            .数学),
        sig("CLAMPMIN",   ["X", "下限"],         "下限钳位（X < 下限 取下限）",            .数学),
        // v16.1 · 第 2 批 30 个高频经典指标 · trader 中文期货市场必用 · BuiltinFunction 注册表已有
        // 经典震荡 6
        sig("RSI",        ["周期 N"],            "相对强弱指标（默认 14 · 70 超买 30 超卖）", .高级),
        sig("WR",         ["周期 N"],            "威廉指标（反向 RSI · 默认 14）",         .高级),
        sig("ROC",        ["周期 N"],            "变化率 ROC（默认 12 · 当前 vs N 周期前）", .高级),
        sig("MOM",        ["周期 N"],            "动量指标（默认 12 · CLOSE - REF(CLOSE,N)）", .高级),
        sig("OSC",        ["周期 N"],            "振荡器（默认 9 · CLOSE - MA(CLOSE,N)）",   .高级),
        sig("DPO",        ["周期 N"],            "区间震荡 DPO（默认 20 · 去趋势）",        .高级),
        // KDJ + MACD 三件套 6
        sig("KDJK",       ["周期 N", "M1"],      "KDJ K 值（默认 9/3）",                   .高级),
        sig("KDJD",       ["周期 N", "M1", "M2"],"KDJ D 值（默认 9/3/3）",                  .高级),
        sig("KDJJ",       ["周期 N", "M1", "M2"],"KDJ J 值（3K - 2D · 默认 9/3/3）",        .高级),
        sig("MACDDIF",    ["快", "慢"],          "MACD DIF 差离值（默认 12/26）",          .高级),
        sig("MACDDEA",    ["快", "慢", "M"],     "MACD DEA 信号线（默认 12/26/9）",        .高级),
        sig("MACDBAR",    ["快", "慢", "M"],     "MACD 柱状（(DIF-DEA) × 2）",             .高级),
        // 资金流 / 量价 5
        sig("OBV",        [],                   "能量潮 OBV（量在价先）",                  .高级),
        sig("MFI",        ["周期 N"],            "资金流量指标（默认 14 · 量价 RSI）",       .高级),
        sig("VWAP",       [],                   "成交量加权平均价 VWAP",                   .高级),
        sig("EMV",        ["周期 N"],            "简易波动指标（默认 14）",                 .高级),
        sig("PVT",        [],                   "价量趋势 PVT（OBV 升级版）",              .高级),
        // 中国市场情绪 3
        sig("PSY",        ["周期 N"],            "心理线（默认 12 · N 周期上涨日占比）",    .高级),
        sig("VR",         ["周期 N"],            "容量比率（默认 26 · 强弱量能）",          .高级),
        sig("CR",         ["周期 N"],            "CR 意愿指标（默认 26 · 多空动能）",       .高级),
        // 高频均线 3
        sig("TEMA",       ["周期 N"],            "三重指数移动均线（默认 9 · 滞后小）",     .均线),
        sig("DEMA",       ["周期 N"],            "双重指数 MA（默认 9）",                  .均线),
        sig("HMA",        ["周期 N"],            "Hull 移动平均（默认 9 · 平滑+灵敏）",     .均线),
        // 进阶振荡 4
        sig("PSAR",       ["加速因子", "上限"],   "抛物线 SAR（默认 0.02/0.2 · 趋势止损）",  .高级),
        sig("ULTOSC",     ["快", "中", "慢"],    "终极振荡器（默认 7/14/28）",             .高级),
        sig("STOCHRSI",   ["周期 N"],            "随机 RSI（默认 14 · RSI 二次振荡）",      .高级),
        sig("STOCH",      ["周期 N", "K周期", "D周期"], "随机指标 KD（默认 9/3/3）",         .高级),
        // 平滑 / 转折预警 + 相关性 3
        sig("TRIX",       ["周期 N"],            "三重指数平滑（默认 12 · 长趋势过滤）",    .高级),
        sig("MASS",       ["快", "慢"],          "Mass 指数（默认 9/25 · 转折预警）",       .高级),
        sig("CORREL",     ["序列 X", "序列 Y", "周期 N"], "皮尔逊相关系数（默认 20）",       .统计),
    ]

    /// v15.22 batch35 · 模糊搜索（name + summary 均不区分大小写 · 中文 summary 不受影响 · 空 query → 返回全部）
    /// v15.96 修：summary 改用 localizedCaseInsensitiveContains · 避免 summary 含英文缩写时大小写不一致
    public static func search(_ query: String) -> [MaiLangFunctionSignature] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        let upper = trimmed.uppercased()
        return entries.filter { sig in
            sig.name.uppercased().contains(upper) || sig.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// 按分类分组（用于函数列表面板有序渲染）
    public static var byCategory: [(MaiLangFunctionSignature.Category, [MaiLangFunctionSignature])] {
        let groups = Dictionary(grouping: entries, by: { $0.category })
        return MaiLangFunctionSignature.Category.allCases.compactMap { cat in
            guard let arr = groups[cat], !arr.isEmpty else { return nil }
            return (cat, arr)
        }
    }

    private static func sig(_ name: String, _ params: [String],
                            _ summary: String,
                            _ cat: MaiLangFunctionSignature.Category) -> MaiLangFunctionSignature {
        MaiLangFunctionSignature(name: name, parameters: params, summary: summary, category: cat)
    }
}
