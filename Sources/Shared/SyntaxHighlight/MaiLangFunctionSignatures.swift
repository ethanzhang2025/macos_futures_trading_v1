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
    ]

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
